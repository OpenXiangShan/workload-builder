# CoreMark Workload

## Description

EEMBC CoreMark benchmark for measuring CPU performance. CoreMark is a small benchmark that measures the performance of embedded processors by running several tasks including list processing, matrix manipulation, and state machine execution.

This is a Linux workload.

## How it runs

The workload downloads and builds the CoreMark benchmark from source. It uses an inittab configuration that:

1. Runs the coremark executable with specific parameters for reproducible results
2. Halts the system with nemu-trap, passing the exit code from coremark

The benchmark runs with these parameters, which is a "standard" verification run of CoreMark:

- 0x0 0x0 0x66 0 7 1 2000

## Single-core QEMU build

Build a firmware image for the QEMU NEMU machine:

```bash
make linux/coremark PLATFORM=qemu -jN
```

The result is `build/linux-workloads/coremark/fw_payload.qemu.bin`. Run it with
a compatible QEMU using:

```bash
QEMU_BIN=/path/to/qemu-system-riscv64 \
  bash scripts/run-qemu.sh \
  build/linux-workloads/coremark/fw_payload.qemu.bin
```

Building does not require QEMU. The runner requires `QEMU_BIN`; it does not
enable profiling or checkpoint generation.

## Multi-hart builds

Build a multi-hart CoreMark workload with:

```bash
make linux/coremark MULTIHART=1 HARTS=2 \
  DEFAULT_DTB=xiangshan-fpga-noAIA-2hart-mem8g-novec -jN
```

The generated root filesystem starts one CoreMark process per hart. Each process
is pinned with `taskset` and uses the same verification arguments listed above.
Set `HARTS` to the number of harts in the matching QEMU checkpoint; the build
automatically selects `PLATFORM=qemu` and requires a matching `DEFAULT_DTB`.
Run with the same hart count and enough memory for that DTS, for example:

```bash
QEMU_BIN=/path/to/qemu-system-riscv64 QEMU_MEMORY=8G \
  HARTS=2 bash scripts/run-qemu.sh \
  build/linux-workloads/coremark/fw_payload.qemu.bin
```
