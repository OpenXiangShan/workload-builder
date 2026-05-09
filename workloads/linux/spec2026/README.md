# SPEC CPU2026 Linux Workload

Build one case:

```sh
make linux/spec2026 BENCH=706.stockfish_r SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN
```

Export images:

```sh
make spec2026-images SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN
```

Default image export mode is `rate`. Use `MODE=speed` or `MODE=all` to
change the selected cases.

Output goes to `build/images/spec2026`.
Rate cases are written to `build/images/spec2026rate`; speed cases are written
to `build/images/spec2026speed`.

The export tree now includes:

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

Re-running `make spec2026-images` skips completed cases and resumes an
interrupted case build through `build/linux-workloads/spec2026/_bench-builds`.
