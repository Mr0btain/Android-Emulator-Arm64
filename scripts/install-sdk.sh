#!/usr/bin/env bash
# Install the built emulator (out/build/distribution/emulator) into the
# Android SDK as the "emulator" package. An existing emulator/ is moved to
# emulator.bak-<timestamp>. Writes package.xml so sdkmanager, avdmanager and
# the IDE treat it as installed (and system images' emulator dependency is met).
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
SRC="$TOP/out/build/distribution/emulator"
DST="$SDK/emulator"

[ -x "$SRC/emulator" ] || { echo "No build at $SRC; run scripts/build.sh first." >&2; exit 1; }

rev="$(sed -n 's/^Pkg.Revision=//p' "$SRC/source.properties")"
IFS=. read -r major minor micro _ <<<"$rev"

if [ -e "$DST" ]; then
  bak="$DST.bak-$(date +%Y%m%d-%H%M%S)"
  echo "Moving existing $DST -> $bak"
  mv "$DST" "$bak"
fi

echo "Installing emulator $rev -> $DST"
cp -a "$SRC" "$DST"

cat > "$DST/package.xml" <<EOF
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

"$DST/emulator" -version | head -1
