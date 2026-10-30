#include "ArtSymbols.hpp"
#include <dlfcn.h>
#include <elf.h>
#include <fstream>
#include <sstream>
#include <cstring>
#include <limits>

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
void* ArtSymbols::exact(std::string_view name) const {
    std::string symbol(name);
    if (void* dynamic=dlsym(RTLD_DEFAULT,symbol.c_str())) return dynamic;
    return resolve(name,false);
}
void* ArtSymbols::prefix(std::string_view name) const { return resolve(name,true); }
void* ArtSymbols::resolve(std::string_view requested,bool prefix_match) const {
    if (!ready()) return nullptr;
    auto header=reinterpret_cast<const Elf64_Ehdr*>(image_.data());
    auto sections=reinterpret_cast<const Elf64_Shdr*>(image_.data()+header->e_shoff);
    for (int kind=0;kind<2;kind++) {
        std::uint32_t type=kind==0?SHT_DYNSYM:SHT_SYMTAB;
        for (int i=0;i<header->e_shnum;i++) {
            const auto& section=sections[i];
            if (section.sh_type!=type || section.sh_link>=header->e_shnum ||
                section.sh_entsize!=sizeof(Elf64_Sym) ||
                !within(image_.size(),section.sh_offset,section.sh_size)) continue;
            const auto& strings=sections[section.sh_link];
            if (strings.sh_type!=SHT_STRTAB ||
                !within(image_.size(),strings.sh_offset,strings.sh_size)) continue;
            const auto* symbols=reinterpret_cast<const Elf64_Sym*>(image_.data()+section.sh_offset);
            const char* strtab=reinterpret_cast<const char*>(image_.data()+strings.sh_offset);
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
                    return reinterpret_cast<void*>(load_bias_+sym.st_value);
            }
        }
    }
    return nullptr;
}
