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
