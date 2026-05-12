# SPEC CPU2017 Linux workload

This workload prepares a writable SPEC workspace from `SPEC2017_ISO` first,
then builds cases against that local install.

Prepare the workspace:

```sh
make spec2017-prepare SPEC2017_ISO=/path/to/cpu2017.iso
```

Build one SPEC CPU2017 case:

```sh
make linux/spec2017 BENCH=mcf MODE=rate INPUT=ref SPEC2017_ISO=/path/to/cpu2017.iso -jN
make linux/spec2017 BENCH=mcf MODE=speed INPUT=ref SPEC2017_ISO=/path/to/cpu2017.iso -jN
```

`MODE=rate` selects `_r` benchmarks and maps `INPUT=ref` to `refrate`.
`MODE=speed` selects `_s` benchmarks and maps `INPUT=ref` to `refspeed`.
Full case names are also accepted:

```sh
make linux/spec2017 BENCH=mcf_rate_refrate SPEC2017_ISO=/path/to/cpu2017.iso -jN
```

The ISO is extracted and installed through a temporary local staging directory,
then copied into the writable workspace
`build/linux-workloads/spec2017/spec-src`. Build output stays under:

```text
build/linux-workloads/spec2017/
```

Build ELF only:

```sh
make spec2017-elf BENCH=mcf MODE=rate INPUT=ref SPEC2017_ISO=/path/to/cpu2017.iso -jN
make spec2017-elf BENCH=mcf MODE=speed INPUT=ref SPEC2017_ISO=/path/to/cpu2017.iso -jN
make spec2017-elfs MODE=all INPUT=ref SPEC2017_ISO=/path/to/cpu2017.iso -jN
```

ELF output is written to:

```text
build/linux-workloads/spec2017/<case>/elf/<case>.elf
```

Export reference rate images. `MODE=rate` is the default:

```sh
make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso -jN
```

Export reference speed images:

```sh
make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso MODE=speed -jN
```

By default, rate images are exported under `build/images/spec2017rate/` and
speed images under `build/images/spec2017speed/`. `SPEC2017_IMAGE_MODE=all`
keeps the combined export under `build/images/spec2017/`.

The export tree is:

```text
build/images/<mode>/
  bin/<variant>.fw_payload.bin
  kernel/<variant>.Image
  elf/<case>.elf
  cmd/<variant>.run.sh
  rootfs/<variant>.rootfs.cpio
  gcpt/gcpt.elf
  gcpt/gcpt.bin
  cfg/riscv-gcc15.cfg
```

`<mode>` is `spec2017rate` for rate and `spec2017speed` for speed.

When SPEC generates multiple run commands for a case, `spec2017-images` exports
one firmware image, one rootfs, and one `cmd/<variant>.run.sh` per command,
plus one shared ELF for the base case. Variants are named with the base case,
command index, and output label, for example:

```text
perlbench_rate_refrate_00_checkspam.2500.5.25.11.150.1.1.1.1.fw_payload.bin
```

Useful selectors:

```sh
make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso SPEC2017_IMAGE_INPUT=test -jN
make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso SPEC2017_IMAGE_INPUT=all -jN
make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso SPEC2017_IMAGE_MODE=rate -jN
make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso SPEC2017_IMAGE_MODE=all -jN
```

`SPEC2017_IMAGE_MODE=all` exports both rate and speed images.

The generated run script emits NEMU profiling traps by default:

```text
echo "CMD: ..."
nemu-trap 256
nemu-trap 257
<benchmark command>
nemu-trap <status>
```

Disable the begin profiling traps with:

```sh
PROFILING=0 make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso -jN
```

The final `nemu-trap <status>` is always emitted.

The repository provides static `xiangshan-fpga-noAIA` DTS templates for the
SPEC2017 memory profiles used by default. The embedded DTB is selected per
case:

```text
rate  -> 8g
speed -> 24g
```

SPEC CPU2017 documents 16 GiB as the minimum system memory for SPECspeed, while
SPECrate only needs 2 GiB per 64-bit copy. This workload also stores benchmark
inputs in initramfs; the largest ref rate input currently needs more than 4 GiB
to unpack and start cleanly, so the default keeps extra headroom for rate too.
Override the selected profile with the available DTS profiles:

```sh
make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso SPEC2017_DTB_MEMORY=8g -jN
make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso SPEC2017_RATE_DTB_MEMORY=8g SPEC2017_SPEED_DTB_MEMORY=24g -jN
```

Alternatively, pass a specific DTB basename with `DEFAULT_DTB`. In that mode the
profile suffix is not added automatically, and the firmware script checks that
the selected DTS memory is large enough for the case:

```sh
make linux/spec2017 BENCH=x264 MODE=rate INPUT=ref \
  DEFAULT_DTB=xiangshan-fpga-noAIA-mem8g \
  SPEC2017_ISO=/path/to/cpu2017.iso -jN
make linux/spec2017 BENCH=x264 MODE=speed INPUT=ref \
  DEFAULT_DTB=xiangshan-fpga-noAIA-mem24g \
  SPEC2017_ISO=/path/to/cpu2017.iso -jN
```

The minimum checked size is 8 GiB for rate cases and 24 GiB for speed cases.

The source templates live in:

```text
dts/xiangshan-fpga-noAIA-mem8g.dts.in
dts/xiangshan-fpga-noAIA-mem24g.dts.in
```

They are compiled into each case's `dt/` directory during firmware assembly.

## Configuration

By default, rate cases use:

```text
workloads/linux/spec2017/riscv-gcc15.cfg
```

Speed cases use:

```text
workloads/linux/spec2017/riscv-gcc15.cfg
```

Override both modes with `SPEC2017_CFG=/path/to/config.cfg`, or override the
mode-specific defaults with `SPEC2017_RATE_CFG` and `SPEC2017_SPEED_CFG`.

`spec2017-prepare` only checks `SPEC2017_ISO` and prepares the local workspace;
it does not depend on benchmark cfg selection. Installation staging uses a
temporary local filesystem; override `SPEC2017_PREPARE_TMPDIR` if `/tmp` is not
suitable. `xorriso` is required for this step.
