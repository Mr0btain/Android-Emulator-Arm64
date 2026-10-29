# Toolchain findings (emu-master-dev, emulator 35.6.3)

## How the build picks a toolchain

- `cmake.py --target linux_aarch64` → `toolchain-linux-aarch64.cmake`
  → `toolchain.cmake` → `android/scripts/unix/gen-android-sdk-toolchain.sh`
  generates wrapper scripts in `out/build/toolchain/`.
- For `linux-aarch64` the generator **already uses the host GNU toolchain**
  (`/usr/bin/aarch64-linux-gnu-{gcc,g++,ar,...}`, `SYSROOT=/`, libstdc++),
  not AOSP clang. Google uses this for cross-builds on Debian-ish hosts. On a
  native arm64 Ubuntu machine those binaries are just the system GCC (15.2).
- Rust is off for linux-aarch64 upstream (`configure_rust` is commented out).

## What had to change (patches/external/qemu)

1. `toolchain.cmake` `_get_host_tag()` hard-coded every Linux host as
   `linux-x86_64`, so it treated our build as a cross-build. Now it checks `uname -m`.
2. `gen-android-sdk-toolchain.sh --print=libcplusplus` returned the cross
   path `/usr/aarch64-linux-gnu/lib/libstdc++.so.6`. Now it prefers the
   multiarch path `/usr/lib/aarch64-linux-gnu/`.
3. `aemu/tasks/{configure,compile}.py` used only the prebuilt
   `prebuilts/cmake/linux-x86`. Now they fall back to `cmake` on PATH.
4. `utils/aosp_dir.shi` panicked if `prebuilts/clang` was missing. That check is
   now skipped on `Linux aarch64`.

## Handled in scripts/build.sh (no patch needed)

- `CMAKE_MAKE_PROGRAM=/usr/bin/ninja`: the build puts
  `android/third_party/chromium/depot_tools` first in PATH, and its `ninja`
  shim only knows the x86 binaries.
- `CMAKE_POLICY_VERSION_MINIMUM=3.5`: CMake 4.x dropped compatibility with
  `cmake_minimum_required(<3.5)`, which many third_party CMakeLists use.
- Don't pass `--aosp` to cmake.py (it's typed as str but used as a Path); the default
  (`external/qemu/../..` = `src/`) is correct.

## Configure warnings that are expected

- No netsim for this platform → Bluetooth/Wi-Fi emulation needs a remote netsim.
- RUST disabled.
- No git version tag (shallow clone).
