# RVV-Bench Workload

## Description

RISC-V Vector (RVV) benchmark suite containing various workloads optimized for the RISC-V Vector extension. These benchmarks test the performance of vector operations commonly used in real-world applications.

This is a Linux workload.

## How it runs

The workload builds multiple vector-optimized benchmarks from source. It uses an inittab configuration that:

1. Executes the run.sh script which runs all benchmark executables sequentially
2. Each benchmark is executed and checked for successful completion
3. System is halted with nemu-trap after all benchmarks complete

## Virtualization

Build RVV-Bench as a nested KVM guest and run the Host firmware with QEMU:

```sh
make linux/rvv-bench PLATFORM=qemu VIRTUALIZATION=1 -jN
QEMU_BIN=/path/to/qemu-system-riscv64 QEMU_MEMORY=16G \
  bash scripts/run-qemu.sh \
  build/virt-linux-workloads/rvv-bench/host/fw_payload.qemu.bin
```
