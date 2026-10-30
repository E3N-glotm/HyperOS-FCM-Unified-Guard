#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p third_party/zygisk
clone_if_missing() {
  url="$1"; dest="$2"
  if [ ! -e "$dest/.git" ]; then
    git clone --depth 1 "$url" "$dest"
  fi
}
clone_if_missing https://github.com/LSPosed/LSPlant.git third_party/lsplant
# Last known LSPlant tree before the 2026-09-24 switch to named std
# modules. The current NDK-only CMake integration does not supply the
# dedicated libcxx std module. Keep the exact revision reproducible.
# This is experimental, not approved for device installation; later
# upstream ART initialization deadlock fixes still require integration.
LSPLANT_PIN=b2f9279014091c83faac094c5fc7c5498261ace8
git -C third_party/lsplant fetch --depth 1 origin "$LSPLANT_PIN"
git -C third_party/lsplant checkout --detach "$LSPLANT_PIN"
git -C third_party/lsplant submodule update --init --recursive --depth 1 lsplant/src/main/jni/external/dex_builder
clone_if_missing https://github.com/LSPosed/Dobby.git third_party/dobby
clone_if_missing https://github.com/tukaani-project/xz-embedded.git third_party/xz-embedded
curl -fLsS --retry 2 https://raw.githubusercontent.com/topjohnwu/zygisk-module-sample/master/module/jni/zygisk.hpp -o third_party/zygisk/zygisk.hpp
{
  echo "LSPlant $(git -C third_party/lsplant rev-parse HEAD)"
  echo "DexBuilder $(git -C third_party/lsplant/lsplant/src/main/jni/external/dex_builder rev-parse HEAD)"
  echo "Dobby $(git -C third_party/dobby rev-parse HEAD)"
  echo "xz-embedded $(git -C third_party/xz-embedded rev-parse HEAD)"
  echo "ZygiskHeader $(sha256sum third_party/zygisk/zygisk.hpp | cut -d ' ' -f1)"
} > dependency-versions.txt
cat dependency-versions.txt
