#pragma once
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>
#include <mutex>

// Read-only ELF symbol lookup for the libart.so already loaded in this
// process. Both the exact and prefix LSPlant symbol callbacks are supported.
// Absent/stripped symbols simply disable this optional backend.
class ArtSymbols {
public:
    ArtSymbols();
    void* exact(std::string_view name) const;
    void* prefix(std::string_view name) const;
    bool ready() const { return load_bias_ && !image_.empty(); }
private:
    std::uintptr_t lookup(const std::vector<std::uint8_t>& elf,
                          std::string_view name,bool is_prefix) const;
    bool inflateMiniElf() const;
    void* resolve(std::string_view name, bool prefix_match) const;
    std::uintptr_t load_bias_ = 0;
    std::string path_;
    std::vector<std::uint8_t> image_;
    mutable std::vector<std::uint8_t> mini_elf_;
    mutable std::once_flag debug_once_;
};
