#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 8 ]; then
    echo "usage: $0 COMMON_PACKAGE CASE_BUILD_DIR CASE KEYS OPS THREADS VALUE_SIZE PROFILING" >&2
    exit 2
fi

common_package="$(realpath "$1")"
case_build_dir="$(realpath -m "$2")"
case_name="$3"
keys="$4"
ops="$5"
threads="$6"
value_size="$7"
profiling="$8"
package_dir="$case_build_dir/package"

case "$profiling" in
    0|1) ;;
    *) echo "PROFILING must be 0 or 1: $profiling" >&2; exit 2 ;;
esac

case "$case_name" in
    readwhilewriting|readrandomwriterandom|updaterandom|seekrandomwhilewriting|randomtransaction|timeseries|mixgraph) ;;
    *) echo "unknown RocksDB case: $case_name" >&2; exit 2 ;;
esac

rm -rf "$package_dir"
mkdir -p "$package_dir/etc/default"
cp -a "$common_package/." "$package_dir/"
printf '%s\n' \
    "ROCKSDB_CASES=$case_name" \
    "ROCKSDB_KEYS=$keys" \
    "ROCKSDB_OPS=$ops" \
    "ROCKSDB_THREADS=$threads" \
    "ROCKSDB_VALUE_SIZE=$value_size" \
    "ROCKSDB_PROFILING=$profiling" \
    > "$package_dir/etc/default/rocksdb"

rm -f "$case_build_dir/rootfs.cpio"
(
    cd "$package_dir"
    find . | fakeroot cpio -o -H newc > "$case_build_dir/rootfs.cpio" 2>/dev/null
)
