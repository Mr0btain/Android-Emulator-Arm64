#!/usr/bin/env bash
# Configure and build the emulator natively for linux-aarch64.
#   out/build         cmake/ninja build tree
#   out/distribution  installable emulator/ directory + zip
#
# usage: scripts/build.sh [extra cmake.py args...]
#   no args            configure + compile (install/strip) + distribution
#   --task configure   run only that task. cmake.py keeps only the LAST
#                      --task given, so don't chain them.
#
# For iterating on compile errors it's faster to run ninja directly:
#   ninja -C out/build -k 0 -j6
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
QEMU="$TOP/src/external/qemu"
mkdir -p "$TOP/out"

# Keep RAM headroom on the 14 GB X13s; override with JOBS=n.
export CMAKE_BUILD_PARALLEL_LEVEL="${JOBS:-6}"

cd "$QEMU"
exec python3 android/build/python/cmake.py \
  --target linux_aarch64 \
  --out "$TOP/out/build" \
  --dist "$TOP/out/distribution" \
  --ccache "$(command -v ccache)" \
  --crash none \
  --cmake_option CMAKE_POLICY_VERSION_MINIMUM=3.5 \
  --cmake_option CMAKE_MAKE_PROGRAM="$(command -v ninja)" \
  --feature no-webrtc \
  --feature no-bazel \
  --task-disable ctest \
  --task-disable accelerationcheck \
  --task-disable emugentest \
  --task-disable genentriestest \
  --task-disable packagesamples \
  --task-disable zipintegrationtests \
  --task-disable integrationtest \
  "$@" 2>&1 | tee "$TOP/out/build.log"
