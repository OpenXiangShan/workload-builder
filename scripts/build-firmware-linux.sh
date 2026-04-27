#!/usr/bin/env bash
set -e

STARTUP_FILE="$(realpath "$1")"
SBI_BUILD_DIR="$(realpath "$2")"
DTS_TEMPLATE_DIR="$(realpath "$3")"
KERNEL_IMAGE="$(realpath "$4")"
WORKLOAD_BUILD_DIR="$(realpath "$5")"
CPIO_ARCHIVE="$WORKLOAD_BUILD_DIR/rootfs.cpio"
DEFAULT_DTB="${DEFAULT_DTB:-xiangshan}"

MEM_BEGIN=$(( 0x80000000 ))
DTB_OFFSET_KB=1536
SBI_OFFSET_KB=1024
KERNEL_OFFSET_MB=2

KILOBYTE=1024
MEGABYTE=$(( 1024*1024 ))
KERNEL_SIZE=$(stat -c%s "$KERNEL_IMAGE")
KERNEL_SIZE_MB=$(( (KERNEL_SIZE + MEGABYTE - 1) / MEGABYTE ))
INITRAMFS_OFFSET_MB=$(( KERNEL_OFFSET_MB + KERNEL_SIZE_MB ))
INITRAMFS_SIZE=$(stat -c%s "$CPIO_ARCHIVE")
INITRAMFS_BEGIN_HEX=$(printf "0x%x" $(( MEM_BEGIN + INITRAMFS_OFFSET_MB*MEGABYTE )))
INITRAMFS_END_HEX=$(printf "0x%x" $(( INITRAMFS_BEGIN_HEX + INITRAMFS_SIZE )))

# Build device tree files
DTC="${DTC:-dtc}"
build-dtb() {
    local dt_dir="$WORKLOAD_BUILD_DIR"/dt
    local dts_template="$1"
    local dts_file="$dt_dir/$(basename "$dts_template" .dts.in).dts"
    local dtb_file="$dt_dir/$(basename "$dts_template" .dts.in).dtb"
    mkdir -p "$dt_dir"
    sed -e "s/INITRAMFS_BEGIN/$INITRAMFS_BEGIN_HEX/g" \
        -e "s/INITRAMFS_END/$INITRAMFS_END_HEX/g" \
        "$dts_template" > "$dts_file"
    "$DTC" -I dts -O dtb -o "$dtb_file" "$dts_file"
}
for dts_template in "$DTS_TEMPLATE_DIR"/*.dts.in ; do
    build-dtb "$dts_template"
done

# Assemble the image
# Using `xiangshan.dtb` as the default device tree unless DEFAULT_DTB is set.
DEFAULT_DTB_FILE="$WORKLOAD_BUILD_DIR/dt/$DEFAULT_DTB.dtb"
if ! [ -f "$DEFAULT_DTB_FILE" ]; then
    echo "Default device tree not found: $DEFAULT_DTB_FILE" >&2
    exit 1
fi
dd if="$STARTUP_FILE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin"
dd if="$DEFAULT_DTB_FILE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$KILOBYTE" seek="$DTB_OFFSET_KB" conv=notrunc
dd if="$SBI_BUILD_DIR/build/platform/generic/firmware/fw_jump.bin" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$KILOBYTE" seek="$SBI_OFFSET_KB" conv=notrunc
dd if="$KERNEL_IMAGE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$MEGABYTE" seek="$KERNEL_OFFSET_MB" conv=notrunc
dd if="$CPIO_ARCHIVE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$MEGABYTE" seek="$INITRAMFS_OFFSET_MB" conv=notrunc
