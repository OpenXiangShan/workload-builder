# SPEC CPU2026 Linux Workload

This workload prepares a writable SPEC workspace from `SPEC2026_ISO` first,
then builds cases against that local install.

Prepare the workspace:

```sh
make spec2026-prepare SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso
```

Build one case:

```sh
make linux/spec2026 BENCH=706.stockfish_r SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN
```

Export images:

```sh
make spec2026-images SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN
```

Default image export mode is `rate`. Use `MODE=speed` or `MODE=all` to
change the selected cases. `SPEC2026_IMAGE_MODE` and `SPEC2026_IMAGE_INPUT`
can be used independently from the single-case build selectors.

By default, rate images are exported under `build/images/spec2026rate/` and
speed images under `build/images/spec2026speed/`. `SPEC2026_IMAGE_MODE=all`
keeps the combined export under `build/images/spec2026/`.

The export tree is:

```text
build/images/spec2026rate/
  bin/<case>.fw_payload.bin
  kernel/<case>.Image
  rootfs/<case>.rootfs.cpio
  elf/<case>.elf
  cmd/<case>.run.sh
  gcpt/gcpt.elf
  gcpt/gcpt.bin
  cfg/<cfg>.cfg
  logs/build_elf/<case>.log
  stamps/<case>.images.stamp

build/images/spec2026speed/
  bin/<case>.fw_payload.bin
  kernel/<case>.Image
  rootfs/<case>.rootfs.cpio
  elf/<case>.elf
  cmd/<case>.run.sh
  gcpt/gcpt.elf
  gcpt/gcpt.bin
  cfg/<cfg>.cfg
  logs/build_elf/<case>.log
  stamps/<case>.images.stamp
```

Useful selectors:

```sh
make spec2026-images BENCH=706.stockfish_r SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN
make spec2026-images BENCH=800.pot3d_s MODE=speed SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN
make spec2026-images SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso SPEC2026_IMAGE_INPUT=test -jN
make spec2026-images SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso SPEC2026_IMAGE_INPUT=all -jN
make spec2026-images SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso SPEC2026_IMAGE_MODE=rate -jN
make spec2026-images SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso SPEC2026_IMAGE_MODE=all -jN
```

`SPEC2026_IMAGE_MODE=all` exports both rate and speed images into the same
combined tree that `SPEC2026_IMAGE_DIR` points to.

The repository provides static `xiangshan-fpga-noAIA-novec` DTS templates for
the SPEC2026 memory profiles used by default. The embedded DTB is selected per
case:

```text
rate  -> 8g
speed -> 64g
```

Override the selected profile with the available DTS profiles:

```sh
make spec2026-images SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso SPEC2026_DTB_MEMORY=8g -jN
make spec2026-images SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso SPEC2026_RATE_DTB_MEMORY=8g SPEC2026_SPEED_DTB_MEMORY=64g -jN
```

Alternatively, pass a specific DTB basename with `DEFAULT_DTB`. In that mode
the profile suffix is not added automatically, and the firmware script checks
that the selected DTS memory is large enough for the case:

```sh
make linux/spec2026 BENCH=706.stockfish_r MODE=rate \
  DEFAULT_DTB=xiangshan-fpga-noAIA-mem8g-novec \
  SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN
make linux/spec2026 BENCH=800.pot3d_s MODE=speed \
  DEFAULT_DTB=xiangshan-fpga-noAIA-mem64g-novec \
  SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN
```

The minimum checked size is 8 GiB for rate cases and 64 GiB for speed cases.

The source templates live in:

```text
dts/xiangshan-fpga-noAIA-mem8g-novec.dts.in
dts/xiangshan-fpga-noAIA-mem64g-novec.dts.in
```

Re-running `make spec2026-images` rebuilds the export tree so the directory
layout and contents stay complete and consistent.
