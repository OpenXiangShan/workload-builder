#!/usr/bin/env bash
set -euo pipefail

export WORKLOAD_DIR
export WORKLOAD_BUILD_DIR
WORKLOAD_DIR="$(realpath "$1")"
WORKLOAD_BUILD_DIR="$(realpath "$2")"
export SRC_DIR="$WORKLOAD_BUILD_DIR/source"
export PKG_DIR="$WORKLOAD_BUILD_DIR/package"
DOWNLOAD_DIR="$WORKLOAD_BUILD_DIR/download"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

populate-src-dir() {
    mkdir -p "$WORKLOAD_BUILD_DIR"
    if [[ -e "$SRC_DIR" ]]; then
        rm -rf "$SRC_DIR"
    fi
    if [[ -d "$WORKLOAD_DIR/source" ]]; then
        cp -r "$WORKLOAD_DIR/source" "$SRC_DIR"
    else
        mkdir -p "$SRC_DIR"
    fi
    for file in "$DOWNLOAD_DIR"/* ; do
        if [ "$file" != "$DOWNLOAD_DIR"/sentinel ] ; then
            cp "$file" "$SRC_DIR"
        fi
    done
}

pack-cpio() {
    local root_dir="$1"
    local cpio_file="$2"
    local temp_file
    rm -f "$cpio_file"
    temp_file="$(mktemp "${cpio_file}.tmp.XXXXXX")"
    if ! (cd "$root_dir" && find . -print0 | fakeroot cpio --null -o -H newc > "$temp_file" 2>/dev/null); then
        rm -f "$temp_file"
        echo "Failed to create initramfs: $cpio_file" >&2
        return 1
    fi
    if [ ! -s "$temp_file" ] || ! cpio -it < "$temp_file" >/dev/null 2>&1; then
        rm -f "$temp_file"
        echo "Generated initramfs is empty or invalid: $cpio_file" >&2
        return 1
    fi
    mv "$temp_file" "$cpio_file"
}

apply-multihart-package() {
    local harts
    local workload_name
    harts="${HARTS:-2}"
    workload_name="${MULTIHART_PAYLOAD_DIR:-$(basename "$WORKLOAD_DIR")}"
    python3 "$SCRIPT_DIR/package-multihart-rootfs.py" \
        --pkg-dir "$PKG_DIR" \
        --harts "$harts" \
        --workload-name "$workload_name"
}

populate-src-dir
rm -rf "$PKG_DIR" && mkdir -p "$PKG_DIR"
bash "$WORKLOAD_DIR/build.sh"
if [[ "${MULTIHART:-0}" == "1" ]]; then
    apply-multihart-package
fi
pack-cpio "$PKG_DIR" "$WORKLOAD_BUILD_DIR/rootfs.cpio"
