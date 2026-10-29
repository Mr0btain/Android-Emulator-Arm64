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

## Build fixes (Phase 4)

All compile failures were GCC 15 strictness, none arm64-specific:
- missing `<cstdint>` / `<thread>` (libstdc++ 15 no longer includes them transitively):
  crashpad, netsim, gfxstream (2 headers), WifiService.h, MemoryWatch.h, Snapshotter.cpp
- ext4_utils `allocate_inode(info)`: C23 makes `f()` mean `f(void)`.

Packaging: `cmake.py` only runs the last `--task`; the install step is
`cmake --build out/build --target install/strip` → `out/build/distribution/emulator`.

## Runtime bugs found booting under TCG (Phase 5)

1. `gic-version=host` is the default on aarch64 Linux → "requires KVM".
   Patched `hw/arm/virt.c` to fall back to GICv3 under TCG.
2. `-cpu host` is hard-coded for arm64 guests on aarch64 Linux → "can only be used
   with KVM". Patched `android-qemu2-glue/main.cpp` to use `max` without usable KVM.
3. SIGSEGV in `qemu_in_vcpu_thread()` while realizing virtio-snd: `current_cpu`
   (TLS) held garbage. A gdb hardware watchpoint on the TLS slot caught
   libuuid's `get_random_bytes()` writing it. Cause: prebuilt
   `common/e2fsprogs/linux-aarch64/lib/libuuid.a` (and the libunwind
   `linux-aarch64` archives) use local-exec TLS relocations, which alias the
   executable's TLS when linked into a `.so`. Fix: system `libuuid`/`libunwind`.
   Verified: no `R_AARCH64_TLSLE_*` relocations left in any installed `.so`
   (`readelf -r ... | grep TLSLE`), and QEMU runs past device setup.

First TCG boot (4 vCPU, 2 GB, swiftshader): guest kernel + init fine, adb up
within minutes, but system_server takes >35 min and hits ANR/watchdog-style
timeouts. Usable only for smoke tests; KVM (Phase 6) is what makes it practical.

Debugging recipe: gdb with `set follow-fork-mode parent` (the launcher execs
qemu in the same PID; crashpad_handler is a forked child). Copy the unstripped
`out/build/qemu/linux-aarch64/qemu-system-aarch64-headless` over the SDK copy
for symbols.
