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

Multi-hart XiangShan builds select a template named
`xiangshan-fpga-noAIA-<HARTS>hart-mem8g.dts.in` from this directory.
Add the matching template before building a new hart count; the build fails if
the selected template does not exist.

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

`--harts` must be at least 2. The generator copies the CPU node for each hart,
extends the CLINT, PLIC, and debug interrupt contexts, and applies the NEMU
UARTLITE and PLIC settings. It normalizes every generated CPU to
`riscv,isa = "rv64imafdc"`.

The build does not invoke this generator automatically. Run it and review the
result before building with the corresponding `HARTS` value.

The generator can create other topologies, but multi-core firmware uses
LibCheckpoint, whose QEMU restorer currently supports only `HARTS=2`.
