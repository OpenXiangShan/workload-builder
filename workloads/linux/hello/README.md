# Hello Workload

## Description

A simple "Hello, World!" program that prints a greeting message. This is a minimal Linux workload used for a smoke test.

## How it runs

This is an assembly program, and it is directly installed as `\init`. This is not the recommended way to build a workload, but a practical compromise.

The main reason of this it that a workload is needed to test `riscv64-nutshell_defconfig` in the CI flow of NEMU. However, hardware floating point is not supported by nutshell. The C library is built with hardware floating point. On RISC-V, the ABI is different with or without hardware floating point. So it is impossible to build a C program without hardware floating point on it.

- It is an overkill to build a C library without hardware floating point specially for nutshell. The only workload running on it is a smoke test.
- It is not a good practice to build the C library used by nearly all Linux workloads without hardware floating point. Most workloads absolutely need hardware floating point.
- We cannot use any programs linked against the C library, including the programs provided by busybox. `fld` and `fsd` instructions are executed even if there are no real floating point operations. This is an ABI feature.
- It is possible to use the same kernel on RISC-V devices with or without hardware floating point. The kernel itself will decide which ISA extensions to use, based on information provided by the device tree.

So the solution for a Linux smoke test on nutshell is an assembly program installed as `/init`.

## Virtualization

Build Hello as a nested KVM guest and run the Host firmware with QEMU:

```sh
make linux/hello PLATFORM=qemu -jN
make virt bin=build/linux-workloads/hello/fw_payload.qemu.bin
QEMU_BIN=/path/to/qemu-system-riscv64 QEMU_MEMORY=16G \
  bash scripts/run-qemu.sh \
  build/virt/hello/host/fw_payload.qemu.bin
```
