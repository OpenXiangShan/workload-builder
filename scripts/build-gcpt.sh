#!/usr/bin/env bash
set -e

GCPT_SOURCE_DIR="$(realpath "$1")"
GCPT_BUILD_DIR="$(realpath "$2")"
BUILD_DIR="$(dirname "$GCPT_BUILD_DIR")"
GCPT_IMPLEMENTATION="${GCPT_IMPLEMENTATION:-alpha}"
GCPT_CONFIGURE_MODE="${GCPT_CONFIGURE_MODE:-normal}"

extract_clint_mmio() {
    local dts_template_dir="$1"
    local default_dtb="$2"
    local dts_template="$dts_template_dir/$default_dtb.dts.in"

    if ! [ -f "$dts_template" ]; then
        echo "Default DTS template not found: $dts_template" >&2
        return 1
    fi

    perl -0777 -ne '
        while (/(?:[A-Za-z_][A-Za-z0-9_]*:\s*)?[A-Za-z0-9,_-]*clint@[^{]*\{(.*?)\};/sg) {
            my $node = $1;
            next unless $node =~ /compatible\s*=\s*[^;]*"riscv,clint0"/s;
            next unless $node =~ /reg\s*=\s*<([^>]+)>/s;
            my @cells = $1 =~ /(0x[0-9a-fA-F]+|\d+)/g;
            next unless @cells >= 2;
            my $addr = (hex_or_dec($cells[0]) << 32) + hex_or_dec($cells[1]);
            printf "0x%x\n", $addr;
            exit 0;
        }
        exit 1;
        sub hex_or_dec {
            my ($v) = @_;
            return $v =~ /^0x/i ? hex($v) : int($v);
        }
    ' "$dts_template"
}

mkdir -p "$BUILD_DIR"
rm -rf "$GCPT_BUILD_DIR"
cp -r "$GCPT_SOURCE_DIR" "$GCPT_BUILD_DIR"

case "$GCPT_IMPLEMENTATION" in
    alpha)
        DTS_TEMPLATE_DIR="$(realpath "${DTS_TEMPLATE_DIR:?DTS_TEMPLATE_DIR is required for LibCheckpointAlpha}")"
        DEFAULT_DTB="${DEFAULT_DTB:-xiangshan}"
        CLINT_MMIO="${CLINT_MMIO:-$(extract_clint_mmio "$DTS_TEMPLATE_DIR" "$DEFAULT_DTB")}"
        export CFLAGS="${CFLAGS:-} -DCONFIG_CLINT_MMIO=$CLINT_MMIO"
        make -C "$GCPT_BUILD_DIR"
        ;;
    libcheckpoint)
        case "$GCPT_CONFIGURE_MODE" in
            normal|dual_core) ;;
            *)
                echo "Unsupported LibCheckpoint configure mode: $GCPT_CONFIGURE_MODE" >&2
                exit 1
                ;;
        esac
        (
            cd "$GCPT_BUILD_DIR"
            bash ./configure "--mode=$GCPT_CONFIGURE_MODE"
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
