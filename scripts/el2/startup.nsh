@echo -off
# Run by the UEFI shell in \EFI\slbounce\ (boot entry "Ubuntu (EL2 KVM)"):
# install the slbounce hook, then hand over to the EL2 GRUB.
for %i in fs0 fs1 fs2 fs3 fs4 fs5 fs6 fs7
  if exist %i:\EFI\slbounce\slbounce.efi then
    %i:
    cd \EFI\slbounce
    load slbounce.efi
    grubel2.efi
    echo "grubel2.efi returned; dropping to shell"
    goto done
  endif
endfor
echo "slbounce.efi not found on fs0-fs7"
:done
