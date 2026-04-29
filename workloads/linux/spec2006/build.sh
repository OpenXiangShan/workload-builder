#!/usr/bin/env bash
set -euo pipefail

: "${SPEC2006_CASE:?SPEC2006_CASE is required}"
: "${SPEC2006:?SPEC2006 is required}"
: "${SPEC2006_CASE_CONFIG:?SPEC2006_CASE_CONFIG is required}"
: "${SPEC2006_CFG:?SPEC2006_CFG is required}"
: "${CROSS_COMPILE:=riscv64-unknown-linux-gnu-}"
: "${SPEC2006_TUNE:=base}"
: "${SPEC2006_JOBS:=$(nproc)}"
: "${SPEC2006_JEMALLOC_REPO:=https://github.com/jemalloc/jemalloc.git}"
: "${SPEC2006_JEMALLOC_COMMIT:=da66aa391f853ccf2300845b3873cc8f1cf48f2d}"
: "${SPEC2006_DOWNLOAD_RETRIES:=3}"
: "${SPEC2006_ELF_ONLY:=false}"
: "${SPEC2006_LOG_DIR:=$WORKLOAD_BUILD_DIR/logs}"
: "${PKG_DIR:=$WORKLOAD_BUILD_DIR/package}"

SPEC2006_JEMALLOC_ROOT="${SPEC2006_JEMALLOC_ROOT:-${JEMALLOC_INSTALL_PATH:-}}"

jemalloc_lock_dir=""
cleanup() {
  if [ -n "$jemalloc_lock_dir" ]; then
    rmdir "$jemalloc_lock_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p "$SPEC2006_LOG_DIR"

spec2006_progress_prefix() {
  local k="${SPEC2006_PROGRESS_K:-1}"
  local n="${SPEC2006_PROGRESS_N:-1}"
  printf '[spec2006 %s/%s]' "$k" "$n"
}

status() {
  printf '%s %s\n' "$(spec2006_progress_prefix)" "$*"
}

show_log_tail() {
  local log_file="$1"
  if [ -f "$log_file" ]; then
    echo "$(spec2006_progress_prefix) Last 40 lines from $log_file:" >&2
    tail -n 40 "$log_file" >&2 || true
  fi
}

retry() {
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "$attempt" -ge "$SPEC2006_DOWNLOAD_RETRIES" ]; then
      return 1
    fi
    printf '%s Retrying failed command (%s/%s): %s\n' \
      "$(spec2006_progress_prefix)" \
      "$attempt" \
      "$SPEC2006_DOWNLOAD_RETRIES" \
      "$*" >&2
    sleep $((attempt * 2))
    attempt=$((attempt + 1))
  done
}

retry_git_clone() {
  local repo="$1"
  local dest="$2"
  local attempt=1
  while true; do
    rm -rf "$dest"
    if git clone "$repo" "$dest"; then
      return 0
    fi
    if [ "$attempt" -ge "$SPEC2006_DOWNLOAD_RETRIES" ]; then
      return 1
    fi
    printf '%s Retrying failed git clone (%s/%s): %s\n' \
      "$(spec2006_progress_prefix)" \
      "$attempt" \
      "$SPEC2006_DOWNLOAD_RETRIES" \
      "$repo" >&2
    sleep $((attempt * 2))
    attempt=$((attempt + 1))
  done
}

prepare_git_checkout() {
  local repo="$1"
  local commit="$2"
  local dest="$3"
  local current_commit target_commit

  if [ ! -d "$dest/.git" ]; then
    retry_git_clone "$repo" "$dest"
  else
    git -C "$dest" remote set-url origin "$repo"
  fi

  if ! git -C "$dest" cat-file -e "$commit^{commit}" 2>/dev/null; then
    retry git -C "$dest" fetch --tags origin
  fi

  current_commit="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
  target_commit="$(git -C "$dest" rev-parse "$commit")"
  if [ "$current_commit" != "$target_commit" ]; then
    git -C "$dest" checkout --detach "$commit"
  fi
}

is_true() {
  case "$1" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

cfg_requires_jemalloc() {
  grep -Eq 'JEMALLOC_PATH|-ljemalloc' "$SPEC2006_CFG"
}

resolve_jemalloc_root() {
  if [ -n "$SPEC2006_JEMALLOC_ROOT" ]; then
    realpath -m "$SPEC2006_JEMALLOC_ROOT"
  else
    realpath -m "$(dirname "$WORKLOAD_BUILD_DIR")/jemalloc/install"
  fi
}

resolve_jemalloc_host() {
  if [ -n "${SPEC2006_JEMALLOC_CONFIGURE_HOST:-}" ]; then
    printf '%s\n' "$SPEC2006_JEMALLOC_CONFIGURE_HOST"
  else
    "${CROSS_COMPILE}gcc" -dumpmachine
  fi
}

prepare_jemalloc() {
  local base_dir source_dir prefix host log_file
  base_dir="$(realpath -m "$(dirname "$WORKLOAD_BUILD_DIR")/jemalloc")"
  source_dir="$base_dir/source"
  prefix="$(resolve_jemalloc_root)"
  host="$(resolve_jemalloc_host)"
  log_file="$base_dir/build.log"

  if [ -f "$prefix/lib/libjemalloc.a" ]; then
    SPEC2006_JEMALLOC_ROOT="$prefix"
    export SPEC2006_JEMALLOC_ROOT
    status "Using cached jemalloc: $prefix"
    return
  fi

  jemalloc_lock_dir="$base_dir/.lock"
  mkdir -p "$base_dir"
  while ! mkdir "$jemalloc_lock_dir" 2>/dev/null; do
    sleep 1
  done

  if [ -f "$prefix/lib/libjemalloc.a" ]; then
    rmdir "$jemalloc_lock_dir"
    jemalloc_lock_dir=""
    SPEC2006_JEMALLOC_ROOT="$prefix"
    export SPEC2006_JEMALLOC_ROOT
    status "Using cached jemalloc: $prefix"
    return
  fi

  status "Preparing jemalloc (log: $log_file)"
  : > "$log_file"

  if ! {
    echo "# jemalloc repo: $SPEC2006_JEMALLOC_REPO"
    echo "# jemalloc commit: $SPEC2006_JEMALLOC_COMMIT"
    echo "# install prefix: $prefix"
    echo "# configure host: $host"
    prepare_git_checkout "$SPEC2006_JEMALLOC_REPO" "$SPEC2006_JEMALLOC_COMMIT" "$source_dir"

    (
      cd "$source_dir"
      CC="${CROSS_COMPILE}gcc" \
      CXX="${CROSS_COMPILE}g++" \
      AR="${CROSS_COMPILE}ar" \
      LD="${CROSS_COMPILE}ld" \
      RANLIB="${CROSS_COMPILE}ranlib" \
      STRIP="${CROSS_COMPILE}strip" \
      ./autogen.sh --prefix="$prefix" --host="$host"
      make -j"$SPEC2006_JOBS"
      make install
    )
  } >>"$log_file" 2>&1; then
    echo "$(spec2006_progress_prefix) jemalloc build failed; see $log_file" >&2
    show_log_tail "$log_file"
    return 1
  fi

  rmdir "$jemalloc_lock_dir"
  jemalloc_lock_dir=""

  SPEC2006_JEMALLOC_ROOT="$prefix"
  export SPEC2006_JEMALLOC_ROOT
  status "jemalloc ready: $prefix"
}

if cfg_requires_jemalloc; then
  prepare_jemalloc
fi

python_args=()
if is_true "$SPEC2006_ELF_ONLY"; then
  python_args+=(--elf-only)
fi

python3 "$WORKLOAD_DIR/spec2006-package.py" \
  --case "$SPEC2006_CASE" \
  --cases-config "$SPEC2006_CASE_CONFIG" \
  --spec "$SPEC2006" \
  --spec-config "$SPEC2006_CFG" \
  --pkg-dir "$PKG_DIR" \
  --out-dir "$WORKLOAD_BUILD_DIR" \
  --cross-compile "$CROSS_COMPILE" \
  --compiler-root "${SPEC2006_COMPILER_ROOT:-}" \
  --gnu-toolchain-root "${SPEC2006_GNU_TOOLCHAIN_ROOT:-}" \
  --jemalloc-root "${SPEC2006_JEMALLOC_ROOT:-}" \
  --log-dir "$SPEC2006_LOG_DIR" \
  --tune "$SPEC2006_TUNE" \
  --jobs "$SPEC2006_JOBS" \
  "${python_args[@]}"
