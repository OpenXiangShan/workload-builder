# stress-ng Linux workload

This workload statically cross-compiles stress-ng 0.22.00 with the Buildroot
RISC-V toolchain and packages it in a Linux firmware image. `DEFAULT_DTB`
selects the embedded device tree.

The default run starts one worker for every stressor supported by the guest and
runs each stressor for a fixed bogo-op budget. The default command policy is:

```text
STRESS_NG_OPS=1
STRESS_NG_ARGS='--oom-avoid --skip-silent --metrics-brief'
STRESS_NG_VM_BYTES=16M
STRESS_NG_CYCLIC_POLICY=rr
```

Unsupported stressors, stressors whose optional dependencies are not linked,
and pathological stressors are skipped by stress-ng. The runner uses the real
`--all 1` parallel mode and automatically attaches `--STRESSOR-ops 1` to every
known stressor. `STRESS_NG_VM_BYTES=16M` bounds the VM worker in the 128 MiB
guest, and `STRESS_NG_CYCLIC_POLICY=rr` avoids the deadline scheduling policy
on guests that do not support it. Exit codes for unavailable resources or
unsupported stressors are treated as expected skips.

The bogo-op budget is intentionally approximate: stress-ng has no global ops
option and different stressors perform very different amounts of work per
operation. The minimum full pass (`STRESS_NG_OPS=1`) is selected because some
single bogo-ops contain large internal batches. The default is estimated to run
for roughly two to three hours at 100 million guest instructions per second.
Three hours is approximately 1.08 trillion instructions. Actual runtime varies
with guest support and simulator performance.

The workload keeps the guest timer enabled for stress-ng worker scheduling,
and sends the completion status from `run.sh`. Set `PROFILING=1` to emit
`nemu-trap 257` before stress-ng starts:

```sh
PROFILING=1 make linux/stress-ng
```

The arguments can be changed at build time with `STRESS_NG_ARGS`, for example:

```sh
make linux/stress-ng \
  STRESS_NG_OPS=2
```

For a quick subset while calibrating, use `STRESS_NG_STRESSORS`:

```sh
make linux/stress-ng \
  STRESS_NG_STRESSORS='cpu vm io' STRESS_NG_OPS=1
```

`stress-ng --help` lists all options. `STRESS_NG_ARGS` accepts additional
global options. The runner passes `--timeout 0` to disable stress-ng's implicit
one-day limit; completion is controlled by the per-stressor operation counts.

Build the image with:

```sh
make linux/stress-ng -jN
```

To embed another supported device tree, pass its template basename:

```sh
make linux/stress-ng DEFAULT_DTB=xiangshan-fpga-noAIA-novec -jN
```
