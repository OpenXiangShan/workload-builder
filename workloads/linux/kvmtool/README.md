# `kvmtool` Workload

## Description

This workload builds and runs `lkvm`, a lightweight virtual machine manager (kvmtool) designed for KVM-based virtualization. The workload runs kvmtool in NEMU to test the H-extension implement.

## How it builds

1. Compiles the Device Tree Compiler (dtc) library with minimal configuration. This library is a dependency of `kvmtool`.
2. Builds kvmtool (lkvm) for RISC-V architecture.
3. Creates a minimal guest initramfs from the contents of the `source/guest` directory, which contains only an `inittab`.
4. Installs the compiled lkvm binary, configuration files, and guest components to the package directory. The guest kernel is the same with the host kernel. The guest just shuts down after printing a short message.

## Note

NEMU profiling mode is not turned on in this workload as it can cause problems when running virtualization. Simulating more than one core using `kvmtool` will also fail.

## Virtualization

Build kvmtool as a nested KVM guest and run the Host firmware with QEMU:

```sh
make linux/kvmtool PLATFORM=qemu -jN
make virt bin=build/linux-workloads/kvmtool/fw_payload.qemu.bin
QEMU_BIN=/path/to/qemu-system-riscv64 QEMU_MEMORY=16G \
  bash scripts/run-qemu.sh \
  build/virt/kvmtool/host/fw_payload.qemu.bin
```
