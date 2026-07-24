#!/usr/bin/env bash
set -e

STARTUP_FILE="$(realpath "$1")"
SBI_BUILD_DIR="$(realpath "$2")"
DTS_TEMPLATE_DIR="$(realpath "$3")"
KERNEL_IMAGE="$(realpath "$4")"
WORKLOAD_BUILD_DIR="$(realpath "$5")"
CPIO_ARCHIVE="$WORKLOAD_BUILD_DIR/rootfs.cpio"
DEFAULT_DTB="${DEFAULT_DTB:-}"
DTB_MEMORY_PROFILE="${DTB_MEMORY_PROFILE:-}"
DTB_MIN_MEMORY_BYTES="${DTB_MIN_MEMORY_BYTES:-}"
HARTS="${HARTS:-2}"
readonly MULTIHART_MAX_HARTS=128
readonly MULTIHART_KERNEL_OFFSET_MB=134

MEM_BEGIN=$(( 0x80000000 ))
DTB_OFFSET_KB=1536
DTB_MAX_SIZE_KB=512
SBI_OFFSET_KB=1024
KERNEL_OFFSET_MB=2

if [ "${MULTIHART:-0}" = 1 ]; then
    if [ -z "$DEFAULT_DTB" ]; then
        echo "DEFAULT_DTB must be specified when MULTIHART=1; use the complete DTS basename without .dts.in" >&2
        exit 1
    fi
    case "$HARTS" in
        ''|*[!0-9]*) echo "HARTS must be an integer in the range 2..$MULTIHART_MAX_HARTS" >&2; exit 1 ;;
    esac
    if [ "$HARTS" -lt 2 ] || [ "$HARTS" -gt "$MULTIHART_MAX_HARTS" ]; then
        echo "HARTS must be an integer in the range 2..$MULTIHART_MAX_HARTS" >&2
        exit 1
    fi
    DTB_OFFSET_KB=2048
    DTB_MAX_SIZE_KB=1024
    KERNEL_OFFSET_MB="$MULTIHART_KERNEL_OFFSET_MB"
elif [ -z "$DEFAULT_DTB" ]; then
    DEFAULT_DTB=xiangshan
fi

KILOBYTE=1024
MEGABYTE=$(( 1024*1024 ))
KERNEL_SIZE=$(stat -c%s "$KERNEL_IMAGE")
KERNEL_SIZE_MB=$(( (KERNEL_SIZE + MEGABYTE - 1) / MEGABYTE ))
INITRAMFS_OFFSET_MB=$(( KERNEL_OFFSET_MB + KERNEL_SIZE_MB ))
INITRAMFS_SIZE=$(stat -c%s "$CPIO_ARCHIVE")
INITRAMFS_BEGIN_ADDR=$(( MEM_BEGIN + INITRAMFS_OFFSET_MB*MEGABYTE ))
INITRAMFS_END_ADDR=$(( INITRAMFS_BEGIN_ADDR + INITRAMFS_SIZE ))
INITRAMFS_BEGIN_HEX=$(printf "0x%x" "$INITRAMFS_BEGIN_ADDR")
INITRAMFS_END_HEX=$(printf "0x%x" "$INITRAMFS_END_ADDR")
INITRAMFS_BEGIN_HI=$(printf "0x%x" $(( INITRAMFS_BEGIN_ADDR >> 32 )))
INITRAMFS_BEGIN_LO=$(printf "0x%x" $(( INITRAMFS_BEGIN_ADDR & 0xffffffff )))
INITRAMFS_END_HI=$(printf "0x%x" $(( INITRAMFS_END_ADDR >> 32 )))
INITRAMFS_END_LO=$(printf "0x%x" $(( INITRAMFS_END_ADDR & 0xffffffff )))

# Build device tree files
DTC="${DTC:-dtc}"
dtb_memory_range_bytes() {
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
                    print values[1], values[2], values[3], values[4]
                    exit
                }
            }
        ' "$dts_file"
    )"
    if [ -z "$cells" ]; then
        return 1
    fi
    set -- $cells
    local begin_high="$1"
    local begin_low="$2"
    local size_high="$3"
    local size_low="$4"
    printf '%s %s\n' \
        $(( begin_high * 4294967296 + begin_low )) \
        $(( size_high * 4294967296 + size_low ))
}

check_dtb_memory_layout() {
    local dts_file="$1"
    local min_bytes="$2"
    local memory_range
    local memory_begin
    local memory_bytes
    local memory_end_addr
    if ! memory_range="$(dtb_memory_range_bytes "$dts_file")"; then
        echo "Cannot determine memory size from DTS: $dts_file" >&2
        exit 1
    fi
    read -r memory_begin memory_bytes <<< "$memory_range"
    if [ "$memory_begin" -ne "$MEM_BEGIN" ]; then
        printf 'DTS memory must begin at 0x80000000: found 0x%x in %s\n' \
            "$memory_begin" "$dts_file" >&2
        exit 1
    fi
    if [ -n "$min_bytes" ] && [ "$memory_bytes" -lt "$min_bytes" ]; then
        echo "DTS memory is too small: $dts_file describes $memory_bytes bytes, need at least $min_bytes bytes" >&2
        exit 1
    fi
    memory_end_addr=$(( memory_begin + memory_bytes ))
    if [ "$INITRAMFS_END_ADDR" -gt "$memory_end_addr" ]; then
        printf 'Firmware image exceeds DTS memory: image ends at 0x%x, memory ends at 0x%x in %s\n' \
            "$INITRAMFS_END_ADDR" "$memory_end_addr" "$dts_file" >&2
        exit 1
    fi
}

check_multihart_cpu_count() {
    local dts_file="$1"
    local expected_harts="$2"
    local actual_harts
    actual_harts="$(grep -Ec 'device_type[[:space:]]*=[[:space:]]*"cpu"' "$dts_file" || true)"
    if [ "$actual_harts" -ne "$expected_harts" ]; then
        echo "DTS hart count mismatch: expected $expected_harts, found $actual_harts in $dts_file" >&2
        exit 1
    fi
}

check_multihart_checkpoint_reservation() {
    local dts_file="$1"
    if ! awk '
        /@80300000[[:space:]]*\{/ {
            in_node = 1
            found_node = 1
            has_reg = 0
            has_no_map = 0
            next
        }
        in_node {
            if ($0 ~ /reg[[:space:]]*=[[:space:]]*<[[:space:]]*0x0[[:space:]]+0x80300000[[:space:]]+0x0[[:space:]]+0x08300000[[:space:]]*>[[:space:]]*;/) {
                has_reg = 1
            }
            if ($0 ~ /no-map[[:space:]]*;/) {
                has_no_map = 1
            }
            if ($0 ~ /^[[:space:]]*};/) {
                exit !(has_reg && has_no_map)
            }
        }
        END {
            if (!found_node) {
                exit 1
            }
        }
    ' "$dts_file"; then
        echo "DTS checkpoint reservation missing or invalid: expected no-map [0x80300000, 0x88600000) in $dts_file" >&2
        exit 1
    fi
}

check_image_component_size() {
    local component="$1"
    local file="$2"
    local max_bytes="$3"
    local actual_bytes
    actual_bytes="$(stat -c%s "$file")"
    if [ "$actual_bytes" -gt "$max_bytes" ]; then
        echo "$component image is too large: maximum $max_bytes bytes, found $actual_bytes bytes in $file" >&2
        exit 1
    fi
}

check_gcpt_image_size() {
    local file="$1"
    local max_bytes="$2"
    local actual_bytes
    local fallback_bytes
    actual_bytes="$(stat -c%s "$file")"
    if [ "$actual_bytes" -le "$max_bytes" ]; then
        return
    fi

    # Both checkpoint implementations link a no-payload fallback at exactly
    # 1 MiB. In a combined image external OpenSBI occupies that address, so
    # accept only their known fallback signatures and omit them from the
    # packed GCPT slot.
    if [ "${MULTIHART:-0}" = 1 ] && \
        [ "$actual_bytes" -eq $(( max_bytes + 8 )) ]; then
        fallback_bytes="$(od -An -tx1 -j "$max_bytes" -N8 "$file" | tr -d '[:space:]')"
        if [ "$fallback_bytes" = 1305100067800000 ]; then
            return
        fi
    elif [ "${MULTIHART:-0}" != 1 ] && \
        [ "$actual_bytes" -eq $(( max_bytes + 24 )) ]; then
        fallback_bytes="$(od -An -tx1 -j "$max_bytes" -N24 "$file" | tr -d '[:space:]')"
        if [ "$fallback_bytes" = 730050106ff0dfff13000000130000001300000000000000 ]; then
            return
        fi
    fi

    echo "GCPT image is too large: maximum $max_bytes bytes, found $actual_bytes bytes in $file" >&2
    exit 1
}

build-dtb() {
    local dt_dir="$WORKLOAD_BUILD_DIR"/dt
    local dts_template="$1"
    local dts_base
    dts_base="$(basename "$dts_template" .dts.in)"
    local dts_file="$dt_dir/$dts_base.dts"
    local dtb_file="$dt_dir/$dts_base.dtb"
    mkdir -p "$dt_dir"
    sed -e "s/INITRAMFS_BEGIN_HI/$INITRAMFS_BEGIN_HI/g" \
        -e "s/INITRAMFS_BEGIN_LO/$INITRAMFS_BEGIN_LO/g" \
        -e "s/INITRAMFS_END_HI/$INITRAMFS_END_HI/g" \
        -e "s/INITRAMFS_END_LO/$INITRAMFS_END_LO/g" \
        -e "s/INITRAMFS_BEGIN/$INITRAMFS_BEGIN_HEX/g" \
        -e "s/INITRAMFS_END/$INITRAMFS_END_HEX/g" \
        "$dts_template" > "$dts_file"
    "$DTC" -I dts -O dtb -o "$dtb_file" "$dts_file"
}

resolve_default_dtb_base() {
    local default_dtb="$1"
    local memory_profile="$2"

    if [ -z "$memory_profile" ]; then
        printf '%s\n' "$default_dtb"
        return
    fi
    if [[ "$default_dtb" == *-novec ]]; then
        printf '%s\n' "${default_dtb%-novec}-mem${memory_profile}-novec"
        return
    fi
    printf '%s\n' "${default_dtb}-mem${memory_profile}"
}

# Assemble the image using the selected DTB basename and optional memory profile.
DEFAULT_DTB_BASE="$(resolve_default_dtb_base "$DEFAULT_DTB" "$DTB_MEMORY_PROFILE")"
DEFAULT_DTB_TEMPLATE="$DTS_TEMPLATE_DIR/$DEFAULT_DTB_BASE.dts.in"
if ! [ -f "$DEFAULT_DTB_TEMPLATE" ]; then
    echo "Default device tree template not found in dts directory: $DEFAULT_DTB_TEMPLATE" >&2
    exit 1
fi

for dts_template in "$DTS_TEMPLATE_DIR"/*.dts.in ; do
    build-dtb "$dts_template"
done

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
if [ "${MULTIHART:-0}" = 1 ]; then
    check_multihart_cpu_count "$DEFAULT_DTS_FILE" "$HARTS"
    check_multihart_checkpoint_reservation "$DEFAULT_DTS_FILE"
fi
check_dtb_memory_layout "$DEFAULT_DTS_FILE" "$DTB_MIN_MEMORY_BYTES"
SBI_IMAGE="$SBI_BUILD_DIR/build/platform/generic/firmware/fw_jump.bin"
check_gcpt_image_size "$STARTUP_FILE" $(( SBI_OFFSET_KB * KILOBYTE ))
check_image_component_size OpenSBI "$SBI_IMAGE" $(( (DTB_OFFSET_KB - SBI_OFFSET_KB) * KILOBYTE ))
check_image_component_size DTB "$DEFAULT_DTB_FILE" $(( DTB_MAX_SIZE_KB * KILOBYTE ))
dd if="$STARTUP_FILE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$KILOBYTE" count="$SBI_OFFSET_KB" status=none
dd if="$DEFAULT_DTB_FILE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$KILOBYTE" seek="$DTB_OFFSET_KB" conv=notrunc status=none
dd if="$SBI_IMAGE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$KILOBYTE" seek="$SBI_OFFSET_KB" conv=notrunc status=none
dd if="$KERNEL_IMAGE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$MEGABYTE" seek="$KERNEL_OFFSET_MB" conv=notrunc status=none
dd if="$CPIO_ARCHIVE" of="$WORKLOAD_BUILD_DIR/fw_payload.bin" bs="$MEGABYTE" seek="$INITRAMFS_OFFSET_MB" conv=notrunc status=none
