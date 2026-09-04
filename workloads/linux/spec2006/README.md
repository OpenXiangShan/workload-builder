# SPEC CPU2006 Linux workload

`workloads/linux/spec2006` now builds SPEC CPU2006 workloads with the original
SPEC tools (`runspec`) from a prepared workspace installed from a SPEC ISO.

## Build one case

Point `SPEC2006_ISO` at the SPEC ISO:

```sh
make linux/spec2006 BENCH=astar INPUT=biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN
```

`BENCH` may also be a full case name from `spec06.json`:

```sh
make linux/spec2006 BENCH=astar_biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN
```

The build flow is:

1. Run `make spec2006-prepare SPEC2006_ISO=/path/to/cpu2006.iso` to install a build-local
   writable SPEC workspace under `build/linux-workloads/spec2006/spec-src`.
2. Generate a build-local SPEC cfg copy under the case build directory.
3. Inject `output_root` into that cfg so SPEC build artifacts stay under this
   repository instead of modifying the prepared SPEC workspace.
4. Run `runspec --action build` inside the prepared workspace.
5. Export the built SPEC ELF, package the benchmark plus input files into the
   Linux rootfs, and produce:

```text
build/linux-workloads/spec2006/<case>/fw_payload.bin
```

## Build and run with QEMU

Use `PLATFORM=qemu` to assemble the same single-core benchmark/rootfs for the
QEMU NEMU machine:

```sh
make linux/spec2006 PLATFORM=qemu BENCH=astar INPUT=biglakes \
  SPEC2006_ISO=/path/to/cpu2006.iso -jN
```

This writes
`build/linux-workloads/spec2006/<case>/fw_payload.qemu.bin` without replacing
the NEMU `fw_payload.bin`. Run the Astar BigLakes case with:

```sh
QEMU_BIN=/path/to/qemu-system-riscv64 \
  bash scripts/run-qemu.sh \
  build/linux-workloads/spec2006/astar_biglakes/fw_payload.qemu.bin
```

Building does not require QEMU. The runner requires `QEMU_BIN` to name a
compatible executable. Single-core QEMU mode uses the 2 GiB NEMU-machine DTS
with a no-IRQ 16550A UART at `0x310b0000` and does not enable SimPoint
profiling or checkpoint generation.

## Build and export images

Export all selected cases to `build/images/spec2006`:

```sh
make spec2006-images SPEC2006_ISO=/path/to/cpu2006.iso -jN
```

By default, export builds only `ref` cases. Select another input set with
`SPEC2006_INPUT`; use `all` to export every configured case:

```sh
make spec2006-images SPEC2006_ISO=/path/to/cpu2006.iso SPEC2006_INPUT=test -jN
make spec2006-images SPEC2006_ISO=/path/to/cpu2006.iso SPEC2006_INPUT=all -jN
```

Export a single configured case with `BENCH`:

```sh
make spec2006-images BENCH=mcf SPEC2006_ISO=/path/to/cpu2006.iso -jN
make spec2006-images BENCH=astar_biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN
```

Adding `PLATFORM=qemu` exports the complete QEMU artifact tree to the same
`build/images/spec2006` directory. Its firmware is
`bin/<case>.fw_payload.bin`.

By default, NEMU firmware embeds `dts/xiangshan-fpga-noAIA-novec.dts.in`, while
QEMU firmware embeds `dts/xiangshan-qemu-nemu-mem2g.dts.in`. Override the
platform default with `DEFAULT_DTB` if you need another DTS template:

```sh
make linux/spec2006 BENCH=astar INPUT=biglakes \
  DEFAULT_DTB=xiangshan-fpga-noAIA-novec \
  SPEC2006_ISO=/path/to/cpu2006.iso -jN
```

## Build a multi-hart workload

Add `MULTIHART=1 HARTS=<count>`, where `<count>` matches the QEMU checkpoint
and the selected device-tree template. Supported counts are 2 through 128:

```sh
make linux/spec2006 BENCH=astar INPUT=biglakes \
  SPEC2006_ISO=/path/to/cpu2006.iso \
  MULTIHART=1 HARTS=2 \
  DEFAULT_DTB=xiangshan-fpga-noAIA-2hart-mem8g-novec -jN
```

`MULTIHART=1` automatically selects `PLATFORM=qemu`; explicitly setting
`PLATFORM=nemu` is rejected. The resulting firmware is
`build/linux-workloads/spec2006/<case>/fw_payload.qemu.bin`. When running it,
set `HARTS` and `QEMU_MEMORY` to match the selected DTS:

```sh
QEMU_BIN=/path/to/qemu-system-riscv64 QEMU_MEMORY=8G \
  HARTS=2 bash scripts/run-qemu.sh \
  build/linux-workloads/spec2006/astar_biglakes/fw_payload.qemu.bin
```

The package step creates one SPEC tree per hart:

```text
/spec_common/launch_multihart.sh
/spec0/task.sh
/spec1/task.sh
...
/spec<N-1>/task.sh
```

Each `task.sh` uses `/bin/nemu-trap 256` and `/bin/nemu-trap 257` before
starting that hart's benchmark copy with `SPEC_ROOT=/specX`, then uses
`/bin/nemu-trap 258` after it returns. The launcher uses `taskset -c X` for
CPU binding.

When `MULTIHART=1`, `DEFAULT_DTB` must be the complete DTS basename, including
the desired memory profile. The corresponding `dts/<DEFAULT_DTB>.dts.in`
template must exist; firmware assembly fails if it is missing.

Selected SPEC cases are built one by one to avoid concurrent `runspec`
instances contending on shared temporary state inside the SPEC tool tree.

The export directory is organized as:

```text
build/images/spec2006/
  bin/<case>.fw_payload.bin
  kernel/<case>.vmlinux
  kernel/<case>.System.map
  kernel/<case>.config
  rootfs/<case>.rootfs.cpio
  dt/<case>.dtb
  dt/<case>.dts
  elf/<case>.elf
  cmd/<case>.run.sh
  gcpt/gcpt.elf
  gcpt/gcpt.bin
  opensbi/fw_jump.elf
  opensbi/defconfig
  manifest/<case>.json
  cfg/<spec-cfg-name>
  logs/build_elf/<case>.log
  stamps/<case>.images.stamp
```

`bin/` is the directly loadable firmware image and `rootfs/` is its initramfs.
`kernel/` contains the ELF kernel plus its symbol map and configuration for
debugging; `dt/` contains the exact DTB and generated DTS used by that case.
`manifest/` records component hashes and load addresses. `gcpt/`, `cfg/`, and
`opensbi/` are shared by cases within the export tree.

Re-running `make spec2006-images` rebuilds the export tree for the selected
platform, so a QEMU export replaces the previously exported NEMU artifacts in
the same directory.

Override the destination with `SPEC2006_IMAGE_DIR=/path/to/image`; the explicit
path is used as-is. Use a separate custom directory if both NEMU and QEMU
exports must be kept, because each run replaces the complete output tree.

## Build ELF only

Build one case without packaging it into the Linux rootfs:

```sh
make spec2006-elf BENCH=astar INPUT=biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN
```

This writes:

```text
build/linux-workloads/spec2006/<case>/elf/<case>.elf
```

Build every selected case as ELF only:

```sh
make spec2006-elfs SPEC2006_ISO=/path/to/cpu2006.iso SPEC2006_INPUT=ref -jN
make spec2006-elfs SPEC2006_ISO=/path/to/cpu2006.iso SPEC2006_INPUT=all -jN
```

If you only want the standalone ELF build flow, you can run it from this
directory without the top-level Makefile:

```sh
cd workloads/linux/spec2006
make -f rules.mk spec2006-elf BENCH=astar INPUT=biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN
make -f rules.mk spec2006-elfs SPEC2006_ISO=/path/to/cpu2006.iso SPEC2006_INPUT=all -jN
```

## Configuration

The default SPEC cfg is the GCC 16 RVA23U64 no-vector configuration:

```text
workloads/linux/spec2006/configs/gcc16-linux-riscv64-rva23u64_novec.cfg
```

For GCC 15, select:

```text
workloads/linux/spec2006/configs/riscv_gcc15_base.cfg
```

Override it with:

```sh
make linux/spec2006 BENCH=bzip2_source \
  SPEC2006_ISO=/path/to/cpu2006.iso \
  SPEC2006_CFG=/path/to/other.cfg \
  -jN
```

The default tuning level is `base`. Override it with `SPEC2006_TUNE=peak`.

Case definitions remain in `spec06.json`; they describe the benchmark name,
required input files/directories, command-line arguments, and input set.

## Toolchain and jemalloc

The default cross prefix is:

```text
riscv64-unknown-linux-gnu-
```

Override it with `SPEC2006_CROSS_COMPILE=/path/to/bin/riscv64-unknown-linux-gnu-`.

The helper derives the toolchain root from `SPEC2006_CROSS_COMPILE` and exports
the env vars expected by the default config (or a custom config):

- `LLVM_INSTALL_PATH`
- `GNU_RISCV64_PATH`
- `JEMALLOC_INSTALL_PATH`

If you need to override them directly, use:

- `SPEC2006_COMPILER_ROOT`
- `SPEC2006_GNU_TOOLCHAIN_ROOT`
- `SPEC2006_JEMALLOC_ROOT`

If the selected cfg references jemalloc and the library is missing, the build
automatically clones upstream jemalloc and installs it into:

```text
build/linux-workloads/spec2006/jemalloc/install
```

Override the install prefix with `SPEC2006_JEMALLOC_ROOT` or
`JEMALLOC_INSTALL_PATH`. Override the jemalloc source/checkout with:

- `SPEC2006_JEMALLOC_REPO`
- `SPEC2006_JEMALLOC_COMMIT`
- `SPEC2006_JEMALLOC_CONFIGURE_HOST`
- `SPEC2006_DOWNLOAD_RETRIES`

## Logs

SPEC2006 builds keep console output concise. Detailed logs are written to:

- `build/linux-workloads/spec2006/<case>/logs/build.log`
- `build/linux-workloads/spec2006/jemalloc/build.log`

## Notes

- The original SPEC ISO is used read-only as installation media.
- `runspec` is never executed against the original ISO contents; it only sees the
  prepared workspace under `build/linux-workloads/spec2006/spec-src`.
- The prepared workspace is installed into a writable build directory before
  any SPEC tools are executed.
- Installation staging uses a temporary local filesystem; override
  `SPEC2006_PREPARE_TMPDIR` if `/tmp` is not suitable.
- `xorriso` is required to extract the SPEC ISO during `spec2006-prepare`.
- Build logs, copied cfg files, build directories, and built executables are
  redirected into the case-local `runspec-output` directory via `output_root`.
- The source cfg in this repository is never passed to `runspec` directly;
  `runspec` is allowed to rewrite only the generated local cfg copy.
