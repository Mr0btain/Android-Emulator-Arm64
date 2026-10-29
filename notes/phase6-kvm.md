# Phase 6: KVM via slbounce (research, 2026-10-29)

## Already in place on this machine
- Kernel 7.0.0-42 has `CONFIG_KVM=y` and ships
  `/lib/firmware/7.0.0-42-generic/device-tree/qcom/sc8280xp-lenovo-thinkpad-x13s-el2.dtb`
  (upstream EL2 variant, 6.16+). No overlay needs to be built.
- Secure Boot is disabled (slbounce requires that).
- GRUB loads the DTB from `/boot/dtb` (symlink to the normal EL1 DTB).
- BIOS N3HET88W (1.60).

## What the EL2 DTB changes vs normal
- Enables the apps SMMU (`iommu@15000000`: reserved -> okay) and adds
  `iommu-map` for all PCIe controllers (no hypervisor to do stage-2 for them).
- Disables the GPU `zap-shader` (the hypervisor normally does the secure handoff).

## Expected losses when booted at EL2
- Remoteprocs (ADSP/CDSP/SLPI): the Qualcomm hypervisor normally boots them;
  Linux can't yet at EL2. ADSP carries audio, battery reporting and USB-C
  orientation/DP altmode on these machines. `qebspil` (stephan-gh/qebspil,
  supports SC8280XP) can start them from UEFI before the switch; kernel
  takeover needs extra patches (codelinaro 6.16/6.17 branches). Treat the EL2
  boot as a "dev mode" boot entry; keep the normal entry as the daily one.

## tcblaunch.exe
- From a Windows arm64 image: `sources/install.wim` (or `install.esd`) in the
  ISO, path inside the image `Windows/System32/tcblaunch.exe`.
  Extract: `7z x install.wim 1/Windows/System32/tcblaunch.exe` or
  `wimlib-imagex extract install.wim 1 /Windows/System32/tcblaunch.exe`.
- Newer builds removed error handling slbounce relies on. Reported working:
  26100.1742 (24H2 RTM), 26100.1, 22621.4317. Reported failing: 22621.2715,
  Canary. Always verify with `sltest.efi` (green line = EL2 reached).
- Ours: `Windows11_Client_arm64_en-us_26300_9457.iso` -> `install.wim` image 1
  -> tcblaunch.exe **10.0.26100.9457**, sha256
  `04b694994054b3e491de9185eaeb842bee629535dc7fef1f9d68c0375d45d954`
  (saved in `out/win/`). Much newer than the reported-good builds: untested.
- WinSxS has a reverse delta (`.../tcbboot_.../r/tcblaunch.exe`) back to
  26100.1, but it's MSDelta **PA31**, which needs Windows'
  UpdateCompression.dll; no Linux tool applies it.
- winbindex only indexes **x64** tcblaunch.exe; no use for arm64.
- arm64 builds come from Microsoft's symbol server:
  `https://msdl.microsoft.com/download/symbols/tcblaunch.exe/<id>/tcblaunch.exe`
  (id = PE timestamp + SizeOfImage). IDs/hashes from LukeMech/hp-omnibook-x14-fe0
  (`rootfs/usr/bin/omnibook-kvm`, TCB_VERSIONS). Downloaded to `out/el2/tcb/<ver>/`:

  | version | id | sha256 | reports |
  |---|---|---|---|
  | 26100.1742 | EC74C165f6000 | 5dfcd025...4770d03d | works on X1E (Yoga Slim 7x), resets OmniBook |
  | 22621.4317 | BEB81838ed000 | 799c8cee...3cf7ff81e | works on sc8280xp (**X13s**) |
  | 26100.4351 | 66A7C7F3100000 | 463520e1...1333e548 | works on X1E |

  Plan: try 26100.1742 first (user's choice), 22621.4317 as fallback.
- Same script's notes: Fedora GRUB can't chainload EFI drivers so they put
  systemd-boot first; kernel args `id_aa64mmfr0.ecv=1` (X1E firmware resets on
  CNTPOFF_EL2) and `cpuidle.off=1` (input lag at EL2); upstream -el2 DTB's
  remoteproc `iommus` hang 7.1+ kernels (we're on 7.0).
- /tmp is a 7 GB tmpfs: extract install.wim under out/, not the scratchpad.

## Steps
1. Get tcblaunch.exe, check its version.
2. Build slbounce (`make`, native gcc works), copy `slbounce.efi`,
   `sltest.efi`, `tcblaunch.exe` to the ESP.
3. Get a UEFI shell (`Shell.efi`, e.g. from edk2) onto the ESP/USB; run
   `sltest.efi tcblaunch.exe` once (needs the user at the keyboard).
4. Load slbounce before GRUB (UEFI Driver#### entry via `efibootmgr -r`, or a
   chainloading EFI step) and add a GRUB entry with `devicetree` pointing at
   the `-el2.dtb`. slbounce only switches when the loaded DTB is EL2-capable,
   so the normal entry is unaffected.
5. Boot the EL2 entry, check `dmesg | grep -i kvm`, `/dev/kvm`, `kvm` group.
6. `emulator -avd arm64-35 -accel on` (patch #6 picks `-cpu host` automatically).
