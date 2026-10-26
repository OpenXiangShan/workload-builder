#!/usr/bin/env bash
set -euo pipefail

: "${VERILATOR_GUEST_EMU:?VERILATOR_GUEST_EMU is required: riscv64 emu binary to run in the guest}"
: "${VERILATOR_GUEST_IMAGE:?VERILATOR_GUEST_IMAGE is required: bare-metal image the nested simulation runs}"
: "${CROSS_COMPILE:?CROSS_COMPILE is required}"

max_cycles="${VERILATOR_MAX_CYCLES:-50000}"
ram_size="${VERILATOR_RAM_SIZE:-8GB}"

if [[ ! "$max_cycles" =~ ^[0-9]+$ ]] || [[ "$max_cycles" -eq 0 ]]; then
    echo "ERROR: VERILATOR_MAX_CYCLES must be a positive integer, got '$max_cycles'" >&2
    exit 1
fi

for input in "$VERILATOR_GUEST_EMU" "$VERILATOR_GUEST_IMAGE"; do
    if [[ ! -f "$input" ]]; then
        echo "ERROR: input not found: $input" >&2
        exit 1
    fi
done

install -Dm 755 "$VERILATOR_GUEST_EMU" "$PKG_DIR/usr/bin/emu"
"$CROSS_COMPILE"strip -s "$PKG_DIR/usr/bin/emu"
install -Dm 644 "$VERILATOR_GUEST_IMAGE" "$PKG_DIR/verilator/workload.bin"

# Keep the provenance of the simulated design inside the image, so a bin file
# on its own still says which XiangShan revision and configuration it runs.
if [[ -f "$VERILATOR_GUEST_EMU.meta" ]]; then
    install -Dm 644 "$VERILATOR_GUEST_EMU.meta" "$PKG_DIR/verilator/emu.meta"
fi

sed -e "s|@MAX_CYCLES@|$max_cycles|g" \
    -e "s|@RAM_SIZE@|$ram_size|g" \
    "$WORKLOAD_DIR/inittab.in" > "$SRC_DIR/inittab"
install -Dm 644 "$SRC_DIR/inittab" "$PKG_DIR/etc/inittab"
