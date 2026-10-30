cmake_minimum_required(VERSION 3.28)
project(fcmu_powerkeeper LANGUAGES C CXX ASM)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
get_filename_component(ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(VENDOR "${ROOT}/third_party")
if(NOT EXISTS "${VENDOR}/lsplant/lsplant/src/main/jni/CMakeLists.txt"
   OR NOT EXISTS "${VENDOR}/dobby/CMakeLists.txt"
   OR NOT EXISTS "${VENDOR}/xz-embedded/linux/lib/xz/xz_dec_stream.c"
   OR NOT EXISTS "${VENDOR}/zygisk/zygisk.hpp")
    message(FATAL_ERROR "Missing pinned optional dependencies. Run fetch-deps.sh first.")
endif()
set(DOBBY_GENERATE_SHARED OFF CACHE BOOL "" FORCE)
set(DOBBY_DEBUG OFF CACHE BOOL "" FORCE)
set(Plugin.SymbolResolver OFF CACHE BOOL "" FORCE)
set(Plugin.ImportTableReplace OFF CACHE BOOL "" FORCE)
set(Plugin.Android.BionicLinkerUtil OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLE OFF CACHE BOOL "" FORCE)
set(BUILD_TEST OFF CACHE BOOL "" FORCE)
add_subdirectory("${VENDOR}/dobby" "${CMAKE_BINARY_DIR}/dobby")
# The standalone LSPlant build expects a cxx::cxx package normally delivered
# via Android Gradle Prefab. When building directly with the official Android
# NDK toolchain, its libc++ headers/runtime are already supplied by the
# toolchain, so provide only a target bridge for find_package(cxx).
set(LSPLANT_STANDALONE ON CACHE BOOL "" FORCE)
set(cxx_DIR "${CMAKE_CURRENT_LIST_DIR}/cxx-config" CACHE PATH "" FORCE)
set(LSPLANT_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(DEBUG_SYMBOLS_PATH "${CMAKE_BINARY_DIR}/symbols" CACHE PATH "" FORCE)
add_subdirectory("${VENDOR}/lsplant/lsplant/src/main/jni" "${CMAKE_BINARY_DIR}/lsplant")
set(XZ "${VENDOR}/xz-embedded")
add_library(xz_static STATIC
    "${XZ}/linux/lib/xz/xz_crc32.c"
    "${XZ}/linux/lib/xz/xz_crc64.c"
    "${XZ}/linux/lib/xz/xz_dec_lzma2.c"
    "${XZ}/linux/lib/xz/xz_dec_stream.c"
)
target_compile_definitions(xz_static PRIVATE XZ_USE_CRC64)
target_include_directories(xz_static PUBLIC
    "${XZ}/linux/include"
    "${XZ}/linux/include/linux"
    "${XZ}/userspace"
)
option(FCMU_PK_EXPERIMENT_DIAGNOSTICS "Enable scoped pre/post Zygisk trace in experimental binary only" OFF)
add_library(fcmu_pk SHARED Bridge.cpp ArtSymbols.cpp)
target_compile_definitions(fcmu_pk PRIVATE XZ_USE_CRC64)
if(FCMU_PK_EXPERIMENT_DIAGNOSTICS)
    target_compile_definitions(fcmu_pk PRIVATE FCMU_PK_EXPERIMENT_DIAGNOSTICS)
endif()
target_include_directories(fcmu_pk PRIVATE "${VENDOR}/zygisk" "${CMAKE_CURRENT_LIST_DIR}")
target_compile_options(fcmu_pk PRIVATE -Wall -Wextra -Wno-c99-extensions)
target_link_libraries(fcmu_pk PRIVATE dobby lsplant_static dex_builder_static xz_static log dl)
# This separate library is only for a disposable Android app_process test,
# never for Zygisk packaging or startup on the user's primary device.
add_library(fcmu_pk_selftest SHARED Bridge.cpp ArtSymbols.cpp)
target_compile_definitions(fcmu_pk_selftest PRIVATE XZ_USE_CRC64 FCMU_ART_ISOLATED_TEST)
target_include_directories(fcmu_pk_selftest PRIVATE "${VENDOR}/zygisk" "${CMAKE_CURRENT_LIST_DIR}")
target_compile_options(fcmu_pk_selftest PRIVATE -Wall -Wextra -Wno-c99-extensions)
target_link_libraries(fcmu_pk_selftest PRIVATE dobby lsplant_static dex_builder_static xz_static log dl)

