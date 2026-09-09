#!/usr/bin/env bash
set -euo pipefail

: "${CROSS_COMPILE:?CROSS_COMPILE is required}"
: "${ROCKSDB_MARCH:=rva23u64}"
: "${ROCKSDB_MABI:=lp64d}"
: "${ROCKSDB_OPT_FLAGS:=-O3 -ftree-vectorize -ftree-loop-vectorize -ftree-slp-vectorize -mrvv-vector-bits=zvl}"

readonly rocksdb_src="$SRC_DIR/rocksdb"
readonly gflags_src="$SRC_DIR/gflags"
readonly gflags_build="$WORKLOAD_BUILD_DIR/gflags-build"
readonly gflags_prefix="$WORKLOAD_BUILD_DIR/gflags-install"
readonly rocksdb_build="$WORKLOAD_BUILD_DIR/rocksdb-build"
readonly rocksdb_prefix="$WORKLOAD_BUILD_DIR/rocksdb-install"

extract_archive() {
    local archive="$1"
    local destination="$2"
    rm -rf "$destination"
    mkdir -p "$destination"
    tar -C "$destination" --strip-components=1 -xf "$archive"
}

extract_archive "$SRC_DIR/rocksdb.tar.gz" "$rocksdb_src"
extract_archive "$SRC_DIR/gflags.tar.gz" "$gflags_src"
patch --batch --forward -d "$rocksdb_src" -p1 \
    < "$WORKLOAD_DIR/randomtransaction-set-name.patch"

readonly cc="${CROSS_COMPILE}gcc"
readonly cxx="${CROSS_COMPILE}g++"
readonly ar="${CROSS_COMPILE}ar"
readonly ranlib="${CROSS_COMPILE}ranlib"
readonly strip="${CROSS_COMPILE}strip"
readonly readelf="${CROSS_COMPILE}readelf"
readonly objdump="${CROSS_COMPILE}objdump"
for tool in "$cc" "$cxx" "$ar" "$ranlib" "$strip" "$readelf" "$objdump"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "required RISC-V Linux tool not found: $tool" >&2
        exit 1
    fi
done

readonly vector_probe="$WORKLOAD_BUILD_DIR/rva23-vector-probe.o"
readonly vector_report="$WORKLOAD_BUILD_DIR/rva23-vector-probe.txt"
# Word splitting is intentional: ROCKSDB_OPT_FLAGS is a user-overridable flag list.
# shellcheck disable=SC2086
if ! printf '%s\n' \
    'void vector_probe(float *restrict d, const float *restrict a,' \
    '                  const float *restrict b, unsigned long n) {' \
    '  for (unsigned long i = 0; i < n; ++i) d[i] = a[i] + b[i];' \
    '}' | "$cc" -x c -c -march="$ROCKSDB_MARCH" -mabi="$ROCKSDB_MABI" \
        $ROCKSDB_OPT_FLAGS -fopt-info-vec-optimized="$vector_report" \
        -o "$vector_probe" -; then
    echo "compiler does not support the requested RocksDB ISA/vectorization flags" >&2
    exit 1
fi
if ! grep -q 'loop vectorized' "$vector_report" || \
    ! "$objdump" -d "$vector_probe" | grep -Eq '[[:space:]]vset(i?vli|vl)[[:space:]]'; then
    echo "compiler accepted the flags but did not auto-vectorize the probe with RVV" >&2
    exit 1
fi

readonly sysroot="${SYSROOT_DIR:-$("$cxx" -print-sysroot)}"
if [ -z "$sysroot" ] || [ ! -d "$sysroot" ]; then
    echo "cannot determine a valid sysroot from $cxx" >&2
    exit 1
fi
readonly target_flags="-march=$ROCKSDB_MARCH -mabi=$ROCKSDB_MABI $ROCKSDB_OPT_FLAGS"
readonly common_toolchain_args=(
    "-DCMAKE_SYSTEM_NAME=Linux"
    "-DCMAKE_SYSTEM_PROCESSOR=riscv64"
    "-DCMAKE_C_COMPILER=$cc"
    "-DCMAKE_CXX_COMPILER=$cxx"
    "-DCMAKE_AR=$ar"
    "-DCMAKE_RANLIB=$ranlib"
    "-DCMAKE_SYSROOT=$sysroot"
    "-DCMAKE_FIND_ROOT_PATH=$sysroot"
    "-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER"
    "-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY"
    "-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY"
    "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY"
    "-DCMAKE_C_FLAGS=$target_flags"
    "-DCMAKE_CXX_FLAGS=$target_flags"
)

# CMake caches the compiler and target flags. Always configure these small
# dependency/build trees from scratch when the hashed build settings change.
rm -rf "$gflags_build" "$gflags_prefix" "$rocksdb_build" "$rocksdb_prefix"

cmake -S "$gflags_src" -B "$gflags_build" \
    "${common_toolchain_args[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$gflags_prefix" \
    -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON \
    -DREGISTER_BUILD_DIR=OFF \
    -DREGISTER_INSTALL_PREFIX=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_BUILD_STATIC_LIBS=ON \
    -DBUILD_gflags_LIB=ON \
    -DBUILD_gflags_nothreads_LIB=OFF \
    -DGFLAGS_BUILD_SHARED_LIBS=OFF \
    -DGFLAGS_BUILD_TESTING=OFF
cmake --build "$gflags_build" --target gflags -j"${JOBS:-$(nproc)}"
cmake --install "$gflags_build"

cmake -S "$rocksdb_src" -B "$rocksdb_build" \
    "${common_toolchain_args[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$gflags_prefix" \
    -Dgflags_DIR="$gflags_prefix/lib/cmake/gflags" \
    -DCMAKE_INSTALL_PREFIX="$rocksdb_prefix" \
    -DROCKSDB_BUILD_SHARED=OFF \
    -DWITH_GFLAGS=ON \
    -DGFLAGS_SHARED=OFF \
    -DGFLAGS_NOTHREADS=OFF \
    -DWITH_BENCHMARK_TOOLS=ON \
    -DWITH_TOOLS=OFF \
    -DWITH_TESTS=OFF \
    -DWITH_SNAPPY=OFF \
    -DWITH_ZLIB=OFF \
    -DWITH_BZ2=OFF \
    -DWITH_LZ4=OFF \
    -DWITH_ZSTD=OFF \
    -DWITH_JEMALLOC=OFF \
    -DPORTABLE=ON \
    -DFAIL_ON_WARNINGS=OFF \
    -DCMAKE_EXE_LINKER_FLAGS=-static
cmake --build "$rocksdb_build" --target db_bench -j"${JOBS:-$(nproc)}"

install -Dm755 "$rocksdb_build/db_bench" "$PKG_DIR/usr/bin/rocksdb-db-bench"
install -Dm755 "$WORKLOAD_DIR/run.sh" "$PKG_DIR/rocksdb/run.sh"
install -Dm644 "$WORKLOAD_DIR/inittab" "$PKG_DIR/etc/inittab"

# Keep the runtime image independent of the host's environment. The static
# binary is intentionally checked here so a future toolchain change cannot
# silently produce an image that needs shared libraries absent from initramfs.
if "$readelf" -l "$PKG_DIR/usr/bin/rocksdb-db-bench" | grep -q INTERP; then
    echo "rocksdb db_bench must be statically linked" >&2
    exit 1
fi

if ! "$readelf" -A "$PKG_DIR/usr/bin/rocksdb-db-bench" | \
    grep -Eq 'Tag_RISCV_arch:.*_v[0-9]'; then
    echo "rocksdb db_bench does not advertise the RISC-V V extension" >&2
    exit 1
fi

if ! "$objdump" -d "$PKG_DIR/usr/bin/rocksdb-db-bench" | awk '
    /[[:space:]]vset(i?vli|vl)[[:space:]]/ { found = 1 }
    END { exit !found }
'; then
    echo "rocksdb db_bench contains no generated RVV instructions" >&2
    exit 1
fi

{
    printf 'compiler=%s\n' "$("$cxx" --version | head -n 1)"
    printf 'sysroot=%s\n' "$sysroot"
    printf 'march=%s\n' "$ROCKSDB_MARCH"
    printf 'mabi=%s\n' "$ROCKSDB_MABI"
    printf 'optimization=%s\n' "$ROCKSDB_OPT_FLAGS"
    printf 'auto_vectorization_probe=passed\n'
    sed 's/^/auto_vectorization_report=/' "$vector_report"
    "$readelf" -A "$PKG_DIR/usr/bin/rocksdb-db-bench"
} > "$PKG_DIR/rocksdb/build-info.txt"

"$strip" "$PKG_DIR/usr/bin/rocksdb-db-bench"
