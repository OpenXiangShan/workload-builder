# NEMU/QEMU Workload Builder

This repository serves as an automated build system to build workloads for
NEMU and the QEMU NEMU machine. It supports two types of workloads:

1. **Linux workloads**: Traditional Linux-based workloads that run on top of the Linux kernel with initramfs
2. **AM workloads**: Bare-metal applications that run directly on the Abstract Machine (AM) abstraction layer

## Get Started

Simply run `make` under the repository. The Linux kernel, the workloads and the loadable images will be built automatically. The resulting files will end up in the `build` directory:

For Linux workloads:

- `build/linux-workloads/workload_name/fw_payload.bin` (NEMU) or `fw_payload.qemu.bin` (QEMU): The all-in-one image that can be directly loaded by the selected machine.
- `build/linux-workloads/workload_name/rootfs.cpio`: The initramfs overlay of the workload.
- `build/linux-workloads/workload_name/dt/`: The selected device tree source and binary.

For AM workloads:

- `build/am-workloads/workload_name/package/`: Directory containing the compiled binaries.

You can also build a single workload with:

- `make linux/workload_name` for a Linux workload.
- `make am/workload_name` for an AM workload.

Single-core workloads default to NEMU. QEMU support covers CoreMark, SPEC
CPU2006, and SPEC CPU2017, which can be assembled with `PLATFORM=qemu`:

```shell
make linux/coremark PLATFORM=qemu -jN
make linux/spec2006 PLATFORM=qemu BENCH=astar INPUT=biglakes \
  SPEC2006_ISO=/path/to/cpu2006.iso -jN
```

QEMU firmware is written beside the NEMU image as `fw_payload.qemu.bin`, so
switching platforms does not overwrite `fw_payload.bin` or rebuild the shared
benchmark/rootfs unnecessarily. Run the completed workload with:

```shell
QEMU_BIN=/path/to/qemu-system-riscv64 \
  bash scripts/run-qemu.sh \
  build/linux-workloads/coremark/fw_payload.qemu.bin
QEMU_BIN=/path/to/qemu-system-riscv64 \
  bash scripts/run-qemu.sh \
  build/linux-workloads/spec2006/astar_biglakes/fw_payload.qemu.bin
```

Building does not require a QEMU installation. The verified baseline is
OpenXiangShan/qemu commit `d6ef1ba720` from `fix/nemu-uart16550`; the runner
requires `QEMU_BIN` and checks for the equivalent `nemu` machine device contract
before booting. It uses TCG and treats only `Hit GOOD TRAP` as success. It
defaults to 2 GiB of RAM; set `QEMU_MEMORY` to match the selected multi-hart DTS
when needed.

CoreMark, SPEC CPU2006, and SPEC CPU2017 also support multi-hart QEMU rootfs images:

```shell
make linux/coremark MULTIHART=1 HARTS=2 \
  DEFAULT_DTB=xiangshan-fpga-noAIA-2hart-mem8g-novec -jN

make linux/spec2006 BENCH=astar INPUT=biglakes \
  SPEC2006_ISO=/path/to/cpu2006.iso \
  MULTIHART=1 HARTS=2 \
  DEFAULT_DTB=xiangshan-fpga-noAIA-2hart-mem8g-novec -jN
```

`MULTIHART=1` automatically selects `PLATFORM=qemu`; explicitly combining it
with `PLATFORM=nemu` is rejected. It creates per-hart workload directories,
uses `/bin/nemu-trap` to send codes 256 and 257 before each benchmark copy and
code 258 after it returns, and requires `DEFAULT_DTB` to be set to the complete
DTS basename. Its matching template must exist in `dts/`; the build fails
rather than guessing a memory profile or generating a missing multi-hart DTS.
Other Linux workload targets remain NEMU-only.

Single-core firmware uses LibCheckpointAlpha. Multi-core firmware uses
LibCheckpoint to restore QEMU multi-hart checkpoints. Set `HARTS` to match
the checkpoint and the selected device-tree template; supported multi-hart
counts are 2 through 128. All multi-hart images reserve the 131 MiB checkpoint
window `[0x80300000, 0x88600000)` and load Linux at `0x88600000`. Multi-hart
builds default `GCPT_SERIAL_PORT` to the QEMU 16550A TX register at
`0x310b0000`; the build passes it to LibCheckpoint as `CONFIG_SERIAL_PORT`.

## Workload Compatibility

Not all workloads can run on all NEMU or QEMU configurations. QEMU support is
limited to `linux/coremark`, `linux/spec2006`, and `linux/spec2017`; the only workload supported by
`riscv64-nutshell_defconfig` is `linux/hello`, since all other workloads require
hardware floating point, which is not supported by nutshell. RVV related workloads
require the vector ISA extension, and hypervisor related workloads require the
hypervisor ISA extension.

## Build Requirements

Any modern Linux distributions should be okay. The build system of this project is using the toolchain provided by buildroot, so you do not have to set up the toolchains manually to build most workloads. Some workloads require additional toolchians not provided by buildroot. Please refer to the README file of each workload (`README.md` in the workload directory) for details.

To create a compressed tarball containing all built workloads, run `make tarball`. This will generate `build/workloads.tar.zstd` which contains all Linux firmware images, root filesystems, and AM workload binaries in a single archive file.

## TODO List

- [x] Add workload `kvmtool`.
- [ ] Add workload `Xvisor`.
- [x] Support for selectable device tree templates.
- [ ] Test Linux workloads with checkpoint functionalities of NEMU.

## Format of the Image

### Linux Workloads

For single-core Linux workloads, execution begins at the DRAM base from the
selected DTS, and the image is loaded into continuous memory starting there.
A single-core image contains:

| Offset  | Content                       |
|---------|-------------------------------|
| 0.0 MiB | LibCheckpointAlpha            |
| 1.0 MiB | OpenSBI                       |
| 1.75 MiB | device tree                  |
| 2.0 MiB | Linux kernel                  |
| --      | initramfs containing workload |

Single-core images place the DTB at 1.75 MiB (`0x801c0000`), providing 768 KiB
for OpenSBI while leaving 256 KiB for the DTB before Linux at 2 MiB. This is an
image-packing choice, not a fixed machine address. The assembler checks both
component sizes. Multi-hart images keep their separate DTB address at
`0x80200000`.

A multi-hart image uses the fixed QEMU checkpoint layout:

| Physical address range | Size | Content |
|------------------------|------|---------|
| `0x80000000–0x800fffff` | 1 MiB | LibCheckpoint recovery program |
| `0x80100000–0x802fffff` | 2 MiB | OpenSBI, with the DTB at `0x80200000` |
| `0x80300000–0x885fffff` | 131 MiB | Checkpoint state window (`no-map`) |
| `0x88600000+` | -- | Linux kernel, followed by the MiB-aligned initramfs |

For OpenSBI, the multi-hart image uses `FW_TEXT_START=0x80100000`,
`FW_JUMP_ADDR=0x88600000`, and `FW_JUMP_FDT_ADDR=0x80200000`.

The canonical single-core and multi-hart DTS memory maps, including DRAM
profiles and DTS selection examples, are in [dts/README.md](dts/README.md#single-core-physical-memory-map).

For single-core images, the selected DTS is the source of truth for the DRAM
base used by GCPT, OpenSBI, the firmware packer, and the exported manifest, as
well as the CLINT address used by GCPT. Its generated DTS and DTB are placed in
the workload's `dt` directory and the DTB is embedded in the firmware image.

For DTS files used with gcpt, the beginning of RAM must be reserved with a `reserved-memory` node so Linux does not allocate or map the gcpt checkpoint buffer. The XiangShan FPGA DTS templates reserve the first 1 MiB of their declared DRAM for this purpose.

```shell
dd conv=notrunc bs=1024 seek=1792 if=dt/some_device.dtb of=fw_payload.bin
```

Use `fw_payload.qemu.bin` as the output file for a QEMU image. The supported
QEMU `nemu` machine exposes a no-IRQ 16550A UART at `0x310b0000`. Multi-hart
images use their separate fixed DTB offset of 2048 KiB and must retain a
matching multi-hart device tree.

OpenSBI is patched (see `bootloader/opensbi.patch`) to load the device tree from a fixed offset relative to the DRAM base. The initramfs is placed after the Linux kernel and aligned to 1 MiB.

### AM Workloads

For AM workloads, the image is a bare-metal binary that runs directly on the hardware. These workloads are built using the Abstract Machine (AM) framework and do not require a Linux kernel or initramfs.

## How is the Linux Kernel Built

The Linux kernel is built using buildroot for Linux workloads. The `br2-external` subdirectory is a br2-external tree used for building the kernel. The kernel is built with a built-in initramfs containing:

- A musl dynamic C library
- BusyBox-based init and core utilities
- `/bin/nemu-trap` for sending a debug call to NEMU
- `/bin/nemu-exec` as a workload launcher.

When called without arguments, `/bin/nemu-trap` stops NEMU with exit code 0. When called with arguments, it sends debug signal to NEMU using the code from the first argument, which must be a decimal integer.

`/bin/nemu-exec` should be called with arguments specifying the workload. It disables NEMU timer interrupt, makes NEMU to enter simpoint profiling mode, starts the workload, and stops NEMU with the exit code of the workload. `nemu-exec cmd arg1 arg2` is roughly equivalent with:

```shell
nemu-trap 256
nemu-trap 257
cmd arg1 arg2
nemu-trap $?
```

For more information about NEMU debug calls and simpoint, please refer to [Xiangshan Docs](https://docs.xiangshan.cc/zh-cn/latest/tools/simpoint/).

## How are Linux Workloads Built

Each Linux workload becomes a binary file that NEMU loads directly. This file contains the device tree, OpenSBI, the Linux kernel, and the workload. Each sub-directory of `workloads` is a "workload directory" defining how to build a workload. The build occurs in an ad hoc source directory, and the resulting files install into an ad hoc package directory. The package directory's content overlays the Linux kernel's built-in initramfs.

Each workload directory should contain:

- An optional `source` sub-directory, which should be a git submodule pointing to the workload's upstream repository or contain the workload's source code.
- An optional `links.txt` file with download links for files needed to build the workload, such as source tarballs or pre-built binaries. Each line in `links.txt` must follow the format: `file_name link sha256sum`.
- A `build.sh` script that builds the workload. After `build.sh` exits normally, the package directory must contain everything needed to run the workload, including the executable, dependencies, and an `/etc/inittab` that starts the workload and stops NEMU after it finishes.
- Any other necessary files, such as an `inittab` to start the workload, patches for building, or configuration files.

For each Linux workload, the build system follows these steps:

1. Copies the workload directory's `source` sub-directory to a temporary location as the source directory for an off-tree build. If `source` does not exist, an empty directory is created. If the source directory already exists, it is deleted first.
2. If `links.txt` exists, downloads each file listed in it to the ad hoc source directory.
3. Creates the package directory. If the package directory already exists, it is deleted first.
4. Invokes the corresponding `build.sh` to build the workload and install it into the package directory. After `build.sh` exits normally, the package directory must have a sub-directory `bin` containing all binaries images of this workload. It can optionally contain other sub-directories, for example, a sub-directory `elf` contaioning all images in the ELF format.
5. Packs the package directory into an initramfs cpio archive.
6. Assembles the OpenSBI binary, Linux kernel, and initramfs (containing the workload) into a single binary file that NEMU loads directly.

Each `build.sh` script must access build information through these environment variables:

- `WORKLOAD_DIR`: the workload directory. The build script should not modify anything here.
- `SRC_DIR`: the ad hoc source directory. The build script can write to this directory.
- `PKG_DIR`: the ad hoc package directory. The build script can write to this directory.
- `CROSS_COMPILE`: the cross-compilation toolchain prefix, for example, `riscv64-linux-gnu-`.
- `SYSROOT_DIR`: the directory of the sysroot used for building the workload.  The build script should not modify anything here.
- `BUILDROOT_DIR`: the buildroot directory. The build script should not modify anything here.

## How are AM Workloads Built

AM (Abstract Machine) workloads are bare-metal applications that run directly on the hardware abstraction layer. These workloads use the Nexus-AM framework and do not require a Linux kernel.

Each AM workload directory should contain:

- An optional `source` sub-directory, which should be a git submodule pointing to the workload's upstream repository or contain the workload's source code.
- An optional `links.txt` file with download links for files needed to build the workload.
- A `build.sh` script that builds the workload using the AM framework.

For each AM workload, the build system follows these steps:

1. Copies the AM framework to a dedicated temporary location for building this workload.
2. Copies the workload directory's `source` sub-directory to a temporary location as the source directory for an off-tree build.
3. If `links.txt` exists, downloads each file listed in it to the ad hoc source directory.
4. Creates the package directory. If the package directory already exists, it is deleted first.
5. Invokes the corresponding `build.sh` to build the workload and install it into the package directory.

Each AM `build.sh` script has access to these environment variables:

- `WORKLOAD_DIR`: the workload directory. The build script should not modify anything here.
- `SRC_DIR`: the ad hoc source directory. The build script can write to this directory.
- `PKG_DIR`: the ad hoc package directory. The build script can write to this directory.
- `CROSS_COMPILE`: the cross-compilation toolchain prefix, for example, `riscv64-linux-gnu-`.
- `AM_HOME`: the dedicated temporary location which the AM framework is copied to. The build script can write to this directory.

## Adding a Workload

You can add a workload with the following steps:

### Adding a Linux Workload

1. Add a workload subdirectory in `workloads/linux` as stated above for Linux workloads.
2. Add `$(eval $(call add_workload_linux,workload_name))` in the Makefile.

### Adding an AM Workload

1. Add a workload subdirectory in `workloads/am` as stated above for AM workloads.
2. Add `$(eval $(call add_workload_am,workload_name))` in the Makefile.

Then run `make` to build your new workload.

## Adding a Device Tree

To add a device tree, create a template file `device_name.dts.in` in the `dts`
directory and select it with `DEFAULT_DTB=device_name`.

Currently, the memory location of the initramfs containing the workload is passed to the kernel by device tree. So for each workload, device tree files are generated from the template on the fly, because the size of the initramfs cannot be known in advance. You should use the parameters `INITRAMFS_BEGIN` and `INITRAMFS_END` in the device tree template. 

```dts
chosen {
    bootargs = "console=hvc0 earlycon=sbi";
    linux,initrd-start = <0x0 INITRAMFS_BEGIN>;
    linux,initrd-end = <0x0 INITRAMFS_END>;
};
```
