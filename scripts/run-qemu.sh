#!/usr/bin/env bash
set -uo pipefail

usage() {
    echo "Usage: QEMU_BIN=/path/to/qemu-system-riscv64 [HARTS=N] [QEMU_MEMORY=SIZE] $0 <fw_payload.qemu.bin>" >&2
}

if [ "$#" -ne 1 ]; then
    usage
    exit 2
fi

firmware="$1"
if [ ! -s "$firmware" ]; then
    echo "QEMU firmware is missing or empty: $firmware" >&2
    exit 2
fi
firmware="$(realpath "$firmware")"

qemu_request="${QEMU_BIN:-}"
if [ -z "$qemu_request" ]; then
    echo "QEMU_BIN must specify qemu-system-riscv64" >&2
    usage
    exit 2
fi
if [[ "$qemu_request" == */* ]]; then
    if [ ! -x "$qemu_request" ]; then
        echo "QEMU executable is missing or not executable: $qemu_request" >&2
        exit 2
    fi
    qemu_bin="$(realpath "$qemu_request")"
else
    qemu_bin="$(command -v "$qemu_request" || true)"
    if [ -z "$qemu_bin" ]; then
        echo "QEMU executable was not found in PATH: $qemu_request" >&2
        exit 2
    fi
fi

qemu_contract="$({
    printf 'info mtree\ninfo qtree\nquit\n' | LC_ALL=C timeout 10s "$qemu_bin" \
        -machine nemu \
        -accel tcg \
        -cpu rv64 \
        -smp 1 \
        -m 128M \
        -display none \
        -serial none \
        -bios none \
        -S \
        -monitor stdio
} 2>&1)"
contract_status=$?
if [ "$contract_status" -ne 0 ]; then
    echo "Failed to inspect the QEMU 'nemu' machine from $qemu_bin" >&2
    printf '%s\n' "$qemu_contract" >&2
    exit "$contract_status"
fi
if ! grep -Eq '0*310b0000-0*310bffff.*riscv\.nemu\.uart' <<< "$qemu_contract" ||
    ! grep -Fq 'dev: serial-mm' <<< "$qemu_contract" ||
    ! grep -Eq 'regshift = 2([[:space:]]|\()' <<< "$qemu_contract" ||
    ! grep -Eq 'num-sources = 67([[:space:]]|\()' <<< "$qemu_contract" ||
    ! grep -Eq 'timebase-freq = 1000000([[:space:]]|\()' <<< "$qemu_contract"; then
    echo "QEMU 'nemu' machine does not match the required XiangShan device contract: $qemu_bin" >&2
    echo "Expected a 16550A UART at 0x310b0000, PLIC with 67 sources, and a 1 MHz timer." >&2
    echo "Use OpenXiangShan/qemu commit d6ef1ba720 or a compatible descendant." >&2
    exit 2
fi

qemu_cpu="rv64,zicond=true,v=true,vlen=128,h=true,sv39=true,sv48=true,sv57=false,sv64=false,smstateen=true,sscofpmf=true,smcntrpmf=true,svade=true,svinval=true,svnapot=true,svpbmt=true,zacas=true,zawrs=true,zba=true,zbb=true,zbc=true,zbkb=true,zbkc=true,zbkx=true,zbs=true,zca=true,zcb=true,zcmop=true,zfa=true,zfh=true,zfhmin=true,zicntr=true,zicsr=true,zifencei=true,zihintntl=true,zihintpause=true,zihpm=true,zimop=true,zkn=true,zknd=true,zkne=true,zknh=true,zksed=true,zksh=true,zkt=true,zvbb=true,zvfh=true,zvfhmin=true,zvkt=true"
harts="${HARTS:-1}"
case "$harts" in
    ''|*[!0-9]*) echo "HARTS must be an integer in the range 1..128" >&2; exit 2 ;;
esac
if [ "$harts" -lt 1 ] || [ "$harts" -gt 128 ]; then
    echo "HARTS must be an integer in the range 1..128" >&2
    exit 2
fi
qemu_memory="${QEMU_MEMORY:-2G}"
log_file="$(mktemp)"
cleanup() {
    rm -f -- "$log_file"
}
trap cleanup EXIT

set +e
"$qemu_bin" \
    -machine nemu \
    -accel tcg \
    -cpu "$qemu_cpu" \
    -smp "$harts" \
    -m "$qemu_memory" \
    -nographic \
    -no-reboot \
    -bios "$firmware" 2>&1 | tee "$log_file"
qemu_status=${PIPESTATUS[0]}
set -e

if grep -Fq 'Hit BAD TRAP' "$log_file"; then
    echo "QEMU reported Hit BAD TRAP" >&2
    exit 1
fi
if grep -Fq 'Hit GOOD TRAP' "$log_file"; then
    if [ "$qemu_status" -ne 0 ]; then
        echo "QEMU reported Hit GOOD TRAP but exited with status $qemu_status" >&2
        exit "$qemu_status"
    fi
    exit 0
fi
if [ "$qemu_status" -ne 0 ]; then
    echo "QEMU exited with status $qemu_status before a terminal trap" >&2
    exit "$qemu_status"
fi

echo "QEMU exited normally without Hit GOOD TRAP or Hit BAD TRAP" >&2
exit 1
