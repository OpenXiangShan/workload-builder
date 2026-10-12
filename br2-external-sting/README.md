# STING virtualization

Use the separate entry for one STING bin or a directory of bins:

```shell
make sting-virt bin=/path/to/sting_00013.bin
make sting-virt bin=/path/to/sting-bins
"$NEMU_HOME/build/riscv64-nemu-interpreter" -b build/sting-virt/sting_00013/host/fw_payload.bin
```

Packages go to `build/sting-virt/<case>/`; the Host builds in
`build/buildroot-virt-host-sting/` and GCPT in
`build/LibCheckpointAlpha-sting-virt/`. This entry adds the STING Buildroot
extension alongside `br2-external/` to reuse its NEMU packages and kernel
config. Ordinary `make virt` retains its original configuration, QEMU
arguments and `VIRT_WORKLOAD_EXIT` contract. STING accepts bare-metal inputs
and requires its UART PASS/FAIL status.

`nemu_sting_host_defconfig` selects these sources and applies `patches/`
through `BR2_GLOBAL_PATCH_DIR`:

| Component | Base | Patch |
| --- | --- | --- |
| QEMU | Official 11.0.0 release | `patches/qemu/11.0.0/0001-riscv-virt-sting-kvm-m-mode-nested.patch` |
| Linux | XiangShan devel `9a299927d0b845eb91b0de48084471e595dfc283` (6.18.34) | `patches/linux/9a299927d0b845eb91b0de48084471e595dfc283/0001-riscv-kvm-sting-runtime.patch` |

QEMU enables the paired kernel's private capabilities 245/246, boots STING
in software M-mode at `0x80000000`, exposes H, and supplies UARTLite at
`0x40600000`. Run with `virt,aia=none,kvm-m-mode=on,kvm-nested=on`, KVM,
`-cpu host -bios none -serial none`. Smrnmi discovery uses the kernel's
software MN CSR bank.

The Linux patch supplies STING's selector CSRs, 32 PMP entries, Smrnmi CSR
storage, no-trigger TSELECT/TDATA1 behavior, MPRV cache-block operations and
HPM counter reads. It also guards physical VSISELECT access on hosts
without AIA. The base devel kernel already provides software M-mode,
nested virtualization and the `sting_5006b_shutdown` module parameter.

The Host launcher sets that parameter to zero and waits for STING UART
PASS/FAIL before reporting its status through NEMU. Guest payload bytes
are unchanged; raw binaries receive only an ELF load header.

The original `sting_00001.bin` and `sting_00013.bin` passed the NEMU → Host
Linux → patched public QEMU/KVM path. Tests execute the generated launcher
to check that an exit-zero marker alone cannot report STING success.
