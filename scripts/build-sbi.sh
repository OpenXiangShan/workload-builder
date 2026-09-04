#!/usr/bin/env bash
set -e

SBI_SOURCE_DIR="$(realpath "$1")"
SBI_BUILD_DIR="$(realpath "$2")"
BUILD_DIR="$(dirname "$SBI_BUILD_DIR")"
source "$(dirname "${BASH_SOURCE[0]}")/dts-config.sh"

MEGABYTE=$((1024 * 1024))
if [ "${MULTIHART:-0}" = 1 ]; then
    FW_TEXT_START=0x80100000
    FW_JUMP_ADDR=0x88600000
    FW_JUMP_FDT_ADDR=0x80200000
else
    DEFAULT_DTB="${DEFAULT_DTB:-xiangshan}"
    DTS_TEMPLATE_DIR="${DTS_TEMPLATE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../dts}"
    DTS_TEMPLATE_DIR="$(realpath "$DTS_TEMPLATE_DIR")"
    DTS_TEMPLATE="$DTS_TEMPLATE_DIR/$DEFAULT_DTB.dts.in"
    DTS_CONFIG="$(dts_extract_config "$DTS_TEMPLATE")"
    read -r MEM_BEGIN MEM_SIZE CLINT_MMIO <<< "$DTS_CONFIG"
    FW_TEXT_START=$((MEM_BEGIN + MEGABYTE))
    FW_JUMP_ADDR="$(dts_linux_kernel_address "$MEM_BEGIN" "$((2 * MEGABYTE))")"
    FW_JUMP_FDT_ADDR=$((MEM_BEGIN + 1792 * 1024))
fi

# prepare OpenSBI source
mkdir -p "$BUILD_DIR"
rm -rf "$SBI_BUILD_DIR"
cp -r "$SBI_SOURCE_DIR" "$SBI_BUILD_DIR"
cp "$SBI_SOURCE_DIR/../opensbi.config" "$SBI_BUILD_DIR/platform/generic/configs/defconfig"

# Build OpenSBI
cd "$SBI_BUILD_DIR"
patch -p1 < "$SBI_SOURCE_DIR/../opensbi.patch"
# OpenSBI treats any nonempty DEBUG value as an unoptimized debug build.
make DEBUG= PLATFORM=generic FW_JUMP=y FW_TEXT_START="$(printf '0x%x' "$FW_TEXT_START")" FW_JUMP_ADDR="$(printf '0x%x' "$FW_JUMP_ADDR")" FW_JUMP_FDT_ADDR="$(printf '0x%x' "$FW_JUMP_FDT_ADDR")"
