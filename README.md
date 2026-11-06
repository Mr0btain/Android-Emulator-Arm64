# Android Emulator for linux-aarch64

A native **arm64 Linux** build of the Android Emulator (`emulator` +
`qemu-system-aarch64`, version **35.6.3**). Google ships no linux-arm64
emulator, and the SDK pulls in x86-64 binaries that won't run. This repo
builds the emulator from AOSP sources with a small set of patches, packages
it, and installs it into the Android SDK so `avdmanager`, Android Studio and
IntelliJ use it like the official package.

Developed and tested on a Lenovo ThinkPad X13s (Snapdragon 8cx Gen 3,
Ubuntu 26.04): Android 15 (API 35) and Android 17 (API 37) arm64 images boot
in roughly 40–80 s with KVM.

## Install a release

Requirements: arm64 Linux with glibc ≥ 2.43 and GCC 15's libstdc++ (Ubuntu
26.04 or newer), plus an Android SDK in `~/Android/Sdk` (or `$ANDROID_HOME`).

```sh
git clone <this repo> && cd <repo>
# download android-emulator-<ver>-linux-aarch64.tar.xz (+ .sha256) from Releases, then:
scripts/install-sdk.sh android-emulator-35.6.3-linux-aarch64.tar.xz
```

`install-sdk.sh` checks the `.sha256` file if it's next to the tarball and
installs to `$SDK/emulator`. Any existing (e.g. x86-64) emulator is moved to
`emulator.bak-<timestamp>`. It also writes the `package.xml` that lets
`sdkmanager` and the IDE see the package as installed.

Runtime libraries come from the system: X11/xcb, PulseAudio, libstdc++,
libunwind, libuuid. A desktop install already has them.

## Run

```sh
# system image: arm64-v8a only
sdkmanager "system-images;android-35;google_apis;arm64-v8a"
avdmanager create avd -n arm64-35 -k "system-images;android-35;google_apis;arm64-v8a"

emulator -avd arm64-35 -accel on  -gpu swiftshader_indirect   # with /dev/kvm
emulator -avd arm64-35 -accel off -gpu swiftshader_indirect   # TCG: works, very slow
```

Tips:

- **KVM** needs `/dev/kvm`. On Snapdragon laptops the Qualcomm hypervisor
  holds EL2, so there's no KVM by default. An EL2 boot via slbounce (plus a
  patched kernel so battery, audio and suspend still work) lives in the
  separate `kernel-work` repo.
- **Use the software GPU and cold boot.** In the AVD's `config.ini`:
  `hw.gpu.enabled=yes`, `hw.gpu.mode=swiftshader_indirect`,
  `fastboot.forceColdBoot=yes`, `fastboot.forceFastBoot=no`. With
  `hw.gpu.mode=auto` IDE launches skip SwiftShader, and a broken Quick Boot
  snapshot shows a black window. In the IDE's Device Manager, set
  Graphics = Software and Boot = Cold.
- **sdkmanager:** cmdline-tools 23+ replaced the Java `sdkmanager` with an
  x86-64 binary. Use `cmdline-tools/22.0/bin/sdkmanager`.
- **API 37+ images** declare a minimum emulator revision newer than any
  public source (≥ 37.2.11), so sdkmanager would swap in the x86-64 emulator.
  Install them with `scripts/install-sysimg.py` (verifies the SHA-1 and skips
  that dependency). API 36/36.1 install normally.
- **Other SDK tools:** `scripts/fix-sdk-tools.sh` swaps the SDK's x86-64
  `platform-tools`/`build-tools` binaries for native Ubuntu ones (`adb`,
  `aapt2`, `zipalign`, ...) and sets Gradle's aapt2 override. `--restore`
  undoes it.

## Build from source

On arm64 Ubuntu 26.04 (≈ 17 GB of sources, ≈ 36 GB build tree, ~50 min on
8 cores with 14 GB RAM):

```sh
scripts/ci-build.sh                # apt packages, fetch, patch, build, package
# or step by step:
scripts/fetch-sources.sh -j 8      # src/ (pinned revisions from sources.list)
scripts/apply-patches.sh           # patches/ -> src/
scripts/build.sh                   # out/build, JOBS=n to limit parallelism
scripts/package.sh                 # out/release/android-emulator-<ver>-linux-aarch64.tar.xz
scripts/install-sdk.sh             # install the local build
```

`ci-build.sh` lists the apt packages it needs; set `SKIP_APT=1` if they're
already installed.

## CI and releases

`.github/workflows/build.yml` runs the same `scripts/ci-build.sh` in an
`ubuntu:26.04` container on GitHub's free arm64 runner (`ubuntu-24.04-arm`),
with ccache kept between runs.

- **Manual run** (Actions → *Build emulator* → *Run workflow*): builds and
  attaches the tarball to the run as an artifact.
- **Release**: push a tag `v<emulator version>-<n>`, e.g.
  `git tag v35.6.3-1 && git push origin v35.6.3-1`. The workflow builds,
  then creates a GitHub release with the tarball, its SHA-256 and install
  notes.

The free arm64 runners are only available to public repos.

## What's patched

| Project | Patch | Why |
|---|---|---|
| external/qemu | 0001, 0002 | Build natively on aarch64 hosts (host tag, system cmake/ninja, no prebuilt clang) |
| external/qemu | 0003 | Skip breakpad symbol extraction when crash upload is off |
| external/qemu | 0004 | GCC 15 build fixes |
| external/qemu | 0005 | `virt`: fall back to GICv3 under TCG on aarch64 (`gic-version=host` needs KVM) |
| external/qemu | 0006 | arm64 guests on aarch64 Linux: `-cpu host` with KVM, `max` under TCG |
| external/qemu | 0007 | Use system libuuid/libunwind (prebuilt static libs crash: local-exec TLS) |
| hardware/google/gfxstream | 0001 | Missing `<cstdint>` (GCC 15) |
| tools/netsim | 0001 | Missing `<cstdint>` (GCC 15) |

Details and the reasoning behind each are in `notes/toolchain.md`. To change a
patch, commit in `src/<project>` and run `scripts/save-patches.sh <project>`.

## Repo layout

```
README.md
sources.list            <path> <aosp-project> <pinned sha> [sparse dirs]
patches/<project>/      our changes, applied by scripts/apply-patches.sh
scripts/
  fetch-sources.sh      clone/update everything in sources.list into src/ (plain git, shallow)
  apply-patches.sh      apply patches/ onto src/
  build.sh              configure + build (cmake.py --target linux_aarch64)
  package.sh            out/build/distribution/emulator -> release tarball
  install-sdk.sh        install a local build or release tarball into the SDK
  ci-build.sh           all of the above from scratch (used by CI)
  pin-sources.sh        pin sources.list to the fetched revisions
  save-patches.sh       export local commits in src/<project> to patches/
  fix-sdk-tools.sh      replace x86-64 SDK tools with native ones
  install-sysimg.py     install a system image without sdkmanager
notes/
  toolchain.md          build port findings
  build-plan.md         original plan and phase notes (history)
src/  out/              sources and build output (git-ignored)
```

Sources are AOSP (`emu-master-dev` / `main` as of 2026-10, pinned in
`sources.list`). `scripts/pin-sources.sh` explains how to move to newer
upstream.

## License

The emulator and everything under `src/` are AOSP code under their own
licenses (mostly Apache 2.0 / GPLv2 for QEMU; see `NOTICE.txt` in the
package). The patches follow the license of the files they modify.
