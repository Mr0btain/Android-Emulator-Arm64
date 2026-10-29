#!/usr/bin/env bash
# Replace x86-64 binaries in the Android SDK with native arm64 ones from the
# host (Ubuntu packages). Originals are moved to <dir>/.x86_64-orig/ so this
# is reversible with --restore. Safe to re-run.
set -euo pipefail

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
GRADLE_PROPS="$HOME/.gradle/gradle.properties"

# SDK tool name -> host command name (when they differ).
declare -A HOST_NAME=(
  [make_f2fs]=""          # no flag-compatible host equivalent; leave alone
  [make_f2fs_casefold]=""
)

is_x86_elf() { file -b "$1" 2>/dev/null | grep -q 'ELF 64-bit.*x86-64'; }

fix_dir() {
  local dir="$1" f name host
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -f "$f" ] && [ ! -L "$f" ] && is_x86_elf "$f" || continue
    name="$(basename "$f")"
    host="${HOST_NAME[$name]-$name}"
    # Some Debian packages only install under /usr/lib/android-sdk.
    if [ -n "$host" ] && ! command -v "$host" >/dev/null; then
      for alt in /usr/lib/android-sdk/{platform-tools,build-tools/debian}/"$host"; do
        [ -x "$alt" ] && host="$alt" && break
      done
    fi
    if [ -z "$host" ] || ! host="$(command -v "$host")"; then
      echo "  skip  $name (no native replacement)"
      continue
    fi
    mkdir -p "$dir/.x86_64-orig"
    mv "$f" "$dir/.x86_64-orig/$name"
    ln -s "$host" "$f"
    echo "  link  $name -> $host"
  done
}

restore_dir() {
  local dir="$1" f
  [ -d "$dir/.x86_64-orig" ] || return 0
  for f in "$dir/.x86_64-orig"/*; do
    rm -f "$dir/$(basename "$f")"
    mv "$f" "$dir/"
  done
  rmdir "$dir/.x86_64-orig"
  echo "  restored $dir"
}

set_gradle_aapt2() {
  local aapt2 key=android.aapt2FromMavenOverride
  aapt2="$(command -v aapt2)"
  mkdir -p "$(dirname "$GRADLE_PROPS")"
  touch "$GRADLE_PROPS"
  if grep -q "^$key=" "$GRADLE_PROPS"; then
    sed -i "s|^$key=.*|$key=$aapt2|" "$GRADLE_PROPS"
  else
    echo "$key=$aapt2" >> "$GRADLE_PROPS"
  fi
  echo "  $GRADLE_PROPS: $key=$aapt2"
}

dirs=("$SDK/platform-tools" "$SDK"/build-tools/*)

if [ "${1:-}" = "--restore" ]; then
  for d in "${dirs[@]}"; do restore_dir "$d"; done
  sed -i '/^android.aapt2FromMavenOverride=/d' "$GRADLE_PROPS" 2>/dev/null || true
  exit 0
fi

for d in "${dirs[@]}"; do
  echo "== $d"
  fix_dir "$d"
done
set_gradle_aapt2
