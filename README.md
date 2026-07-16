# NEMU Workload Builder

This repository serves as an automated build system to build the workloads of NEMU for testing purpose. It supports two types of workloads:

1. **Linux workloads**: Traditional Linux-based workloads that run on top of the Linux kernel with initramfs
2. **AM workloads**: Bare-metal applications that run directly on the Abstract Machine (AM) abstraction layer

## Get Started

Simply run `make` under the repository. The Linux kernel, the workloads and the loadable images will be built automatically. The resulting files will end up in the `build` directory:

For Linux workloads:

- `build/linux-workloads/workload_name/fw_payload.bin`: The all-in-one image that can be directly loaded by NEMU.
- `build/linux-workloads/workload_name/rootfs.cpio`: The initramfs overlay of the workload.
- `build/linux-workloads/workload_name/dt/`: A directory containing device tree files.

For AM workloads:

- `build/am-workloads/workload_name/package/`: Directory containing the compiled binaries.

You can also build a single workload with:

- `make linux/workload_name` for a Linux workload.
- `make am/workload_name` for an AM workload.

SPEC Linux workloads can also build multi-hart rootfs images:

```shell
make linux/spec2006 BENCH=astar INPUT=biglakes \
  SPEC2006_ISO=/path/to/cpu2006.iso \
  MULTIHART=1 HARTS=2 -jN
```

`MULTIHART=1` creates per-hart workload directories, uses `/bin/nemu-trap` to
send codes 256 and 257 before each benchmark copy and code 258 after it
returns, and selects
`xiangshan-fpga-noAIA-<HARTS>hart-mem8g` as the default DTB when `DEFAULT_DTB`
is not set. Its matching template must exist in `dts/`; the build fails rather
than generating a missing multi-hart DTS.

Single-core firmware uses LibCheckpointAlpha. Multi-core firmware uses
LibCheckpoint to restore QEMU multi-hart checkpoints. Set `HARTS` to match
the checkpoint and the selected device-tree template.

## Workload Compatibility

Not all workloads can run on all NEMU configurations. The only workload supported by `riscv64-nutshell_defconfig` is `linux/hello`, since all other workloads require hardware floating point, which is not supported by nutshell. RVV related workloads require the vector ISA extension, and hypervisor related workloads require the hypervisor ISA extension.

## Build Requirements

Any modern Linux distributions should be okay. The build system of this project is using the toolchain provided by buildroot, so you do not have to set up the toolchains manually to build most workloads. Some workloads require additional toolchians not provided by buildroot. Please refer to the README file of each workload (`README.md` in the workload directory) for details.

To create a compressed tarball containing all built workloads, run `make tarball`. This will generate `build/workloads.tar.zstd` which contains all Linux firmware images, root filesystems, and AM workload binaries in a single archive file.

## TODO List

- [x] Add workload `kvmtool`.
- [ ] Add workload `Xvisor`.
- [x] Support for building multiple device trees for each Linux workload.
- [ ] Test Linux workloads with checkpoint functionalities of NEMU.

## Format of the Image

### Linux Workloads

For Linux workloads, the image assumes that execution begins at `0x80000000`, and the image is loaded into a continuous memory starting from that address. The image contains the following content:

| Offset  | Content                       |
|---------|-------------------------------|
| 0.0 MiB | LibCheckpointAlpha (single-core) / LibCheckpoint (multi-core) |
| 1.0 MiB | OpenSBI                       |
| 1.5 MiB | device tree                   |
| 2.0 MiB | Linux kernel                  |
| --      | initramfs containing workload |

Multiple device trees are built for each workload, each corresponds to a specific NEMU configuration. The device tree files are placed under the `dt` directory in the build output directory of that workload. The "default" device tree built into the image is `dt/xiangshan.dtb`. To replace the device tree, the following command can be used:

For DTS files used with gcpt, the beginning of RAM must be reserved with a `reserved-memory` node so Linux does not allocate or map the gcpt checkpoint buffer. The XiangShan FPGA DTS templates reserve 1 MiB at `0x80000000` for this purpose.

```shell
dd conv=notrunc bs=1024 seek=1536 if=dt/some_device.dtb of=fw_payload.bin
```

OpenSBI is patched (see `bootloader/opensbi.patch`) to load the device tree from a fixed location. The initramfs is placed after the Linux kernel and aligned to 1 MiB.

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

To add a device tree, simply create a template file `device_name.dts.in` in the `dts` directory. It will be automatically found by the build system.

Currently, the memory location of the initramfs containing the workload is passed to the kernel by device tree. So for each workload, device tree files are generated from the template on the fly, because the size of the initramfs cannot be known in advance. You should use the parameters `INITRAMFS_BEGIN` and `INITRAMFS_END` in the device tree template. 

```dts
chosen {
    bootargs = "console=hvc0 earlycon=sbi";
    linux,initrd-start = <0x0 INITRAMFS_BEGIN>;
    linux,initrd-end = <0x0 INITRAMFS_END>;
};
```
