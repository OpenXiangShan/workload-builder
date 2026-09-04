#!/usr/bin/env bash
set -euo pipefail

BUILDROOT_DIR="$(realpath "$1")"
SBI_BUILD_DIR="$(realpath "$2")"
WORKLOAD_BUILD_DIR="$(realpath "$3")"
IMAGE_DIR="$(realpath -m "$4")"
ARTIFACT_NAME="$5"
DTB_BASENAME="$6"
KERNEL_IMAGE="$(realpath "$7")"
WORKLOAD_ELF="$(realpath "${WORKLOAD_ELF:?WORKLOAD_ELF must be set}")"
BUILD_LOG="$(realpath "${BUILD_LOG:?BUILD_LOG must be set}")"
RUN_COMMAND="$(realpath "${RUN_COMMAND:?RUN_COMMAND must be set}")"
SPEC_CONFIG="$(realpath "${SPEC_CONFIG:?SPEC_CONFIG must be set}")"
GCPT_ELF="$(realpath "${GCPT_ELF:?GCPT_ELF must be set}")"
GCPT_BIN="$(realpath "${GCPT_BIN:?GCPT_BIN must be set}")"
source "$(dirname "${BASH_SOURCE[0]}")/dts-config.sh"

mapfile -t vmlinux_files < <(find "$BUILDROOT_DIR/output/build" -path '*/vmlinux' -type f -print | sort)
if [ "${#vmlinux_files[@]}" -ne 1 ]; then
    echo "Expected exactly one vmlinux under $BUILDROOT_DIR/output/build, found ${#vmlinux_files[@]}" >&2
    exit 1
fi

VMLINUX="${vmlinux_files[0]}"
KERNEL_BUILD_DIR="$(dirname "$VMLINUX")"
SYSTEM_MAP="$KERNEL_BUILD_DIR/System.map"
KERNEL_CONFIG="$KERNEL_BUILD_DIR/.config"
DTB_FILE="$WORKLOAD_BUILD_DIR/dt/$DTB_BASENAME.dtb"
DTS_FILE="$WORKLOAD_BUILD_DIR/dt/$DTB_BASENAME.dts"
SBI_ELF="$SBI_BUILD_DIR/build/platform/generic/firmware/fw_jump.elf"
SBI_CONFIG="$SBI_BUILD_DIR/platform/generic/configs/defconfig"
FIRMWARE_IMAGE="$(realpath "${FIRMWARE_IMAGE:-$WORKLOAD_BUILD_DIR/fw_payload.bin}")"
ROOTFS="$WORKLOAD_BUILD_DIR/rootfs.cpio"

for file in "$SYSTEM_MAP" "$KERNEL_CONFIG" "$DTB_FILE" "$DTS_FILE" "$SBI_ELF" "$SBI_CONFIG" "$FIRMWARE_IMAGE" "$ROOTFS" "$KERNEL_IMAGE" "$WORKLOAD_ELF" "$BUILD_LOG" "$RUN_COMMAND" "$SPEC_CONFIG" "$GCPT_ELF" "$GCPT_BIN"; do
    if [ ! -f "$file" ]; then
        echo "Required debug artifact not found: $file" >&2
        exit 1
    fi
done

dts_config="$(dts_extract_config "$DTS_FILE")"
read -r memory_base memory_size clint_mmio <<< "$dts_config"

KERNEL_DIR="$IMAGE_DIR/kernel"
DT_DIR="$IMAGE_DIR/dt"
SBI_DIR="$IMAGE_DIR/opensbi"
MANIFEST_DIR="$IMAGE_DIR/manifest"
BIN_DIR="$IMAGE_DIR/bin"
ROOTFS_DIR="$IMAGE_DIR/rootfs"
ELF_DIR="$IMAGE_DIR/elf"
CMD_DIR="$IMAGE_DIR/cmd"
CFG_DIR="$IMAGE_DIR/cfg"
GCPT_DIR="$IMAGE_DIR/gcpt"
LOG_DIR="$IMAGE_DIR/logs/build_elf"
STAMP_DIR="$IMAGE_DIR/stamps"
mkdir -p "$KERNEL_DIR" "$DT_DIR" "$SBI_DIR" "$MANIFEST_DIR" "$BIN_DIR" "$ROOTFS_DIR" "$ELF_DIR" "$CMD_DIR" "$CFG_DIR" "$GCPT_DIR" "$LOG_DIR" "$STAMP_DIR"

WORKLOAD_ELF_NAME="$(basename "$WORKLOAD_ELF" .elf)"
cp "$FIRMWARE_IMAGE" "$BIN_DIR/$ARTIFACT_NAME.fw_payload.bin"
cp "$ROOTFS" "$ROOTFS_DIR/$ARTIFACT_NAME.rootfs.cpio"
cp "$WORKLOAD_ELF" "$ELF_DIR/$WORKLOAD_ELF_NAME.elf"
cp "$BUILD_LOG" "$LOG_DIR/$WORKLOAD_ELF_NAME.log"
cp "$RUN_COMMAND" "$CMD_DIR/$ARTIFACT_NAME.run.sh"
cp "$SPEC_CONFIG" "$CFG_DIR/$(basename "$SPEC_CONFIG")"
cp "$GCPT_ELF" "$GCPT_DIR/gcpt.elf"
cp "$GCPT_BIN" "$GCPT_DIR/gcpt.bin"
cp "$VMLINUX" "$KERNEL_DIR/$ARTIFACT_NAME.vmlinux"
cp "$SYSTEM_MAP" "$KERNEL_DIR/$ARTIFACT_NAME.System.map"
cp "$KERNEL_CONFIG" "$KERNEL_DIR/$ARTIFACT_NAME.config"
cp "$DTB_FILE" "$DT_DIR/$ARTIFACT_NAME.dtb"
cp "$DTS_FILE" "$DT_DIR/$ARTIFACT_NAME.dts"
cp "$SBI_ELF" "$SBI_DIR/fw_jump.elf"
cp "$SBI_CONFIG" "$SBI_DIR/defconfig"

kernel_min_offset_mb=2
dtb_offset=$((1792 * 1024))
multihart=false
if [ "${MULTIHART:-0}" = 1 ]; then
    kernel_min_offset_mb=134
    dtb_offset=$((2 * 1024 * 1024))
    multihart=true
fi

megabyte=$((1024 * 1024))
kernel_address_value="$(dts_linux_kernel_address "$memory_base" "$((kernel_min_offset_mb * megabyte))")"
kernel_size=$(stat -c%s "$KERNEL_IMAGE")
kernel_end_address=$((kernel_address_value + kernel_size))
initramfs_address_value=$(( (kernel_end_address + megabyte - 1) / megabyte * megabyte ))
kernel_address=$(printf '0x%x' "$kernel_address_value")
initramfs_address=$(printf '0x%x' "$initramfs_address_value")
dtb_address=$(printf '0x%x' $((memory_base + dtb_offset)))
opensbi_load_address=$(printf '0x%x' $((memory_base + megabyte)))
opensbi_jump_address="$kernel_address"
gcpt_load_address=$(printf '0x%x' "$memory_base")
sha256() {
    sha256sum "$1" | cut -d ' ' -f 1
}

cat > "$MANIFEST_DIR/$ARTIFACT_NAME.json" <<EOF
{
  "case": "$ARTIFACT_NAME",
  "multihart": $multihart,
  "device_tree": {
    "basename": "$DTB_BASENAME",
    "dtb": "dt/$ARTIFACT_NAME.dtb",
    "dts": "dt/$ARTIFACT_NAME.dts",
    "load_address": "$dtb_address",
    "sha256": "$(sha256 "$DTB_FILE")"
  },
  "opensbi": {
    "elf": "opensbi/fw_jump.elf",
    "config": "opensbi/defconfig",
    "load_address": "$opensbi_load_address",
    "jump_address": "$opensbi_jump_address",
    "sha256": "$(sha256 "$SBI_ELF")"
  },
  "gcpt": {
    "elf": "gcpt/gcpt.elf",
    "binary": "gcpt/gcpt.bin",
    "load_address": "$gcpt_load_address",
    "elf_sha256": "$(sha256 "$GCPT_ELF")",
    "binary_sha256": "$(sha256 "$GCPT_BIN")"
  },
  "kernel": {
    "vmlinux": "kernel/$ARTIFACT_NAME.vmlinux",
    "system_map": "kernel/$ARTIFACT_NAME.System.map",
    "config": "kernel/$ARTIFACT_NAME.config",
    "load_address": "$kernel_address",
    "sha256": "$(sha256 "$VMLINUX")"
  },
  "initramfs": {
    "file": "rootfs/$ARTIFACT_NAME.rootfs.cpio",
    "load_address": "$initramfs_address",
    "sha256": "$(sha256 "$ROOTFS")"
  },
  "firmware": {
    "file": "bin/$ARTIFACT_NAME.fw_payload.bin",
    "sha256": "$(sha256 "$FIRMWARE_IMAGE")"
  }
}
EOF
