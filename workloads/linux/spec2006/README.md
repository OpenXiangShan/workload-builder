# SPEC CPU2006 Linux workload

`workloads/linux/spec2006` now builds SPEC CPU2006 workloads with the original
SPEC tools (`runspec`) against an external SPEC installation.

## Build one case

Either point `SPEC` at the SPEC tree:

```sh
make linux/spec2006 BENCH=astar INPUT=biglakes SPEC=/path/to/cpu2006 -jN
```

or pass `SPEC2006` explicitly:

```sh
make linux/spec2006 BENCH=astar INPUT=biglakes SPEC2006=/path/to/cpu2006 -jN
```

`BENCH` may also be a full case name from `spec06.json`:

```sh
make linux/spec2006 BENCH=astar_biglakes SPEC=/path/to/cpu2006 -jN
```

The build flow is:

1. Generate a build-local SPEC cfg copy under the case build directory.
2. Inject `output_root` into that cfg so SPEC build artifacts stay under this
   repository instead of modifying the original SPEC installation.
3. Run `runspec --action build`.
4. Export the built SPEC ELF, package the benchmark plus input files into the
   Linux rootfs, and produce:

```text
build/linux-workloads/spec2006/<case>/fw_payload.bin
```

## Build and export images

Export all selected cases to `build/images/spec2006`:

```sh
make spec2006-images SPEC=/path/to/cpu2006 -jN
```

By default, export builds only `ref` cases. Select another input set with
`SPEC2006_INPUT`; use `all` to export every configured case:

```sh
make spec2006-images SPEC=/path/to/cpu2006 SPEC2006_INPUT=test -jN
make spec2006-images SPEC=/path/to/cpu2006 SPEC2006_INPUT=all -jN
```

Selected SPEC cases are built one by one to avoid concurrent `runspec`
instances contending on shared temporary state inside the SPEC tool tree.

The export directory is organized as:

```text
build/images/spec2006/
  bin/<case>.fw_payload.bin
  kernel/<case>.Image
  elf/<case>.elf
  gcpt/gcpt.elf
  gcpt/gcpt.bin
  cfg/<spec-cfg-name>
```

`gcpt/` and `cfg/` are copied once per export tree, not once per case.

Override the destination with `SPEC2006_IMAGE_DIR=/path/to/image`.

## Build ELF only

Build one case without packaging it into the Linux rootfs:

```sh
make spec2006-elf BENCH=astar INPUT=biglakes SPEC=/path/to/cpu2006 -jN
```

This writes:

```text
build/linux-workloads/spec2006/<case>/elf/<case>.elf
```

Build every selected case as ELF only:

```sh
make spec2006-elfs SPEC=/path/to/cpu2006 SPEC2006_INPUT=ref -jN
make spec2006-elfs SPEC=/path/to/cpu2006 SPEC2006_INPUT=all -jN
```

If you only want the standalone ELF build flow, you can run it from this
directory without the top-level Makefile:

```sh
cd workloads/linux/spec2006
make -f rules.mk spec2006-elf BENCH=astar INPUT=biglakes SPEC=/path/to/cpu2006 -jN
make -f rules.mk spec2006-elfs SPEC=/path/to/cpu2006 SPEC2006_INPUT=all -jN
```

## Configuration

The default SPEC cfg is:

```text
workloads/linux/spec2006/riscv_gcc15_base.cfg
```

Override it with:

```sh
make linux/spec2006 BENCH=bzip2_source \
  SPEC=/path/to/cpu2006 \
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
the env vars expected by `riscv_gcc15_base.cfg`:

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

- The original SPEC tree is used read-only for sources and input data.
- Build logs, copied cfg files, build directories, and built executables are
  redirected into the case-local `runspec-output` directory via `output_root`.
- The source cfg in this repository is never passed to `runspec` directly;
  `runspec` is allowed to rewrite only the generated local cfg copy.
