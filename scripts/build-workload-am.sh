#!/usr/bin/env bash
set -euo pipefail

export WORKLOAD_DIR
export WORKLOAD_BUILD_DIR
WORKLOAD_DIR="$(realpath "$1")"
WORKLOAD_BUILD_DIR="$(realpath "$2")"
AM_SOURCE_DIR="$(realpath "$3")"
export SRC_DIR="$WORKLOAD_BUILD_DIR/source"
export PKG_DIR="$WORKLOAD_BUILD_DIR/package"
export AM_HOME="$WORKLOAD_BUILD_DIR/am"
export AM_ARCH="${AM_ARCH:-${ARCH:-riscv64-xs}}"
export AM_CPPFLAGS="${CPPFLAGS:-}"
export CPPFLAGS="$AM_CPPFLAGS"
export AM_MAKEARGS="ARCH=$AM_ARCH CROSS_COMPILE=$CROSS_COMPILE"
DOWNLOAD_DIR="$WORKLOAD_BUILD_DIR/download"
script_dir="$(cd "$(dirname "$0")" && pwd)"
fingerprint=$(python3 "$script_dir/am-build-fingerprint.py" "$AM_SOURCE_DIR" "$WORKLOAD_DIR" "$DOWNLOAD_DIR")
if [[ -f "$WORKLOAD_BUILD_DIR/.am-build-fingerprint" && -f "$WORKLOAD_BUILD_DIR/.am-package-fingerprint" &&
      -f "$WORKLOAD_BUILD_DIR/sentinel" && -d "$PKG_DIR" &&
      $(<"$WORKLOAD_BUILD_DIR/.am-build-fingerprint") == "$fingerprint" ]] &&
   package_fingerprint=$(python3 "$script_dir/am-build-fingerprint.py" --package "$PKG_DIR") &&
   [[ $(<"$WORKLOAD_BUILD_DIR/.am-package-fingerprint") == "$package_fingerprint" ]]; then
    printf 'AM build cache hit: %s (%s)\n' "$WORKLOAD_DIR" "$AM_ARCH"
    exit 0
fi

populate-src-dir() {
    mkdir -p "$WORKLOAD_BUILD_DIR"
    rm -rf "$AM_HOME"
    cp -r "$AM_SOURCE_DIR" "$AM_HOME"
    if [[ -e "$SRC_DIR" ]]; then
        rm -rf "$SRC_DIR"
    fi
    if [[ -d "$WORKLOAD_DIR/source" ]]; then
        cp -r "$WORKLOAD_DIR/source" "$SRC_DIR"
    else
        mkdir -p "$SRC_DIR"
    fi
    for file in "$DOWNLOAD_DIR"/* ; do
        if [[ -f "$file" && "$file" != "$DOWNLOAD_DIR"/sentinel ]]; then
            cp "$file" "$SRC_DIR"
        fi
    done
}

populate-src-dir
rm -rf "$PKG_DIR" && mkdir -p "$PKG_DIR"
find "$AM_HOME" -type d -name build -prune -exec rm -rf {} +
bash "$WORKLOAD_DIR/build.sh"

package_fingerprint=$(python3 "$script_dir/am-build-fingerprint.py" --package "$PKG_DIR")
printf '%s\n' "$package_fingerprint" > "$WORKLOAD_BUILD_DIR/.am-package-fingerprint.tmp.$$"
mv "$WORKLOAD_BUILD_DIR/.am-package-fingerprint.tmp.$$" "$WORKLOAD_BUILD_DIR/.am-package-fingerprint"
printf '%s\n' "$fingerprint" > "$WORKLOAD_BUILD_DIR/.am-build-fingerprint.tmp.$$"
mv "$WORKLOAD_BUILD_DIR/.am-build-fingerprint.tmp.$$" "$WORKLOAD_BUILD_DIR/.am-build-fingerprint"
touch "$WORKLOAD_BUILD_DIR"/sentinel
