# Device Tree Templates

This directory contains device tree templates for each device configuration. For each workload, device tree files are generated from the template on the fly, because some parameters cannot be known in advance.

## Parameters

These parameters are replaced with the corresponding values when building the workloads:

- `INITRAMFS_BEGIN`: Begin address of the initramfs containing the workload.
- `INITRAMFS_END`: End address of the initramfs containing the workload.

## Device Configurations

- `xiangshan.dts.in`: This device tree template is for the `riscv64-xs_defconfig` NEMU configuration.
- `yanqihu.dts.in`: This device tree template is for the `riscv64-yanqihu_defconfig` NEMU configuration.
- `nutshell.dts.in`: This device tree template is for the `riscv64-nutshell_defconfig` NEMU configuration.
- `xiangshan-fpga-noAIA-novec.dts.in`: Base XiangShan FPGA DTS without vector extensions.
- `xiangshan-fpga-noAIA-mem8g-novec.dts.in`: XiangShan FPGA DTS without vector extensions, with an 8 GiB memory profile.
- `xiangshan-fpga-noAIA-mem24g-novec.dts.in`: XiangShan FPGA DTS without vector extensions, with a 24 GiB memory profile.
- `xiangshan-fpga-noAIA-mem64g-novec.dts.in`: XiangShan FPGA DTS without vector extensions, with a 64 GiB memory profile.

Multi-hart XiangShan builds require the user to select a complete DTS basename
with `DEFAULT_DTB`; the build no longer assumes a `mem8g` suffix. For example,
`DEFAULT_DTB=xiangshan-fpga-noAIA-32hart-mem64g` selects
`xiangshan-fpga-noAIA-32hart-mem64g.dts.in`. The matching template must exist;
the build fails if it does not.

## Single-Core Physical Memory Map

Single-core images use `MULTIHART=0` and LibCheckpointAlpha. They keep the
original compact placement below; the multi-hart checkpoint-state reservation
and the `0x88600000` kernel address do not apply:

| Physical address / range | Size or offset | Assignment |
|-------------------------|----------------|------------|
| `0x80000000–0x800fffff` | 1 MiB | LibCheckpointAlpha checkpoint-recovery program; reserved as `no-map` in the DTS |
| `0x80100000` | +1 MiB | OpenSBI firmware starts here |
| `0x80180000` | +1.5 MiB | Device tree placed here by firmware assembly |
| `0x80200000` and above | +2 MiB | Linux kernel image, then the MiB-aligned initramfs |

The single-core firmware packer uses `DTB_OFFSET_KB=1536`,
`SBI_OFFSET_KB=1024`, and `KERNEL_OFFSET_MB=2`. The initramfs address is
computed from the actual kernel size and starts at the next MiB boundary. The
selected single-core DTS supplies the DRAM capacity; no fixed 8 GiB or 64 GiB
profile is imposed by this layout.

## Multi-Hart Physical Memory Map

All `MULTIHART=1` images use the same physical placement, regardless of the
selected DRAM capacity or hart count. The image is loaded at `0x80000000`:

| Physical range | Size | Assignment |
|----------------|------|------------|
| `0x80000000–0x800fffff` | 1 MiB | LibCheckpoint/GCPT checkpoint-recovery program |
| `0x80100000–0x802fffff` | 2 MiB | OpenSBI firmware; the selected DTB is placed at `0x80200000` |
| `0x80300000–0x885fffff` | 131 MiB | `no-map` checkpoint register-state reservation |
| `0x88600000` and above | — | Linux kernel image, then the MiB-aligned initramfs |

The checkpoint reservation is `[0x80300000, 0x88600000)`. LibCheckpoint uses
one 1 MiB state slot per hart and currently allocates startup/restore storage
for at most 128 harts. Therefore the build accepts `HARTS=2..128`; the 131 MiB
window includes the slots plus alignment headroom before Linux.

The kernel address is derived from the OpenSBI placement:

```text
FW_TEXT_START     = 0x80100000
FW_PAYLOAD_OFFSET = 0x08500000
Linux entry       = 0x88600000
```

The unified addresses do not force a single DRAM size. The repository's
standard templates retain these profiles:

| Template | DRAM |
|----------|------|
| `xiangshan-fpga-noAIA-2hart-mem8g` | 8 GiB |
| `xiangshan-fpga-noAIA-32hart-mem64g` | 64 GiB |

Select the complete template basename explicitly when building, for example:

```sh
make linux/hello MULTIHART=1 HARTS=2 \
  DEFAULT_DTB=xiangshan-fpga-noAIA-2hart-mem8g
```

## Generate Multi-Hart XiangShan DTS

Run the generator from the repository root to create a template for a new
hart count. For example, generate the two-hart template from the 8 GiB
XiangShan FPGA baseline with:

```shell
python3 scripts/generate-xiangshan-multihart-dts.py \
  --base dts/xiangshan-fpga-noAIA-mem8g.dts.in \
  --harts 2 \
  --output dts/xiangshan-fpga-noAIA-2hart-mem8g.dts.in
```

`--harts` must be in the range 2 through 128. The generator copies the CPU node for each hart,
extends the CLINT, PLIC, and debug interrupt contexts, and applies the NEMU
UARTLITE and PLIC settings. It normalizes every generated CPU to
`riscv,isa = "rv64imafdc"`. Generated multi-hart templates reserve the fixed
131 MiB checkpoint window `[0x80300000, 0x88600000)`.

The build does not invoke this generator automatically. Run it and review the
result before building with the corresponding `HARTS` value.

The generator can create other topologies. For multi-core firmware, set
`HARTS` in the range 2 through 128 to match both the generated template and the
QEMU checkpoint, and pass that template through `DEFAULT_DTB`. Every
multi-hart image uses DTB address `0x80200000` and kernel address
`0x88600000`; the fixed placement keeps the 131 MiB checkpoint window at
`0x80300000` clear of the boot payload.
