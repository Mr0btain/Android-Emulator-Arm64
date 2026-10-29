#!/usr/bin/env bash
# Phase 6: copy slbounce + tcblaunch.exe + a UEFI shell to the ESP under
# \EFI\slbounce\ and add a "UEFI Shell (slbounce)" boot entry set as BootNext
# only (BootOrder is not touched, so the following boot is normal again).
# Needs root. --remove deletes the directory and the boot entry.
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
EL2="$TOP/out/el2"
ESP="${ESP:-/boot/efi}"
DST="$ESP/EFI/slbounce"
LABEL="UEFI Shell (slbounce)"
DISK=/dev/nvme0n1 PART=1

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

entry() { efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\).* $LABEL.*/\1/p"; }

if [ "${1:-}" = "--remove" ]; then
  for n in $(entry); do efibootmgr -q -b "$n" -B; done
  rm -rf "$DST"
  echo "removed $DST and boot entry"
  exit 0
fi

mkdir -p "$DST"
cp "$EL2"/slbounce/out/{sltest,slbounce,dtbhack}.efi "$DST/"
cp /usr/share/efi-shell-aa64/shellaa64.efi "$DST/"
cp -L "$EL2/tcblaunch.exe" "$DST/tcblaunch.exe"                      # 22621.4317
cp "$EL2/tcb/26100.1742/tcblaunch.exe" "$DST/tcb26100.exe"           # fallback
sync

n="$(entry)"
if [ -z "$n" ]; then
  efibootmgr -q -c -d "$DISK" -p "$PART" -L "$LABEL" -l '\EFI\slbounce\shellaa64.efi'
  n="$(entry)"
  # -c puts the new entry first in BootOrder; restore the old order.
  efibootmgr -q -o "$(efibootmgr | sed -n 's/^BootOrder: //p' | sed "s/^$n,//;s/,$n//")"
fi
efibootmgr -q -n "$n"
ls -l "$DST"
efibootmgr | grep -E "^Boot(Next|Order|$n)"
