# Geekbench 6

This workload packages the Geekbench 6.7.0 Linux/RISC-V Preview binaries into a
Linux initramfs workload.

Build the all-in-one NEMU firmware image:

```shell
make linux/geekbench6
```

The resulting firmware is written to `build/linux-workloads/geekbench6/` as
`fw_payload.bin`, with the unpacked initramfs in `rootfs.cpio` and generated
device trees in `dt/`.

This workload uses `dts/xiangshan-fpga-noAIA.dts.in` as its built-in default
device tree so the large Geekbench initramfs stays inside Linux-visible memory.

The automated boot path runs `./geekbench_riscv64 --cpu --iterations 1` so the
simulator validation can reach a good trap in reasonable time. The default DTB
describes one hart, so the Preview CPU run is single-core in this workload.

Set `GEEKBENCH_ARGS='...'` at build time to change the Geekbench CLI. The
default is `--cpu --iterations 1`:

```shell
GEEKBENCH_ARGS='--sysinfo' make linux/geekbench6
```

The boot script calls `nemu-trap 0` after the Geekbench process returns. This is
intentional: the Preview binary may return a non-zero status when it cannot
upload results, but reaching this point still means the benchmark path
completed. The generated inittab also appends `nemu-trap -1` after
`/geekbench/run.sh` as a fallback for cases where the run script exits before
issuing its own trap.

By default, no trap is emitted before the workload starts. Build with
`PROFILING=1` to emit `nemu-trap 256` and `nemu-trap 257` from inittab before
the benchmark starts:

```shell
PROFILING=1 make linux/geekbench6
```

If you have a Pro-capable Geekbench binary, you can add `--single-core` or
`--multi-core` in `GEEKBENCH_ARGS`. The Preview binaries in this repo reject
both switches as Pro-only.

The tarball also includes `geekbench_rv64gcv`; it is installed in the image for
manual use, while the automatic boot path runs the scalar `geekbench_riscv64`
binary for broader simulator compatibility.

The Geekbench Preview binary exposes only the full CPU benchmark and sysinfo
commands. Individual workload switches are present in the binary but require
Geekbench Pro, so this workload builds the runnable CPU benchmark image.
