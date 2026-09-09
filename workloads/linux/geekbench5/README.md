# Geekbench 5

This workload packages the Geekbench 5.5.1 Linux/RISC-V Preview binaries into a
Linux initramfs workload.

The default image keeps the Preview binary's normal upload flow and enables an
offline runtime takeover around it. It patches only the embedded upload URL
scheme (without changing ELF offsets), and redirects all name resolution and
socket traffic to an in-process local transport. No kernel source, network
device, or listener is needed, and all benchmark computation remains in the
downloaded ELF.

Build the all-in-one NEMU firmware image:

```shell
make linux/geekbench5
```

The resulting firmware is written to `build/linux-workloads/geekbench5/` as
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
GEEKBENCH_ARGS='--sysinfo' make linux/geekbench5
```

The in-process transport receives the normal upload request, extracts the
calculated `score` and `multicore_score` values, and prints them without
contacting the Browser. The complete captured upload request is printed before
the score summary.
The capture buffer grows with each request and honors that request's own
`Content-Length`; chunked or close-delimited uploads are also captured in full.
After a complete scored upload is printed and parsed, the preload shim finishes
the Preview process so it cannot wait for a real Browser response.
The boot script calls `nemu-trap 0` after the Geekbench process returns. This is
intentional: the shim finishes the Preview process after a complete scored
upload has been printed, and the generated inittab also appends `nemu-trap -1` after
`/geekbench/run.sh` as a fallback for cases where the run script exits before
issuing its own trap.

By default, no trap is emitted before the workload starts. Build with
`PROFILING=1` to emit `nemu-trap 257` from inittab before the benchmark starts:

```shell
PROFILING=1 make linux/geekbench5
```

If you have a Pro-capable Geekbench binary, you can add `--single-core` or
`--multi-core` in `GEEKBENCH_ARGS`. The Preview binaries in this repo reject
both switches as Pro-only.

The Geekbench Preview binary exposes only the full CPU benchmark and sysinfo
commands. Individual workload switches are present in the binary but require
Geekbench Pro, so this workload builds the runnable CPU benchmark image.

The workload always enables the takeover; there is no network-enabled mode in
the generated image.
