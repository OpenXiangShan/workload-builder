# litmus-tests-riscv Workload

## Description

These are litmus tests for the RISC-V concurrency architecture, as used by members of the RISC-V Memory Model Task Group during the architecture development.

This is a Linux workload.

## Virtualization

Build the litmus tests as a nested KVM guest and run the Host firmware with QEMU:

```sh
make linux/litmus-tests-riscv PLATFORM=qemu -jN
make virt bin=build/linux-workloads/litmus-tests-riscv/fw_payload.qemu.bin
QEMU_BIN=/path/to/qemu-system-riscv64 QEMU_MEMORY=16G \
  bash scripts/run-qemu.sh \
  build/virt/litmus-tests-riscv/host/fw_payload.qemu.bin
```
