#!/usr/bin/env bash
set -e

GCPT_SOURCE_DIR="$(realpath "$1")"
GCPT_BUILD_DIR="$(realpath "$2")"
BUILD_DIR="$(dirname "$GCPT_BUILD_DIR")"
GCPT_IMPLEMENTATION="${GCPT_IMPLEMENTATION:-alpha}"
GCPT_CONFIGURE_MODE="${GCPT_CONFIGURE_MODE:-normal}"
GCPT_PAYLOAD_PATH="${GCPT_PAYLOAD_PATH:-${3:-}}"
GCPT_SERIAL_PORT="${GCPT_SERIAL_PORT:-}"

source "$(dirname "${BASH_SOURCE[0]}")/dts-config.sh"

mkdir -p "$BUILD_DIR"
rm -rf "$GCPT_BUILD_DIR"
cp -r "$GCPT_SOURCE_DIR" "$GCPT_BUILD_DIR"
# Source worktrees may contain ignored build output. Never reuse it when the
# configure mode or embedded payload changes.
rm -rf "$GCPT_BUILD_DIR/build"

case "$GCPT_IMPLEMENTATION" in
    alpha)
        DTS_TEMPLATE_DIR="$(realpath "${DTS_TEMPLATE_DIR:?DTS_TEMPLATE_DIR is required for LibCheckpointAlpha}")"
        DEFAULT_DTB="${DEFAULT_DTB:-xiangshan}"
        DTS_TEMPLATE="$DTS_TEMPLATE_DIR/$DEFAULT_DTB.dts.in"
        DTS_CONFIG="$(dts_extract_config "$DTS_TEMPLATE")"
        read -r MEM_BEGIN MEM_SIZE CLINT_MMIO <<< "$DTS_CONFIG"
        export CFLAGS="${CFLAGS:-} -DCONFIG_CLINT_MMIO=$CLINT_MMIO -DCONFIG_DRAM_BASE=$MEM_BEGIN"
        make -C "$GCPT_BUILD_DIR"
        ;;
    libcheckpoint)
        if [ -n "$GCPT_SERIAL_PORT" ]; then
            CFLAGS="${CFLAGS:-} -DCONFIG_SERIAL_PORT=$GCPT_SERIAL_PORT"
        fi
        case "$GCPT_CONFIGURE_MODE" in
            normal|dual_core) ;;
            *)
                echo "Unsupported LibCheckpoint configure mode: $GCPT_CONFIGURE_MODE" >&2
                exit 1
                ;;
        esac
        (
            cd "$GCPT_BUILD_DIR"
            configure_args=("--mode=$GCPT_CONFIGURE_MODE")
            if [ -n "$GCPT_PAYLOAD_PATH" ]; then
                if ! [ -f "$GCPT_PAYLOAD_PATH" ]; then
                    echo "GCPT payload not found: $GCPT_PAYLOAD_PATH" >&2
                    exit 1
                fi
                configure_args+=("--gcpt-payload=$GCPT_PAYLOAD_PATH")
            fi
            bash ./configure "${configure_args[@]}"
            # LibCheckpoint is freestanding, while the Buildroot toolchain
            # defaults to stack protection and PIE.
            CFLAGS="${CFLAGS:-} -fno-stack-protector -fno-PIE" make LDFLAGS="-no-pie"
        )
        ;;
    *)
        echo "Unsupported GCPT implementation: $GCPT_IMPLEMENTATION" >&2
        exit 1
        ;;
esac
