# GAPBS Linux Workloads

NEMU SimPoint checkpoint images for the
[GAP Benchmark Suite](https://github.com/sbeamer/gapbs). Each workload is one
`kernel × graph` pair: a static, single-threaded GAPBS kernel that loads a
pre-serialized reference graph and runs one or more trials. There are 18 cases —
the cartesian product of six kernels and three graphs.

| kernel | graph file    | arguments |
|--------|---------------|-----------|
| bfs    | `<graph>.sg`  | `-n <trials>` |
| sssp   | `<graph>.wsg` | `-d <delta> -n <trials>` (delta: road `50000`; twitter/web `2`) |
| pr     | `<graph>.sg`  | `-i 1000 -t 1e-4 -n 1` |
| cc     | `<graph>.sg`  | `-n 1` |
| bc     | `<graph>.sg`  | `-i 1 -n <trials>` |
| tc     | `<graph>U.sg` | `-n 1` |

Graphs: `road`, `twitter`, `web`. Cases are named `<kernel>_<graph>`
(e.g. `bfs_road`, `sssp_web`).

## Trials

`bfs`, `sssp`, and `bc` pick a new random source each trial, so more trials
sample more sources. Their trial count is sized per case (`num_trials` in
`gapbs-package.py`) so every such case runs for roughly the same time — cheap
cases get many trials, expensive ones get few:

| kernel | road | twitter | web |
|--------|-----:|--------:|----:|
| bfs    |   33 |      13 |   2 |
| sssp   |   39 |       2 |   1 |
| bc     |   26 |       2 |   1 |

`pr`, `cc`, and `tc` are source-independent — every trial is identical work, so
they stay at a single trial regardless. Raise or lower `TARGET_TRIAL_SECONDS`
to rebalance.

## Building

```sh
make gapbs-list                       # list the 18 case names
make linux/gapbs-bfs_road -jN         # build one case
make gapbs-images -jN                 # build all 18 images
```

Images are written to `build/images/gapbs/bin/<case>.fw_payload.bin`.

## Graphs

Kernels load a pre-serialized graph with `-f`, so graph construction is not
part of the profiled region. The serialized files are read from
`GAPBS_GRAPH_DIR`:

```sh
make gapbs-images GAPBS_GRAPH_DIR=/path/to/serialized -jN
```

Convert the reference graphs once with the GAPBS `converter` (in `source/`):
`.sg` is used by bfs/pr/cc/bc, `.wsg` (weighted) by sssp, and `U.sg`
(symmetrized) by tc.

## How large graphs are delivered (split + FIFO)

Each serialized graph is bundled inside the initramfs. The Linux `newc` cpio
format stores every file's size in a 32-bit field, so **no single file may be
4 GiB or larger**. The twitter and web graphs are 9.5–30 GB and cannot be
shipped as one file. They are delivered without modifying GAPBS:

1. **Build time** — a graph at or above 4 GiB is split into ordered
   sub-4-GiB parts (`split -d -b 3G`) under `/gapbs/parts/`. Smaller graphs
   (all `road` cases) are bundled whole.
2. **Run time** — the generated `run.sh` recreates the single stream GAPBS
   expects through a **named FIFO** that carries the real `.sg`/`.wsg`/`U.sg`
   suffix, streaming the parts into it in order and freeing each part as it is
   consumed:

   ```sh
   mkfifo /gapbs/<graph>
   ( for p in /gapbs/parts/<graph>.*; do cat "$p"; rm -f "$p"; done ) > /gapbs/<graph> &
   /usr/bin/<kernel> -f /gapbs/<graph> <args>
   ```

GAPBS reads the FIFO exactly as it would a real file. This works because its
serialized reader is strictly sequential — it reads the header, then each CSR
array front-to-back, with no seek — so a forward-only pipe suffices. The
suffix must ride on the FIFO *name* because GAPBS selects serialized mode from
the filename extension. The split and stitch live entirely in the build
packager and the generated `run.sh`; the GAPBS source is untouched.

## Memory and device tree

A graph of size *G* peaks at roughly *2 × G* during the initramfs boot-unpack:
the cpio image and the unpacked rootfs coexist before the kernel frees the
source. The largest weighted graphs (`web.wsg` 30 GB, `twitter.wsg` 23 GB)
therefore need more than 64 GiB of guest RAM and are built against the
`mem128g` device-tree profile; all other cases fit the default `mem64g`:

```sh
make linux/gapbs-sssp_web \
  GAPBS_DEFAULT_DTB=xiangshan-fpga-noAIA-mem128g-novec \
  GAPBS_DTB_MIN_MEMORY_BYTES=137438953472 -jN
```

NEMU must be built with `CONFIG_MSIZE` at least as large as the guest device
tree declares. Total initramfs beyond 4 GiB relies on the 64-bit
`linux,initrd-start/end` device-tree cells emitted by `build-firmware-linux.sh`.

## Files

- `gapbs-package.py` — lists cases; cross-compiles the kernel (static,
  `SERIAL=1`); stages or splits the graph; writes `run.sh` + `inittab`.
- `build.sh` — thin wrapper invoked per case by the build system.
- `rules.mk` — generates the per-case build and image targets.
- `source/` — the GAPBS submodule (kernels and `converter`).
