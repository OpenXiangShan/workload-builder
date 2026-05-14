#!/usr/bin/env bash
set -e

STARTUP_FILE="$(realpath "$1")"
SBI_BUILD_DIR="$(realpath "$2")"
DTS_TEMPLATE_DIR="$(realpath "$3")"
KERNEL_IMAGE="$(realpath "$4")"
WORKLOAD_BUILD_DIR="$(realpath "$5")"
CPIO_ARCHIVE="$WORKLOAD_BUILD_DIR/rootfs.cpio"
DEFAULT_DTB="${DEFAULT_DTB:-xiangshan}"
DTB_MEMORY_PROFILE="${DTB_MEMORY_PROFILE:-}"
DTB_MIN_MEMORY_BYTES="${DTB_MIN_MEMORY_BYTES:-}"

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
dtb_memory_size_bytes() {
    local dts_file="$1"
    local cells
    cells="$(
        awk '
            /device_type[[:space:]]*=[[:space:]]*"memory"/ { in_memory = 1 }
            in_memory && /reg[[:space:]]*=/ {
                line = $0
                while (line !~ /;/ && (getline more) > 0) {
                    line = line " " more
                }
                gsub(/[<>;]/, " ", line)
                n = split(line, fields, /[[:space:]]+/)
                count = 0
                for (i = 1; i <= n; i++) {
                    if (fields[i] ~ /^(0x[0-9a-fA-F]+|[0-9]+)$/) {
                        values[++count] = fields[i]
                    }
                }
                if (count >= 4) {
                    print values[3], values[4]
                    exit
                }
            }
        ' "$dts_file"
    )"
    if [ -z "$cells" ]; then
        return 1
    fi
    set -- $cells
    local high="$1"
    local low="$2"
    printf '%s\n' $(( high * 4294967296 + low ))
}

check_dtb_memory_size() {
    local dts_file="$1"
    local min_bytes="$2"
    local memory_bytes
    if ! memory_bytes="$(dtb_memory_size_bytes "$dts_file")"; then
        echo "Cannot determine memory size from DTS: $dts_file" >&2
        exit 1
    fi
    if [ "$memory_bytes" -lt "$min_bytes" ]; then
        echo "DTS memory is too small: $dts_file describes $memory_bytes bytes, need at least $min_bytes bytes" >&2
        exit 1
    fi
}

build-dtb() {
    local dt_dir="$WORKLOAD_BUILD_DIR"/dt
    local dts_template="$1"
    local dts_base
    dts_base="$(basename "$dts_template" .dts.in)"
    local dts_file="$dt_dir/$dts_base.dts"
    local dtb_file="$dt_dir/$dts_base.dtb"
    mkdir -p "$dt_dir"
    sed -e "s/INITRAMFS_BEGIN/$INITRAMFS_BEGIN_HEX/g" \
        -e "s/INITRAMFS_END/$INITRAMFS_END_HEX/g" \
        "$dts_template" > "$dts_file"
    "$DTC" -I dts -O dtb -o "$dtb_file" "$dts_file"
}
for dts_template in "$DTS_TEMPLATE_DIR"/*.dts.in ; do
    build-dtb "$dts_template"
done

# Assemble the image using the selected DTB basename and optional memory profile.
if [ -n "$DTB_MEMORY_PROFILE" ]; then
    DEFAULT_DTB_BASE="$DEFAULT_DTB-mem$DTB_MEMORY_PROFILE"
else
    DEFAULT_DTB_BASE="$DEFAULT_DTB"
fi
DEFAULT_DTB_FILE="$WORKLOAD_BUILD_DIR/dt/$DEFAULT_DTB_BASE.dtb"
DEFAULT_DTS_FILE="$WORKLOAD_BUILD_DIR/dt/$DEFAULT_DTB_BASE.dts"
if ! [ -f "$DEFAULT_DTB_FILE" ]; then
    echo "Default device tree not found: $DEFAULT_DTB_FILE" >&2
    exit 1
fi
if ! [ -f "$DEFAULT_DTS_FILE" ]; then
    echo "Default device tree source not found: $DEFAULT_DTS_FILE" >&2
    exit 1
fi
if [ -n "$DTB_MIN_MEMORY_BYTES" ]; then
    check_dtb_memory_size "$DEFAULT_DTS_FILE" "$DTB_MIN_MEMORY_BYTES"
fi
dd if="$STARTUP_FILE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" status=none
dd if="$DEFAULT_DTB_FILE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$KILOBYTE" seek="$DTB_OFFSET_KB" conv=notrunc status=none
dd if="$SBI_BUILD_DIR/build/platform/generic/firmware/fw_jump.bin" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$KILOBYTE" seek="$SBI_OFFSET_KB" conv=notrunc status=none
dd if="$KERNEL_IMAGE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$MEGABYTE" seek="$KERNEL_OFFSET_MB" conv=notrunc status=none
dd if="$CPIO_ARCHIVE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$MEGABYTE" seek="$INITRAMFS_OFFSET_MB" conv=notrunc status=none
