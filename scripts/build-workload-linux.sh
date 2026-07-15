#!/usr/bin/env bash
set -e

export WORKLOAD_DIR
export WORKLOAD_BUILD_DIR
WORKLOAD_DIR="$(realpath "$1")"
WORKLOAD_BUILD_DIR="$(realpath "$2")"
export SRC_DIR="$WORKLOAD_BUILD_DIR/source"
export PKG_DIR="$WORKLOAD_BUILD_DIR/package"
DOWNLOAD_DIR="$WORKLOAD_BUILD_DIR/download"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(realpath "$SCRIPT_DIR/..")"

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
    rm -f "$cpio_file"
    cd "$root_dir"
    find . | fakeroot cpio -o -H newc > "$cpio_file" 2>/dev/null
}

build-workload-helper() {
    local name="$1"
    local src="$REPO_ROOT/workloads/linux/common/$name.c"
    local out="$WORKLOAD_BUILD_DIR/$name"
    "${CROSS_COMPILE:?CROSS_COMPILE is required}gcc" -O2 -static "$src" -o "$out"
    chmod +x "$out"
}

apply-multihart-package() {
    local harts
    harts="${HARTS:-2}"
    build-workload-helper before_workload
    build-workload-helper after_workload
    python3 "$SCRIPT_DIR/package-multihart-rootfs.py" \
        --pkg-dir "$PKG_DIR" \
        --harts "$harts" \
        --before-workload "$WORKLOAD_BUILD_DIR/before_workload" \
        --after-workload "$WORKLOAD_BUILD_DIR/after_workload"
}

populate-src-dir
rm -rf "$PKG_DIR" && mkdir -p "$PKG_DIR"
bash "$WORKLOAD_DIR/build.sh"
if [[ "${MULTIHART:-0}" == "1" ]]; then
    apply-multihart-package
fi
pack-cpio "$PKG_DIR" "$WORKLOAD_BUILD_DIR/rootfs.cpio"
