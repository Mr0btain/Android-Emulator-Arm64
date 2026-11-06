#!/usr/bin/env bash
# Rewrite sources.list with the upstream commit each project in src/ was
# fetched at (FETCH_HEAD, i.e. before our patches). Use after a fetch +
# successful build to pin that state for reproducible (CI) builds.
#
# To move to newer upstream: put branch names (emu-master-dev / main) back
# in the revision column, run fetch-sources.sh + apply-patches.sh + build.sh,
# then run this script.
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$TOP/sources.list"
tmp="$(mktemp)"
{
  echo "# <path> <aosp-project> <revision> [sparse-dirs,comma,separated]"
  echo "# From platform/manifest emu-master-dev, minus x86-only host toolchain"
  echo "# prebuilts, windows/darwin groups and test-only projects."
  echo "# Pinned $(date -I) by scripts/pin-sources.sh (branches: emu-master-dev, main)."
  grep -vE '^\s*(#|$)' "$LIST" | while read -r path name _rev sparse; do
    sha=$(git -C "$TOP/src/$path" rev-parse --verify FETCH_HEAD)
    echo "$path $name $sha${sparse:+ $sparse}"
  done
} > "$tmp"
mv "$tmp" "$LIST"
echo "pinned $(grep -vcE '^\s*(#|$)' "$LIST") projects"
