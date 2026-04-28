#!/usr/bin/env bash
set -euo pipefail

archive="$SRC_DIR/Geekbench-5.5.1-LinuxRISCVPreview.tar.gz"
extract_dir="$SRC_DIR/geekbench"
payload_dir="$PKG_DIR/geekbench"

rm -rf "$extract_dir"
mkdir -p "$extract_dir" "$payload_dir"
tar -C "$extract_dir" --strip-components=1 -xf "$archive"

install -m 755 "$extract_dir/geekbench5" "$payload_dir/geekbench5"
install -m 755 "$extract_dir/geekbench_riscv64" "$payload_dir/geekbench_riscv64"
install -m 644 "$extract_dir/geekbench.plar" "$payload_dir/geekbench.plar"
install -m 755 "$WORKLOAD_DIR/run.sh" "$payload_dir/run.sh"
mkdir -p "$PKG_DIR/etc"
mkdir -p "$PKG_DIR/etc/default"
printf 'GEEKBENCH_ARGS=%q\n' "${GEEKBENCH_ARGS:---cpu --iterations 1}" > "$PKG_DIR/etc/default/geekbench"
if [ "${PROFILING:-0}" = 1 ]; then
    printf '::sysinit:sh -c "nemu-trap 257"\n' > "$PKG_DIR/etc/inittab"
fi
printf '::once:sh -c "/geekbench/run.sh; nemu-trap -1"\n' >> "$PKG_DIR/etc/inittab"
