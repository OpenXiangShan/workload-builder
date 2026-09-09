#!/usr/bin/env bash
set -euo pipefail

: "${SPECJBB_INPUT:?SPECJBB_INPUT is required (licensed ISO, archive, or directory)}"
: "${SPECJBB_RV_JDK_INPUT:?SPECJBB_RV_JDK_INPUT is required (RV64 JDK directory or archive)}"
: "${SPECJBB_JVM_XMS:=4g}"
: "${SPECJBB_JVM_XMX:=4g}"
: "${SPECJBB_MODE:=COMPOSITE}"

[[ -e "$SPECJBB_INPUT" ]] || { echo "SPECjbb input not found: $SPECJBB_INPUT" >&2; exit 1; }
[[ -e "$SPECJBB_RV_JDK_INPUT" ]] || { echo "RV64 JDK input not found: $SPECJBB_RV_JDK_INPUT" >&2; exit 1; }
[[ "$SPECJBB_MODE" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid SPECJBB_MODE" >&2; exit 1; }

payload_dir="$PKG_DIR/specjbb2015"
mkdir -p "$payload_dir/specjbb" "$payload_dir/jdk"
if [[ -d "$SPECJBB_RV_JDK_INPUT" ]]; then
  cp -a "$SPECJBB_RV_JDK_INPUT"/. "$payload_dir/jdk/"
else
  jdk_stage="$WORKLOAD_BUILD_DIR/jdk-stage"
  rm -rf "$jdk_stage" && mkdir -p "$jdk_stage"
  tar -xf "$SPECJBB_RV_JDK_INPUT" -C "$jdk_stage"
  if [[ -x "$jdk_stage/bin/java" ]]; then
    cp -a "$jdk_stage"/. "$payload_dir/jdk/"
  else
    jdk_root="$(find "$jdk_stage" -mindepth 1 -maxdepth 2 -type f -path '*/bin/java' -printf '%h\n' | sed 's|/bin$||' | head -n 1)"
    [[ -n "$jdk_root" ]] || { echo "RV64 JDK archive does not contain bin/java" >&2; exit 1; }
    cp -a "$jdk_root"/. "$payload_dir/jdk/"
  fi
fi
if [[ -d "$SPECJBB_INPUT" ]]; then
  cp -a "$SPECJBB_INPUT"/. "$payload_dir/specjbb/"
elif [[ "$SPECJBB_INPUT" == *.iso ]] && command -v 7z >/dev/null 2>&1; then
  7z x -y "$SPECJBB_INPUT" -o"$payload_dir/specjbb" >/dev/null
elif [[ "$SPECJBB_INPUT" == *.iso ]] && command -v bsdtar >/dev/null 2>&1; then
  bsdtar -xf "$SPECJBB_INPUT" -C "$payload_dir/specjbb"
elif [[ "$SPECJBB_INPUT" == *.iso ]]; then
  echo "Extracting a SPECjbb ISO requires 7z or bsdtar" >&2
  exit 1
else
  tar -xf "$SPECJBB_INPUT" -C "$payload_dir/specjbb"
fi
[[ -x "$payload_dir/jdk/bin/java" ]] || { echo "RV64 JDK bin/java not found after extraction" >&2; exit 1; }
[[ -f "$payload_dir/specjbb/specjbb2015.jar" ]] || { echo "specjbb2015.jar not found at the input root" >&2; exit 1; }
install -m 755 "$WORKLOAD_DIR/run.sh" "$payload_dir/run.sh"
install -m 755 "$WORKLOAD_DIR/launch-multihart.sh" "$payload_dir/launch-multihart.sh"
install -D -m 644 "$WORKLOAD_DIR/inittab" "$PKG_DIR/etc/inittab"
{
  printf 'SPECJBB_JVM_XMS=%q\n' "$SPECJBB_JVM_XMS"
  printf 'SPECJBB_JVM_XMX=%q\n' "$SPECJBB_JVM_XMX"
  printf 'SPECJBB_MODE=%q\n' "$SPECJBB_MODE"
  printf 'SPECJBB_HARTS=%q\n' "${SPECJBB_HARTS:-${HARTS:-2}}"
} > "$payload_dir/specjbb-workload.conf"
