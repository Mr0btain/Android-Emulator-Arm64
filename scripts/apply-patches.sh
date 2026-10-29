#!/usr/bin/env bash
# Apply patches/<path>/*.patch onto src/<path>, starting from the fetched
# upstream revision. Run after scripts/fetch-sources.sh.
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TOP/patches"

find . -name '*.patch' -printf '%h\n' | sed 's|^\./||' | sort -u | while read -r path; do
  dir="$TOP/src/$path"
  if [ ! -d "$dir/.git" ]; then
    echo "skip  $path (not fetched)"; continue
  fi
  git -C "$dir" checkout -q --force FETCH_HEAD
  git -C "$dir" -c user.name=patches -c user.email=patches@localhost \
    am -q --committer-date-is-author-date "$TOP/patches/$path"/*.patch
  echo "ok    $path ($(ls "$TOP/patches/$path"/*.patch | wc -l) patch(es))"
done
