#!/usr/bin/env bash
set -euo pipefail

source_spec_iso="$(realpath "$1")"
prepared_spec_root="$(realpath -m "$2")"

prepare_dir="$(dirname "$prepared_spec_root")"
mkdir -p "$prepare_dir"
chmod -R u+rwX "$prepared_spec_root" 2>/dev/null || true
rm -rf "$prepared_spec_root"

temp_root=""
cleanup() {
  if [ -n "$temp_root" ]; then
    chmod -R u+rwX "$temp_root" 2>/dev/null || true
    rm -rf "$temp_root" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if ! command -v xorriso >/dev/null 2>&1; then
  echo "xorriso is required to extract $source_spec_iso" >&2
  exit 1
fi

tmp_parent="${SPEC2006_PREPARE_TMPDIR:-${TMPDIR:-/tmp}}"
mkdir -p "$tmp_parent"
temp_root="$(mktemp -d "$tmp_parent/spec-prepare.XXXXXX")"

media_root="$temp_root/media"
staged_spec_root="$temp_root/spec-src"
mkdir -p "$media_root"

xorriso -osirrox on -indev "$source_spec_iso" -extract / "$media_root" >/dev/null

if ! [ -f "$media_root/install.sh" ]; then
  echo "install.sh not found in $source_spec_iso" >&2
  exit 1
fi

(
  cd "$media_root"
  env -u SPEC sh ./install.sh -f -d "$staged_spec_root"
)

mkdir -p "$prepared_spec_root"
cp -R "$staged_spec_root"/. "$prepared_spec_root"/
chmod -R u+rwX "$prepared_spec_root"

(
  cd "$prepared_spec_root"
  . ./shrc >/dev/null
  bin/relocate >/dev/null
)
