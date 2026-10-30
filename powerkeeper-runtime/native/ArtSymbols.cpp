#include "ArtSymbols.hpp"
#include <elf.h>
#include <fstream>
#include <sstream>
#include <cstring>
#include <limits>
#include <linux/xz.h>
#include <algorithm>

namespace {
bool within(std::size_t total, std::uint64_t offset, std::uint64_t length) {
    return offset <= total && length <= total - offset;
}
bool ends_in_art(const std::string& path) {
    return path.size() >= 10 && path.compare(path.size()-10, 10, "/libart.so") == 0;
}
}

ArtSymbols::ArtSymbols() {
    std::ifstream maps("/proc/self/maps");
    std::string line;
    while (std::getline(maps, line)) {
        std::istringstream stream(line);
        std::string ranges, perms, offset, dev, inode, path;
        if (!(stream >> ranges >> perms >> offset >> dev >> inode >> path)) continue;
        if (!ends_in_art(path)) continue;
        const auto dash=ranges.find('-');
        if (dash==std::string::npos) continue;
        try {
            std::uintptr_t start=std::stoull(ranges.substr(0,dash), nullptr,16);
            std::uintptr_t file_offset=std::stoull(offset,nullptr,16);
            if (start<file_offset) continue;
            auto candidate=start-file_offset;
            if (!load_bias_ || candidate<load_bias_) {
                path_=path;
                load_bias_=candidate;
            }
        } catch (...) { continue; }
    }
    if (!load_bias_) return;
    std::ifstream file(path_,std::ios::binary|std::ios::ate);
    if (!file) { load_bias_=0; return; }
    auto length=file.tellg();
    if (length<static_cast<std::streamoff>(sizeof(Elf64_Ehdr)) ||
        length>static_cast<std::streamoff>(250ULL<<20)) { load_bias_=0; return; }
    image_.resize(static_cast<std::size_t>(length));
    file.seekg(0,std::ios::beg);
    if (!file.read(reinterpret_cast<char*>(image_.data()),length)) {
        image_.clear();load_bias_=0;return;
    }
    auto hdr=reinterpret_cast<const Elf64_Ehdr*>(image_.data());
    if (std::memcmp(hdr->e_ident,ELFMAG,SELFMAG)!=0 ||
        hdr->e_ident[EI_CLASS]!=ELFCLASS64 ||
        hdr->e_shentsize!=sizeof(Elf64_Shdr) ||
        !within(image_.size(),hdr->e_shoff,static_cast<std::uint64_t>(hdr->e_shnum)*sizeof(Elf64_Shdr))) {
        image_.clear();load_bias_=0;
    }
}
void ArtSymbols::prewarm() {
    // libart .gnu_debugdata is XZ compressed on many Android releases.
    // Do all I/O, malloc and CRC initialization BEFORE suspending ART:
    // callbacks must not acquire linker locks or decode XZ under suspend.
    if (ready()) (void)inflateMiniElf();
}
void* ArtSymbols::exact(std::string_view name) const { return resolve(name,false); }
void* ArtSymbols::prefix(std::string_view name) const { return resolve(name,true); }
void* ArtSymbols::resolve(std::string_view requested,bool prefix_match) const {
    if (!ready()) return nullptr;
    auto found=lookup(image_,requested,prefix_match);
    if (!found && !mini_elf_.empty())
        found=lookup(mini_elf_,requested,prefix_match);
    return found?reinterpret_cast<void*>(load_bias_+found):nullptr;
}
std::uintptr_t ArtSymbols::lookup(const std::vector<std::uint8_t>& elf,
                                  std::string_view requested,bool prefix_match) const {
    if(elf.size()<sizeof(Elf64_Ehdr))return 0;
    auto header=reinterpret_cast<const Elf64_Ehdr*>(elf.data());
    if(std::memcmp(header->e_ident,ELFMAG,SELFMAG)!=0 ||
       header->e_ident[EI_CLASS]!=ELFCLASS64 ||
       header->e_shentsize!=sizeof(Elf64_Shdr) ||
       !within(elf.size(),header->e_shoff,static_cast<std::uint64_t>(header->e_shnum)*sizeof(Elf64_Shdr)))
        return 0;
    auto sections=reinterpret_cast<const Elf64_Shdr*>(elf.data()+header->e_shoff);
    for (int kind=0;kind<2;kind++) {
        std::uint32_t type=kind==0?SHT_DYNSYM:SHT_SYMTAB;
        for (int i=0;i<header->e_shnum;i++) {
            const auto& section=sections[i];
            if (section.sh_type!=type || section.sh_link>=header->e_shnum ||
                section.sh_entsize!=sizeof(Elf64_Sym) ||
                !within(elf.size(),section.sh_offset,section.sh_size)) continue;
            const auto& strings=sections[section.sh_link];
            if (strings.sh_type!=SHT_STRTAB ||
                !within(elf.size(),strings.sh_offset,strings.sh_size)) continue;
            const auto* symbols=reinterpret_cast<const Elf64_Sym*>(elf.data()+section.sh_offset);
            const char* strtab=reinterpret_cast<const char*>(elf.data()+strings.sh_offset);
            std::size_t count=section.sh_size/sizeof(Elf64_Sym);
            for (std::size_t j=0;j<count;j++) {
                const Elf64_Sym& sym=symbols[j];
                if (sym.st_shndx==SHN_UNDEF || !sym.st_value || sym.st_name>=strings.sh_size) continue;
                const char* ptr=strtab+sym.st_name;
                std::size_t remaining=strings.sh_size-sym.st_name;
                const void* end=std::memchr(ptr,0,remaining);
                if (!end) continue;
                std::string_view value(ptr,static_cast<const char*>(end)-ptr);
                if ((!prefix_match && value==requested) ||
                    (prefix_match && value.size()>=requested.size() &&
                     value.substr(0,requested.size())==requested))
                    return sym.st_value;
            }
        }
    }
    return 0;
}
bool ArtSymbols::inflateMiniElf() const {
    if(!ready())return false;
    auto hdr=reinterpret_cast<const Elf64_Ehdr*>(image_.data());
    if(hdr->e_shstrndx>=hdr->e_shnum)return false;
    auto sh=reinterpret_cast<const Elf64_Shdr*>(image_.data()+hdr->e_shoff);
    const auto& names=sh[hdr->e_shstrndx];
    if(!within(image_.size(),names.sh_offset,names.sh_size))return false;
    const char* strings=reinterpret_cast<const char*>(image_.data()+names.sh_offset);
    const std::uint8_t* compressed=nullptr;
    std::size_t compressed_size=0;
    for(int i=0;i<hdr->e_shnum;i++){
        const auto& item=sh[i];
        if(item.sh_name>=names.sh_size)continue;
        const char* name=strings+item.sh_name;
        auto remaining=names.sh_size-item.sh_name;
        if(!std::memchr(name,0,remaining))continue;
        if(std::strcmp(name,".gnu_debugdata")!=0)continue;
        if(!within(image_.size(),item.sh_offset,item.sh_size))return false;
        compressed=image_.data()+item.sh_offset;
        compressed_size=item.sh_size;
        break;
    }
    if(!compressed || !compressed_size)return false;
    static std::once_flag crc_once;
    std::call_once(crc_once,[]{
        xz_crc32_init();
        xz_crc64_init();
    });
    xz_dec* decoder=xz_dec_init(XZ_DYNALLOC,64U<<20);
    if(!decoder)return false;
    std::vector<std::uint8_t> output(1U<<20);
    xz_buf io{};
    io.in=compressed;
    io.in_size=compressed_size;
    io.out=output.data();
    io.out_size=output.size();
    bool ok=false;
    while(true){
        auto state=xz_dec_run(decoder,&io);
        if(state==XZ_STREAM_END){
            output.resize(io.out_pos);
            if(output.size()>=sizeof(Elf64_Ehdr)){
                const auto* hdr=reinterpret_cast<const Elf64_Ehdr*>(output.data());
                ok=std::memcmp(hdr->e_ident,ELFMAG,SELFMAG)==0 &&
                    hdr->e_ident[EI_CLASS]==ELFCLASS64 &&
                    hdr->e_shentsize==sizeof(Elf64_Shdr) &&
                    within(output.size(),hdr->e_shoff,
                        static_cast<std::uint64_t>(hdr->e_shnum)*sizeof(Elf64_Shdr));
            }
            break;
        }
        if(state==XZ_UNSUPPORTED_CHECK)continue;
        if(state!=XZ_OK)break;
        if(io.out_pos>=io.out_size){
            if(output.size()>=(128U<<20))break;
            output.resize(std::min(output.size()*2,static_cast<std::size_t>(128U<<20)));
            io.out=output.data();io.out_size=output.size();
        } else if(io.in_pos>=io.in_size)break;
    }
    xz_dec_end(decoder);
    if(ok)mini_elf_=std::move(output);
    return ok;
}
