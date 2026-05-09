#!/usr/bin/env bash
set -euo pipefail

: "${SPEC2026_CASE:?SPEC2026_CASE is required}"
: "${SPEC2026:?SPEC2026 is required}"
: "${SPEC2026_CFG:?SPEC2026_CFG is required}"
: "${CROSS_COMPILE:=riscv64-unknown-linux-gnu-}"
: "${SPEC2026_TUNE:=base}"
: "${SPEC2026_JOBS:=$(nproc)}"
: "${SPEC2026_ELF_ONLY:=false}"
: "${SPEC2026_LOG_DIR:=$WORKLOAD_BUILD_DIR/logs}"
: "${PKG_DIR:=$WORKLOAD_BUILD_DIR/package}"

mkdir -p "$SPEC2026_LOG_DIR"

spec2026_progress_prefix() {
  local k="${SPEC2026_PROGRESS_K:-1}"
  local n="${SPEC2026_PROGRESS_N:-1}"
  printf '[spec2026 %s/%s]' "$k" "$n"
}

status() {
  printf '%s %s\n' "$(spec2026_progress_prefix)" "$*"
}

is_true() {
  case "$1" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

python_args=()
if is_true "$SPEC2026_ELF_ONLY"; then
  python_args+=(--elf-only)
fi

python3 "$WORKLOAD_DIR/spec2026-package.py" \
  --case "$SPEC2026_CASE" \
  --spec "$SPEC2026" \
  --spec-config "$SPEC2026_CFG" \
  --pkg-dir "$PKG_DIR" \
  --out-dir "$WORKLOAD_BUILD_DIR" \
  --cross-compile "$CROSS_COMPILE" \
  --log-dir "$SPEC2026_LOG_DIR" \
  --tune "$SPEC2026_TUNE" \
  --jobs "$SPEC2026_JOBS" \
  --input-set "${SPEC2026_INPUT:-ref}" \
  "${python_args[@]}"
