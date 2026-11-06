#!/usr/bin/env bash
# Export our local commits (on top of the fetched upstream revision) from each
# project in src/ to patches/<path>/NNNN-*.patch.
#
# usage: scripts/save-patches.sh [project-path ...]   (default: all in sources.list)
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
paths=("$@")
[ ${#paths[@]} -gt 0 ] || mapfile -t paths < <(grep -vE '^\s*(#|$)' "$TOP/sources.list" | awk '{print $1}')

for path in "${paths[@]}"; do
  dir="$TOP/src/$path"
  [ -d "$dir/.git" ] || continue
  # Base: the revision pinned in sources.list, else the last fetched one.
  base="$(awk -v p="$path" '$1==p && $3 ~ /^[0-9a-f]{40}$/ {print $3}' "$TOP/sources.list")"
  [ -n "$base" ] || base="$(git -C "$dir" rev-parse FETCH_HEAD 2>/dev/null)" || continue
  [ "$(git -C "$dir" rev-list --count "$base..HEAD")" -gt 0 ] || continue
  rm -rf "$TOP/patches/$path"
  mkdir -p "$TOP/patches/$path"
  git -C "$dir" format-patch -q --no-signature -o "$TOP/patches/$path" "$base..HEAD"
  echo "saved $path: $(ls "$TOP/patches/$path" | wc -l) patch(es)"
done
