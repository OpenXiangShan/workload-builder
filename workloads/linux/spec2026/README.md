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

Re-running `make spec2026-images` rebuilds the export tree so the directory
layout and contents stay complete and consistent.
