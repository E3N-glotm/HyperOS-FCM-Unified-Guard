#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to an installed Android NDK (r28c or newer)}"
command -v cmake >/dev/null
command -v ninja >/dev/null
test -f third_party/zygisk/zygisk.hpp
test -f build/powerkeeper-runtime.dex
cmake -S native -B build/native -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 \
  -DANDROID_STL=c++_static
cmake --build build/native --target fcmu_pk
test -s build/native/libfcmu_pk.so
echo "ZYGISK_BRIDGE_COMPILED (EXPERIMENTAL / NOT INSTALLED)"
