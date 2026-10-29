#!/usr/bin/env bash
# Fetch every project in sources.list into src/<path> with plain git.
# Shallow (depth 1) at the listed revision; projects with sparse dirs use a
# blobless partial clone + sparse checkout. Re-running updates in place.
#
# usage: scripts/fetch-sources.sh [-j N] [path-filter-regex]
set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$TOP/src"
BASE_URL="https://android.googlesource.com"
JOBS=4

if [ "${1:-}" = "-j" ]; then JOBS="$2"; shift 2; fi
FILTER="${1:-.}"

fetch_one() {
  local path="$1" name="$2" rev="$3" sparse="${4:-}"
  local dir="$SRC/$path"

  if [ ! -d "$dir/.git" ]; then
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" remote add origin "$BASE_URL/$name"
  fi

  if [ -n "$sparse" ]; then
    git -C "$dir" config remote.origin.promisor true
    git -C "$dir" config remote.origin.partialclonefilter blob:none
    git -C "$dir" sparse-checkout set --cone ${sparse//,/ }
    git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$rev"
  else
    git -C "$dir" fetch -q --depth 1 origin "$rev"
  fi
  git -C "$dir" checkout -q --force FETCH_HEAD
  echo "ok    $path ($(git -C "$dir" rev-parse --short HEAD))"
}
export -f fetch_one
export SRC BASE_URL

grep -vE '^\s*(#|$)' "$TOP/sources.list" | awk -v f="$FILTER" '$1 ~ f' |
  xargs -P "$JOBS" -L 1 bash -c 'fetch_one "$@" || echo "FAIL  $1" >&2' _

# Manifest linkfile/copyfile steps.
link() { [ -e "$SRC/$1" ] && ln -sfn "$1" "$SRC/$2"; }
link build/bazel/toplevel.WORKSPACE WORKSPACE || true
link build/bazel/toplevel.bazelrc .bazelrc || true
link build/bazel/toplevel.bazelversion .bazelversion || true
[ -e "$SRC/external/qemu/android/vscode/emu.code-workspace" ] &&
  cp "$SRC/external/qemu/android/vscode/emu.code-workspace" "$SRC/"
true
