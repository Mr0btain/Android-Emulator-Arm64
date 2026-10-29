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
