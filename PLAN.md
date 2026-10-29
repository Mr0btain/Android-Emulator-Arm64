# Native arm64 Android Emulator for the ThinkPad X13s

## Status

| Phase | State |
|---|---|
| 0 Repo + packages | done |
| 1 SDK tools | adb, fastboot, aapt, aapt2, mke2fs linked natively; Gradle aapt2 override set. Remaining tools need the extra packages below |
| 2 Fetch sources | done: 54 projects, ~17 GB, `scripts/fetch-sources.sh` |
| 3 Toolchain port | done: configures (see `notes/toolchain.md`, 2 patches) |
| 4 Build | done: native `emulator` 35.6.3 + `qemu-system-aarch64` (8 patches total, see `patches/`) |
| 5 Install + run | AVD `arm64-35` (Android 15) runs under TCG: no crash, adb works, boot is very slow (>35 min to system_server FinishBooting) |
| 6 KVM (optional) | done: EL2 boot via slbounce (`scripts/el2-install.sh`), AVD cold-boots in 41 s with `-accel on` |

Goal: build the Android Emulator (`external/qemu`, branch `emu-master-dev`)
natively on this laptop, and fix the rest of the Android SDK so IntelliJ /
Android Studio can build, deploy to and debug on an arm64 AVD.

## Host

| | |
|---|---|
| Machine | Lenovo ThinkPad X13s (Snapdragon 8cx Gen 3, Cortex-X1C/A78C) |
| Arch | aarch64 |
| OS | Ubuntu 26.04.1 LTS |
| CPU / RAM / disk | 8 cores, 14 GB RAM, ~416 GB free |
| KVM | **Not available** (`/dev/kvm` missing; Qualcomm hypervisor owns EL2) |
| Existing SDK | `~/Android/Sdk` — `platform-tools` and `build-tools` are x86-64 binaries and won't run |

Until Phase 6 is done, the emulator runs on QEMU TCG (software CPU
emulation). It will work, but it will be slow.

## Ground rules

- **Plain git, not `repo`.** `sources.list` holds the projects we need
  (taken from the `emu-master-dev` manifest). `scripts/fetch-sources.sh`
  clones or updates each one under `src/`, which keeps the AOSP layout
  (`src/external/qemu`, `src/prebuilts/...`) that the build scripts expect.
- `src/` and `out/` are git-ignored. This repo only tracks our scripts,
  the source list, patches and notes.
- Our changes to upstream projects live as patch files under
  `patches/<project-path>/NNNN-*.patch`. `scripts/apply-patches.sh` applies
  them, so they can be re-applied after every fetch.
- Pin revisions in `sources.list` once a working build exists, so it can
  be reproduced.

## Repo layout

```
PLAN.md                 this file
sources.list            <path> <aosp-project> <branch|sha> [depth]
scripts/
  fetch-sources.sh      git clone/fetch everything in sources.list into src/
  apply-patches.sh      apply patches/ onto src/
  save-patches.sh       export local commits in src/<proj> to patches/
  fix-sdk-tools.sh      swap x86 SDK binaries for native ones (--restore undoes)
  build.sh              configure + build the emulator into out/
  install-sdk.sh        install out/ distribution into ~/Android/Sdk/emulator
patches/                our changes to upstream projects
notes/                  build logs, findings, gotchas
src/        (ignored)   upstream sources
out/        (ignored)   build output
```

---

## Phase 0 — Repo and host packages

1. `git init` this directory, with `.gitignore` covering `src/`, `out/` and `*.log`.
2. Install the host packages (see "Packages" at the end).
3. Check the tools: `clang --version`, `cmake --version`, `ninja --version`,
   `rustc --version`, `python3 --version`.

**Done when:** the system toolchain works and the repo exists.

## Phase 1 — Fix the non-emulator SDK pieces (quick wins)

Gets IntelliJ building and deploying apps, even before there's an emulator.

1. **adb / fastboot:** use Ubuntu's native arm64 `adb` / `fastboot`. Move the
   x86 `~/Android/Sdk/platform-tools/{adb,fastboot}` aside and symlink the
   system binaries in, so the IDE finds them.
2. **aapt2:** get a native arm64 `aapt2`: try Ubuntu's `aapt` package first,
   or a community build, or build one from AOSP later. Then set in
   `~/.gradle/gradle.properties`:
   `android.aapt2FromMavenOverride=/path/to/aapt2`
3. Check the other native tools in `build-tools/*` (`zipalign`, `aidl`,
   `split-select`, ...) and replace whichever ones the builds actually use.
4. Test: build a sample app with Gradle from the command line, then from
   IntelliJ.

**Done when:** `./gradlew assembleDebug` succeeds and `adb devices` runs.

## Phase 2 — Fetch the sources with git

1. Write `sources.list` from the `emu-master-dev` manifest, **leaving out**:
   - everything in the `platform-windows` / `platform-darwin` groups
   - the x86-only host toolchain: `prebuilts/clang/host/linux-x86`,
     `prebuilts/cmake/linux-x86`, `prebuilts/ninja/linux-x86`,
     `prebuilts/python/linux-x86`, `prebuilts/bazel/linux-x86_64`,
     `prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8`
   - `prebuilts/studio/jdk` (use the system JDK)
   - `tools/repohooks`, `external/mobly-bundled-snippets`,
     `prebuilts/android-emulator-build/system-images` (only used for tests)
2. Shallow-clone (`--depth 1`, single branch) wherever the manifest says
   `clone-depth="1"`. Clone the rest shallow too unless we need the history.
3. Do the manifest's `linkfile`/`copyfile` steps in the script
   (`WORKSPACE`, `.bazelrc`, `.bazelversion`, `emu.code-workspace`).
4. Record the disk usage of `src/`.

**Done when:** `scripts/fetch-sources.sh` runs from scratch and is idempotent.

Useful: the prebuilt repos already contain **linux-aarch64** builds of Qt
(`prebuilts/android-emulator-build/qt/linux-aarch64`) and of the QEMU
dependencies (`qemu-android-deps/linux-aarch64`), and `external/qemu` has a
`toolchain-linux-aarch64.cmake`. Google cross-compiles for this target. The
work is making it build *natively* on arm64.

## Phase 3 — Toolchain port (the main work)

The emulator build (`external/qemu/android/build/python/cmake.py` and
`android/build/cmake/toolchain*.cmake`) assumes the x86-64 prebuilt clang,
cmake, ninja and python, plus a generated toolchain wrapper directory
(`android/scripts/gen-android-sdk-toolchain.sh`).

1. Read `toolchain.cmake`, `toolchain-linux-aarch64.cmake`,
   `toolchain-rust.cmake`, and the `aemu/` python build package. Find every
   hard-coded `prebuilts/.../linux-x86` path and every x86/cross assumption.
   Write the findings to `notes/toolchain.md`.
2. Add a "native aarch64 host" mode. Preferably it's a small patch that:
   - uses system `clang`/`clang++`/`lld`/`llvm-ar`, etc., from `PATH`
   - uses system `cmake`, `ninja`, `python3` and `rustc`/`cargo`
   - sets the sysroot to `/` (or drops the sysroot flags) instead of the
     cross sysroot
   - links against system libc++ (or libstdc++, if libc++ causes trouble)
3. Keep the linux-aarch64 Qt / qemu-deps prebuilts if they link cleanly
   against the system glibc. If they don't, switch to system Qt6
   (`qt6-base-dev`) and system libs.
4. Turn off pieces that only cause trouble, at least for the first build:
   crash reporting (breakpad/crashpad uploads), WebRTC/video bridge,
   netsim/root-canal, tests.

**Done when:** `cmake` configures without errors.

## Phase 4 — Build

1. `scripts/build.sh` → configure in `out/`, run `ninja` with
   `-j6` (to leave RAM headroom, since we have 14 GB) and `ccache`.
2. Work through compile and link errors: each fix is a patch in `patches/`
   plus a line in `notes/build-log.md`.
3. Run `out/distribution` / `out/emulator -version`.

**Done when:** a native aarch64 `emulator` and `qemu-system-aarch64` exist
and start.

## Phase 5 — Install and run

1. `scripts/install-sdk.sh` → copy the build into `~/Android/Sdk/emulator`
   (back up anything already there) and write a matching `package.xml`
   so `sdkmanager`/the IDE accept it.
2. Install an **arm64-v8a** system image (e.g. `system-images;android-35;google_apis;arm64-v8a`)
   and create an AVD with `avdmanager`.
3. Boot under TCG: `emulator -avd <name> -accel off -gpu swiftshader_indirect`
   (fall back to `-no-window` and use `scrcpy` if the GUI has problems).
4. Deploy an app from IntelliJ.

**Done when:** an AVD boots and an app installs and runs from the IDE.

### Phase 5 notes

- cmdline-tools 23+ (`latest`) replaced the Java `sdkmanager` with a native
  **x86-64** `android` CLI that won't run here. `avdmanager` is still Java.
  Use `cmdline-tools/22.0/bin/sdkmanager` (the last Java version) to install packages.
- **Black, unresponsive window** after closing and relaunching: Quick Boot
  restored a broken `default_boot` snapshot (log: "Error -1 from the snapshot
  callback"). Also `hw.gpu.mode=auto` meant IDE launches skipped SwiftShader.
  Fix in `~/.android/avd/arm64-35.avd/config.ini`: `hw.gpu.enabled=yes`,
  `hw.gpu.mode=swiftshader_indirect`, `fastboot.forceColdBoot=yes`,
  `fastboot.forceFastBoot=no` (old snapshot moved to `out/avd-snapshot-bak/`).
  In IntelliJ's Device Manager keep Graphics = Software and Boot = Cold.
  Cold boot under KVM: ~45 s; a "System UI isn't responding" dialog may show
  once right after boot (tap Wait).
- sdkmanager recognizes our build as the `emulator` package via the
  `package.xml` that `scripts/install-sdk.sh` writes.

## Phase 6 — (Optional) KVM via EL2

Hardware virtualization makes the emulator usable at real speed, but on the
X13s it means changing the boot chain.

1. Research **slbounce** (TravMurav/slbounce) + the EL2 device-tree overlay
   for sc8280xp. Note the risks and how to recover before touching anything.
2. Set up a separate boot entry so the current boot stays as a fallback.
3. Confirm `/dev/kvm`, then boot the AVD with `-accel on`.
4. If EL2 doesn't work out: try Cuttlefish (also needs KVM) or Waydroid
   (container-based, no KVM) as the fast way to run apps.

---

## Packages (Phase 0)

```
sudo apt install \
  build-essential clang lld llvm libc++-dev libc++abi-dev \
  cmake ninja-build pkg-config ccache python3-venv python3-pip \
  rustc cargo bison flex m4 \
  libgl-dev libegl-dev libgles-dev libvulkan-dev libdrm-dev libgbm-dev \
  libx11-dev libxext-dev libx11-xcb-dev libxcb1-dev libxrandr-dev libxi-dev \
  libpulse-dev libasound2-dev libglib2.0-dev libpixman-1-dev libfdt-dev \
  libusb-1.0-0-dev libudev-dev zlib1g-dev libssl-dev libxml2-dev \
  qt6-base-dev \
  adb fastboot aapt
```

Phase 1 extras (native versions of the remaining SDK build/platform tools;
re-run `scripts/fix-sdk-tools.sh` after installing):

```
sudo apt install zipalign aidl dexdump split-select etc1tool hprof-conv sqlite3
```

Found during Phase 4/5:

```
sudo apt install uuid-dev libunwind-dev
```
(system replacements for prebuilt static libs with broken local-exec TLS,
see notes/toolchain.md)

More may turn up. Add them here when they do.

## Risks / open questions

- The linux-aarch64 prebuilts were built for Google's cross sysroot. They
  might need an older or newer glibc/libc++ than Ubuntu 26.04 ships.
- `emu-master-dev` is moving partly to Bazel. If CMake support has
  bit-rotted, we'll need Bazel for arm64 (from Bazelisk, not the prebuilt).
- Building needs a lot of RAM: watch out for OOM when linking (use `-j4`
  for the link-heavy targets, add swap if needed).
- TCG performance: running an arm64 guest on an arm64 host under TCG is
  still slow. Expect boots to take several minutes.
