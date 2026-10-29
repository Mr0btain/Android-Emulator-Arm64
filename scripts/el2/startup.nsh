@echo -off
# Run by the UEFI shell in \EFI\slbounce\ (boot entry "Ubuntu (EL2 KVM)"):
# install the slbounce hook, then hand over to the EL2 GRUB.
# The ESP's fsN number depends on the firmware (fs13 on this X13s), so scan.
for %i run (0 31)
  if exist fs%i:\EFI\slbounce\slbounce.efi then
    fs%i:
    cd \EFI\slbounce
    load slbounce.efi
    grubel2.efi
    echo "grubel2.efi returned; dropping to shell"
    goto done
  endif
endfor
echo "slbounce.efi not found on fs0-fs31"
:done
