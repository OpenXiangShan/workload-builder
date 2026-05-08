#!/usr/bin/env bash
set -euo pipefail

: "${SPEC2017_CASE:?SPEC2017_CASE is required}"
: "${SPEC2017:?SPEC2017 is required}"
: "${SPEC2017_CFG:?SPEC2017_CFG is required}"
: "${CROSS_COMPILE:=riscv64-unknown-linux-gnu-}"
: "${SPEC2017_TUNE:=base}"
: "${SPEC2017_JOBS:=$(nproc)}"
: "${SPEC2017_ELF_ONLY:=false}"
: "${SPEC2017_ALL_RUNS:=false}"
: "${SPEC2017_PROFILING:=1}"
: "${SPEC2017_LOG_DIR:=$WORKLOAD_BUILD_DIR/logs}"
: "${PKG_DIR:=$WORKLOAD_BUILD_DIR/package}"

mkdir -p "$SPEC2017_LOG_DIR"

is_true() {
  case "$1" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

python_args=()
if is_true "$SPEC2017_ELF_ONLY"; then
  python_args+=(--elf-only)
fi
if is_true "$SPEC2017_ALL_RUNS"; then
  python_args+=(--all-runs)
fi

python3 "$WORKLOAD_DIR/spec2017-package.py" \
  --case "$SPEC2017_CASE" \
  --spec-source "$SPEC2017" \
  --spec-config "$SPEC2017_CFG" \
  --pkg-dir "$PKG_DIR" \
  --out-dir "$WORKLOAD_BUILD_DIR" \
  --cross-compile "$CROSS_COMPILE" \
  --compiler-root "${SPEC2017_COMPILER_ROOT:-}" \
  --gnu-toolchain-root "${SPEC2017_GNU_TOOLCHAIN_ROOT:-}" \
  --log-dir "$SPEC2017_LOG_DIR" \
  --tune "$SPEC2017_TUNE" \
  --jobs "$SPEC2017_JOBS" \
  --profiling "$SPEC2017_PROFILING" \
  "${python_args[@]}"
