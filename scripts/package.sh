#!/usr/bin/env bash
# Package out/build/distribution/emulator for release:
#   out/release/android-emulator-<Pkg.Revision>-linux-aarch64.tar.xz (+ .sha256)
#   out/release/android-emulator-arm64_<Pkg.Revision>-1_arm64.deb   (+ .sha256)
# The tarball holds a top-level emulator/ directory (the SDK "emulator"
# package). Install it with: scripts/install-sdk.sh <tarball>
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$TOP/out/build/distribution"
OUT="$TOP/out/release"

[ -x "$DIST/emulator/emulator" ] || { echo "No build at $DIST/emulator; run scripts/build.sh first." >&2; exit 1; }
rev="$(sed -n 's/^Pkg.Revision=//p' "$DIST/emulator/source.properties")"
name="android-emulator-${rev}-linux-aarch64"

mkdir -p "$OUT"
rm -f "$OUT/$name".tar.xz*
tar -C "$DIST" --owner=0 --group=0 --sort=name -cf - emulator | xz -T0 -6 > "$OUT/$name.tar.xz"
(cd "$OUT" && sha256sum "$name.tar.xz" > "$name.tar.xz.sha256")
ls -lh "$OUT/$name.tar.xz"
cat "$OUT/$name.tar.xz.sha256"

"$TOP/scripts/package-deb.sh" "$DIST/emulator"
