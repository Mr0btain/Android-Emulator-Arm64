#!/usr/bin/env bash
# Build a .deb of the emulator:
#   /usr/lib/android-emulator/emulator/          the SDK "emulator" package (+ package.xml)
#   /usr/bin/android-emulator-sdk-link           links it into a user's SDK
# A system package can't install into ~/Android/Sdk, so after installing, each
# user runs `android-emulator-sdk-link` (once; the link survives upgrades).
#
# Usage: scripts/package-deb.sh [emulator-dir | release-tarball]
#   default input: out/build/distribution/emulator
# Output: out/release/android-emulator-arm64_<ver>-<rev>_arm64.deb
# Env: DEB_REVISION (default 1), DEB_MAINTAINER
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
IN="${1:-$TOP/out/build/distribution/emulator}"
OUT="$TOP/out/release"
PKG=android-emulator-arm64
PREFIX=/usr/lib/android-emulator

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
if [ -f "$IN" ]; then
  tar -C "$work" -xf "$IN"; SRC="$work/emulator"
else
  SRC="$IN"
fi
[ -x "$SRC/emulator" ] || { echo "No emulator at $SRC" >&2; exit 1; }

ver="$(sed -n 's/^Pkg.Revision=//p' "$SRC/source.properties")"
debver="${ver}-${DEB_REVISION:-1}"
IFS=. read -r major minor micro _ <<<"$ver"
root="$work/root"
mkdir -p "$root$PREFIX" "$root/usr/bin" "$root/DEBIAN" "$root/usr/share/doc/$PKG"
cp -a "$SRC" "$root$PREFIX/emulator"

# Same package.xml as scripts/install-sdk.sh, so sdkmanager/the IDE accept it.
cat > "$root$PREFIX/emulator/package.xml" <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ns2:repository xmlns:ns2="http://schemas.android.com/repository/android/common/02" xmlns:ns3="http://schemas.android.com/repository/android/common/01" xmlns:ns4="http://schemas.android.com/repository/android/generic/01" xmlns:ns5="http://schemas.android.com/repository/android/generic/02" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <license id="android-sdk-license" type="text">Built from AOSP sources (see NOTICE.txt).</license>
  <localPackage path="emulator" obsolete="false">
    <type-details xsi:type="ns5:genericDetailsType"/>
    <revision><major>${major:-0}</major><minor>${minor:-0}</minor><micro>${micro:-0}</micro></revision>
    <display-name>Android Emulator (native linux-aarch64 build)</display-name>
    <uses-license ref="android-sdk-license"/>
  </localPackage>
</ns2:repository>
EOF

cat > "$root/usr/bin/android-emulator-sdk-link" <<EOF
#!/bin/sh
# Point an Android SDK's emulator/ at the packaged native arm64 emulator.
# Usage: android-emulator-sdk-link [sdk-dir]   (default: \$ANDROID_HOME or ~/Android/Sdk)
#        android-emulator-sdk-link --remove [sdk-dir]
set -eu
TARGET=$PREFIX/emulator
remove=; [ "\${1:-}" = --remove ] && { remove=1; shift; }
SDK="\${1:-\${ANDROID_HOME:-\${ANDROID_SDK_ROOT:-\$HOME/Android/Sdk}}}"
DST="\$SDK/emulator"
if [ -n "\$remove" ]; then
  [ -L "\$DST" ] && [ "\$(readlink "\$DST")" = "\$TARGET" ] && rm "\$DST" && echo "removed \$DST"
  exit 0
fi
mkdir -p "\$SDK"
if [ -L "\$DST" ]; then
  rm "\$DST"
elif [ -e "\$DST" ]; then
  bak="\$DST.bak-\$(date +%Y%m%d-%H%M%S)"
  echo "moving existing \$DST -> \$bak"
  mv "\$DST" "\$bak"
fi
ln -s "\$TARGET" "\$DST"
echo "\$DST -> \$TARGET"
"\$DST/emulator" -version | head -1
EOF
chmod 755 "$root/usr/bin/android-emulator-sdk-link"

cp "$SRC/NOTICE.txt" "$root/usr/share/doc/$PKG/" 2>/dev/null || true
cat > "$root/usr/share/doc/$PKG/README" <<EOF
Native linux-aarch64 build of the Android Emulator $ver.
After installing, run once per user:  android-emulator-sdk-link
(links \$ANDROID_HOME or ~/Android/Sdk/emulator to $PREFIX/emulator).
EOF

# Runtime dependencies from the ELF files, ignoring libraries bundled in the
# package itself (lib64/, qemu/..., etc.). Optional Qt image-format plugins
# are skipped (the tiff one wants libtiff.so.5, which 26.04 doesn't ship;
# it simply isn't loaded).
deps=""
if command -v dpkg-shlibdeps >/dev/null; then
  mkdir -p "$work/shl/debian"
  printf 'Source: %s\n\nPackage: %s\nArchitecture: arm64\n' "$PKG" "$PKG" > "$work/shl/debian/control"
  mapfile -t elfs < <(find "$root$PREFIX" -type f -perm -u+x -exec sh -c 'file -b "$1" | grep -q "^ELF.*aarch64.*dynamic"' _ {} \; -print | grep -v /plugins/imageformats/)
  mapfile -t libdirs < <(find "$root$PREFIX" -name '*.so*' -printf '%h\n' | sort -u)
  ldpath=$(IFS=:; echo "${libdirs[*]}")
  deps=$(cd "$work/shl" && LD_LIBRARY_PATH="$ldpath" dpkg-shlibdeps -O --ignore-missing-info \
           -xlibc6-dbg "${elfs[@]}" 2>/dev/null | sed -n 's/^shlibs:Depends=//p') || deps=""
fi
[ -n "$deps" ] || deps="libc6 (>= 2.43), libstdc++6, libx11-6, libxcb1, libpulse0, libuuid1, libunwind8"

size=$(du -sk "$root" | cut -f1)
cat > "$root/DEBIAN/control" <<EOF
Package: $PKG
Version: $debver
Architecture: arm64
Maintainer: ${DEB_MAINTAINER:-Android-Emulator-Arm64 builders <noreply@github.com>}
Installed-Size: $size
Depends: $deps
Section: devel
Priority: optional
Homepage: https://android.googlesource.com/platform/external/qemu
Description: Android Emulator $ver, native build for linux-aarch64
 QEMU-based Android Emulator built natively for arm64 Linux from AOSP
 sources. Installs to $PREFIX/emulator; run android-emulator-sdk-link
 once per user to use it from an Android SDK (Android Studio, IntelliJ,
 avdmanager). Use -accel on where /dev/kvm is available.
EOF

mkdir -p "$OUT"
deb="$OUT/${PKG}_${debver}_arm64.deb"
dpkg-deb --root-owner-group -Zxz --build "$root" "$deb" >/dev/null
(cd "$OUT" && sha256sum "$(basename "$deb")" > "$(basename "$deb").sha256")
ls -lh "$deb"
dpkg-deb -f "$deb" Depends
