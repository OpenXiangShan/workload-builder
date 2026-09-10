#!/usr/bin/env bash
set -euo pipefail

: "${CROSS_COMPILE:?CROSS_COMPILE is required}"

archive="$SRC_DIR/stress-ng-0.22.00.tar.gz"
source_dir="$SRC_DIR/stress-ng-0.22.00"

tar -C "$SRC_DIR" -xf "$archive"
make -C "$source_dir" \
    CC="${CROSS_COMPILE}gcc" \
    CXX="${CROSS_COMPILE}g++" \
    LD="${CROSS_COMPILE}gcc" \
    STATIC=1 \
    PRESERVE_CFLAGS=1 \
    -j"${JOBS:-$(nproc)}"

install -Dm755 "$source_dir/stress-ng" "$PKG_DIR/usr/bin/stress-ng"
install -Dm755 "$WORKLOAD_DIR/run.sh" "$PKG_DIR/stress-ng/run.sh"
install -d "$PKG_DIR/etc/default"

{
    printf '%s\n' \
        '::sysinit:/bin/mount -t proc proc /proc' \
        '::sysinit:/bin/mount -o remount,rw /' \
        '::sysinit:/bin/mount -t sysfs sysfs /sys'
    if [ "${PROFILING:-0}" = 1 ]; then
        printf '%s\n' '::sysinit:sh -c "nemu-trap 257"'
    fi
    printf '%s\n' '::once:/stress-ng/run.sh'
} > "$PKG_DIR/etc/inittab"

{
    printf 'STRESS_NG_OPS=%q\n' "${STRESS_NG_OPS:-1}"
    printf 'STRESS_NG_STRESSORS=%q\n' "${STRESS_NG_STRESSORS:-}"
    printf 'STRESS_NG_ARGS=%q\n' \
        "${STRESS_NG_ARGS:---oom-avoid --skip-silent --metrics-brief}"
    printf 'STRESS_NG_VM_BYTES=%q\n' "${STRESS_NG_VM_BYTES:-16M}"
    printf 'STRESS_NG_CYCLIC_POLICY=%q\n' "${STRESS_NG_CYCLIC_POLICY:-rr}"
} > "$PKG_DIR/etc/default/stress-ng"
