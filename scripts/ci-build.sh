#!/usr/bin/env bash
# Full build from a clean checkout, as run by .github/workflows/build.yml
# inside an ubuntu:26.04 arm64 container (works the same on any arm64
# Ubuntu 26.04 box): packages -> fetch -> patches -> build -> package.
#
#   JOBS=n          parallel compile jobs (default: nproc)
#   CCACHE_DIR=dir  persistent ccache (CI caches it between runs)
#   SKIP_APT=1      don't install packages (already present)
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TOP"

if [ -z "${SKIP_APT:-}" ]; then
  export DEBIAN_FRONTEND=noninteractive
  SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo
  $SUDO apt-get update -q
  $SUDO apt-get install -y -q --no-install-recommends \
    ca-certificates git curl file xz-utils zip unzip \
    build-essential clang lld llvm libc++-dev libc++abi-dev \
    cmake ninja-build pkg-config ccache python3 python3-venv python3-pip \
    rustc cargo bison flex m4 \
    libgl-dev libegl-dev libgles-dev libvulkan-dev libdrm-dev libgbm-dev \
    libx11-dev libxext-dev libx11-xcb-dev libxcb1-dev libxrandr-dev libxi-dev \
    libpulse-dev libasound2-dev libglib2.0-dev libpixman-1-dev libfdt-dev \
    libusb-1.0-0-dev libudev-dev zlib1g-dev libssl-dev libxml2-dev \
    qt6-base-dev uuid-dev libunwind-dev
fi

# The workspace is bind-mounted and owned by another uid in CI.
git config --global --get-all safe.directory | grep -qx '\*' || git config --global --add safe.directory '*'
git config --global user.name  >/dev/null || git config --global user.name ci
git config --global user.email >/dev/null || git config --global user.email ci@localhost

export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}" CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
export JOBS="${JOBS:-$(nproc)}"

echo "::group::fetch sources"
scripts/fetch-sources.sh -j 8 2> >(tee out-fetch-errors.txt >&2)
if grep -q '^FAIL' out-fetch-errors.txt; then echo "fetch failed" >&2; exit 1; fi
rm -f out-fetch-errors.txt
echo "::endgroup::"

echo "::group::apply patches"
scripts/apply-patches.sh
echo "::endgroup::"

# CI disk is tight: the prebuilt repos' history isn't needed once checked out.
if [ -n "${CI:-}" ]; then
  rm -rf src/prebuilts/android-emulator-build/*/.git
  df -h "$TOP" | tail -1
fi

# Helper projects (flatc, ...) are configured as nested CMake builds with no
# toolchain file, so they use CMake's own compiler lookup. That found nothing
# in the CI container ("CMAKE_CXX_COMPILER not set"); name the compilers.
export CC="${CC:-gcc}" CXX="${CXX:-g++}"
echo "CC=$(command -v "$CC") CXX=$(command -v "$CXX")"

echo "::group::build"
ccache -z >/dev/null || true
rc=0
scripts/build.sh || rc=$?
ccache -s || true
echo "::endgroup::"
if [ "$rc" != 0 ]; then
  # Collect the nested CMake configure logs for the failure artifact.
  mkdir -p out/logs
  find out/build -path '*/CMakeFiles/*' \( -name CMakeConfigureLog.yaml -o -name CMakeError.log \) \
    -newer sources.list -printf '%P\n' 2>/dev/null | while read -r f; do
      mkdir -p "out/logs/$(dirname "$f")"; cp "out/build/$f" "out/logs/$f"
    done
  df -h "$TOP" > out/logs/df.txt || true
  exit "$rc"
fi

scripts/package.sh
