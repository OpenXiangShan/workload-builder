# DTS Generator

This directory is the canonical source for workload-builder device-tree
generation. It contains `DTSGen.py`, the profile generator, the build-facing
basename generator, and profile data. Recognized `DEFAULT_DTB` names are
generated into `build/generated-dts` during the build. An unsupported custom
basename can be supplied explicitly as `dts/<name>.dts.in`; the build copies it
into the generated directory before packing the firmware.

## Generate A Template

The profile-oriented CLI is useful when creating a template explicitly:

```sh
python3 dts/generate-workload-builder-dts.py \
  --profile fpga-noaia-novec \
  --memory-gib 16 \
  --output /tmp/custom-fpga.dts.in
```

Supported profiles are `fpga-noaia-novec`, `qemu-nemu`, and `nemu`. Use
`--harts 2..128` with `qemu-nemu` for multi-hart output. `--memory-gib` and
`--memory-size` select the DRAM capacity; `--no-vector` removes vector ISA
declarations. This CLI is for inspecting or exporting a profile; Make selects
profiles through `DEFAULT_DTB` and regenerates its own build-tree copy. The
generated file contains `INITRAMFS_BEGIN_*` and
`INITRAMFS_END_*` placeholders and must be processed by the firmware packer
before it is compiled into a DTB.

The build-facing CLI accepts a complete basename and is what Make invokes:

```sh
python3 dts/generate-nemu-board-dts.py \
  --name xiangshan-qemu-nemu-2hart-mem16g \
  --output build/generated-dts/xiangshan-qemu-nemu-2hart-mem16g.dts.in
```

Built-in names include the `xiangshan`, `yanqihu`, `nutshell`, and `spike`
profiles, FPGA noAIA names, and QEMU `nemu` names of the form
`<board>[-<harts>hart][-mem<size>g][-novec]`. Unknown names use a matching
custom template passed through `--custom-template-dir`; otherwise generation
fails with an `unsupported DTS basename` error.

The bundled `boom.dts.in` custom template describes the single-hart BOOM v4
DiffTest platform: RV64IMAFDC with Zba/Zbb/Zbs, Sv39, eight PMP regions at
four-byte granularity, and 256 MiB DRAM at `0x80000000`. It uses CLINT at
`0x02000000`, PLIC at `0x0c000000`, and an ns16550 UART at `0x10000000`.
Select it with `make linux/hello DEFAULT_DTB=boom`; it uses the
`boom_defconfig` Buildroot tree with floating-point support.

Linux images with `DEFAULT_DTB=nutshell` or `nutshell-*` use
`nutshell_defconfig` (RV64IMAC/LP64) instead of `xiangshan_defconfig`.

BOOM also has two generated 2 GiB profiles: `boom-mem2g` uses the simulated
ns16550 at `0x10000000`; `boom-fpga-mem2g` uses the FPGA UART16550 at
`0x310b0000`, with a 50 MHz UART clock, `reg-shift=2`, and 32-bit accesses
(`earlycon=uart8250,mmio32,0x310b0000`). Both use Sv39, CLINT at
`0x02000000`, PLIC at `0x0c000000`, and eight PMP regions at four-byte
granularity. Neither UART declares an interrupt connection.

Linux images with `DEFAULT_DTB=boom` or `boom-*` use `boom_defconfig`
(RV64GC/LP64D userspace, V and KVM disabled in the kernel).

`nutshell` is the 128 MiB machine description used by NEMU's
`riscv64-nutshell_defconfig`: uartlite at `0x40600000`, no PLIC.
NutShell simulation uses the same map. `nutshell-mem2g` keeps that
MMIO and enlarges DRAM to 2 GiB. `nutshell-fpga` describes NutShell
FPGA: UART16550 @ `0x310b0000`, PLIC @ `0x3c000000`, 2 GiB.

All three names emit `riscv,isa = "rv64imac_zicsr_zifencei"` to match
`riscv,isa-extensions`. NutShell implements Zicsr and Zifencei; it
does not implement Zicntr or Zihpm.

Pass them as `DEFAULT_DTB=nutshell`, `DEFAULT_DTB=nutshell-mem2g`, or
`DEFAULT_DTB=nutshell-fpga`.

For generated FPGA noAIA and QEMU `nemu` names, select the ISA declaration
independently of the basename:

```sh
make linux/coremark \
  DEFAULT_DTB=xiangshan-fpga-noAIA-mem16g-novec \
  DTS_ISA_CONFIG=kunminghu-v2
```

`DTS_ISA_CONFIG` accepts `kunminghu-v2` and `kunminghu-v3`, with V3 as the
default. For QEMU `nemu`, V2 uses the intersection of the QEMU and Kunminghu
V2 ISA declarations. The `-novec` suffix still controls vector advertisement.

## NHv3a SoC Templates

Two custom templates describe the Nanhu v3a (NHv3a) SoC; they are selected by
the complete basename and are copied from this directory by the build:

* `nhv3a.dts.in` - full SoC description for a real boot: 32 GiB of DDR at
  `0x80000000`, DesignWare APB UART0 at `0x0005_0000` (`reg-shift = 2`,
  32-bit registers), CLINT at `0x3800_0000`, PLIC at `0x3C00_0000`, one
  hart (NEMU standalone; the XSTop RTL instantiates two).
* `nhv3a-minimal.dts.in` - boot-flow test profile used by the trimmed
  `linux/hello` image: 16 MiB of DDR, no PLIC node (the test has no
  external interrupts), a single UART.  This is what makes the memmap and
  the Linux PLIC probe disappear from the instruction count.

```sh
# full SoC machine
make linux/hello DEFAULT_DTB=nhv3a

# smallest modern boot: tiny 7.1 kernel + no-console OpenSBI
make linux/hello DEFAULT_DTB=nhv3a-minimal MINIMAL=1
```

## Direct DTSGen CLI

`DTSGen.py` remains available for low-level generation:

```sh
python3 dts/DTSGen.py --nr-harts 2 --memory-size 0x400000000 \
  --rva-profile rva23s64 | dtc -O dtb -o build/example.dtb -
```

## Profiles And Validation

Profile data is stored in `workload-builder-profiles.json`; generation itself is
offline.

The build invokes the generator and then uses `dtc` to compile the generated
template. This validates DTS generation, DTB compilation, and image assembly;
it does not prove that NEMU, QEMU, or FPGA hardware boots a workload
successfully.

## Contributors

The generator incorporates the `DTSGen` implementation and device-tree
conventions from OpenXiangShan's `nemu_board`. The vendored source revision is
commit `15db1e6` of
[`OpenXiangShan/nemu_board`](https://github.com/OpenXiangShan/nemu_board/commit/15db1e6cdf4dcbf4cc016cb8938a5f8f35b59faf).

GitHub authors and co-authors represented in that revision are:

- `chenguokai`
- `xyyy1420`
- `dzwduan`
- `cyyself`
- `Gs-ygc`
