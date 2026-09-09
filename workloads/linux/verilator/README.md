# Verilator Linux Workload

A nested RTL simulation as a guest benchmark: the workload is a Verilator model
of XiangShan, cross-compiled for riscv64, running as an ordinary Linux program
and simulating a bare-metal image.

Unlike the compute benchmarks in this repository, the interesting property here
is the *host* side of the simulation. Verilator emits enormous straight-line
evaluation functions with an instruction working set far beyond any cache, so
this workload stresses the frontend — fetch, branch prediction, instruction
cache and TLB — rather than the memory hierarchy.

## Inputs

The model is not built here. It is produced outside workload-builder and passed
in by path, in the same spirit as the SPEC suites taking an ISO path.

| Variable | Meaning |
|----------|---------|
| `VERILATOR_GUEST_EMU` | riscv64 `emu` binary (required) |
| `VERILATOR_GUEST_IMAGE` | bare-metal image the nested simulation runs (required) |
| `VERILATOR_MAX_CYCLES` | simulated cycles before the model stops (default `50000`) |
| `VERILATOR_RAM_SIZE` | simulated DRAM size (default `8GB`) |

```sh
make linux/verilator \
  DEFAULT_DTB=xiangshan-fpga-noAIA-mem8g-novec \
  VERILATOR_GUEST_EMU=/path/to/emu-riscv64 \
  VERILATOR_GUEST_IMAGE=/path/to/payload.bin \
  VERILATOR_MAX_CYCLES=1000000 -jN
```

`DEFAULT_DTB` is not optional. The default `xiangshan` device tree declares
128 MiB of DRAM; the guest needs a few GiB for the model binary, the unpacked
initramfs and the model's own heap.

If a `<emu>.meta` file sits beside `VERILATOR_GUEST_EMU`, it is copied to
`/verilator/emu.meta` so the image records which design revision it simulates.

## How the model is launched

`/etc/inittab` runs the model through `nemu-exec`, which disables the timer
interrupt, enters SimPoint profiling mode, and traps NEMU with the exit status:

```
nemu-exec /usr/bin/emu -i /verilator/workload.bin --no-diff --ram-size=<size> -C <cycles>
```

`--ram-size` must be given explicitly. A model built for XiangShan defaults to
an 8 TB sparse mapping for simulated DRAM, which no guest page-table layout can
satisfy.

`--no-diff` runs without a reference model. With no reference there is no trap
detection either, so the run is bounded by `-C` rather than by the nested
payload finishing — see below.

## Choosing the cycle cap

`VERILATOR_MAX_CYCLES` sets the total length of the workload. Guest instructions
per simulated cycle cannot be predicted usefully, so measure it: run the image
under NEMU at two small caps, read the retired-instruction counts, and fit. The
slope is instructions per simulated cycle and the intercept absorbs Linux boot
plus model construction.

For a `KunminghuV2Config` model built at `-O3`, simulating bare-metal CoreMark:

```text
guest instructions = 1.71e9 + 3.72e6 x simulated_cycles
```

so `VERILATOR_MAX_CYCLES=50000` is about 188 G instructions. The nested payload
starts printing before cycle 10 000.

Whether the nested payload reaches its own steady state matters less than it
might seem. Reset, boot and payload startup all execute the same verilated code,
which is the property being characterised.

## Files

- `build.sh` — stages the model, the payload and the generated `inittab`.
- `inittab.in` — launch template; `@MAX_CYCLES@` and `@RAM_SIZE@` are substituted
  at build time so the resulting image is self-contained.
