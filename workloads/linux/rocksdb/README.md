# RocksDB Linux Workloads

This workload packages RocksDB `v10.7.5`'s static `db_bench` and runs the
database workloads that are useful for XiangShan memory-system studies:

`readwhilewriting`, `readrandomwriterandom`, `updaterandom`,
`seekrandomwhilewriting`, `randomtransaction`, `timeseries`, and `mixgraph`.

The source and gflags dependency are pinned in `links.txt`. The build uses the
local or explicitly selected `riscv64-unknown-linux-gnu` RISC-V Linux toolchain,
disables optional compression libraries, and verifies that the resulting
`db_bench` is a fully static RVA23U64 executable. The build explicitly enables
GCC's `-O3` loop/SLP auto-vectorization and checks a probe for generated RVV
instructions. The database is created under `/tmp/rocksdb` at runtime and is
removed after each case, so no database files are embedded in the initramfs.

When profiling is enabled, its NEMU marker is emitted after any `fillrandom`
preparation and immediately before the selected benchmark. Timer interrupts
stay enabled so single-hart Linux can schedule RocksDB's foreground and
background threads.
`mixgraph` uses an 83% Get, 14% Put, and 3% Seek mix. `timeseries` uses its
compaction filter to discard entries outside the configured timestamp window,
keeping long runs from growing the in-memory filesystem without bound.

`randomtransaction-set-name.patch` fixes an upstream release-build issue in
the benchmark helper: `Transaction::SetName()` was called only inside an
`assert`, so it disappeared under `NDEBUG` and later `Prepare()` calls failed.

## Build

```sh
make rocksdb-list
make ROCKSDB_CROSS_COMPILE=/path/to/riscv64-unknown-linux-gnu- \
  linux/rocksdb-readwhilewriting -j$(nproc)
make ROCKSDB_CROSS_COMPILE=/path/to/riscv64-unknown-linux-gnu- \
  linux/rocksdb -j$(nproc)       # all seven cases
make ROCKSDB_CROSS_COMPILE=/path/to/riscv64-unknown-linux-gnu- \
  rocksdb-images -j$(nproc)      # export all images
```

The selected GNU/Linux toolchain must support `-march=rva23u64`; it is separate
from Buildroot's kernel/rootfs toolchain. If its binaries are already in
`PATH`, the default prefix `riscv64-unknown-linux-gnu-` is sufficient.

Each NEMU firmware image is written to
`build/linux-workloads/rocksdb/<case>/fw_payload.bin`. Exported images use the
same case names under `build/images/rocksdb/bin/`. All cases share one compiled
`db_bench`; their rootfs images only differ in `/etc/default/rocksdb`. The
default `xiangshan-fpga-noAIA` DTB provides 2 GiB of memory; override it with
`DEFAULT_DTB=<basename>` when targeting another compatible machine.

## Runtime controls

Each case image runs its named case. The common `run.sh` can also run a custom
comma-separated subset. These environment variables are read inside the guest:

| variable | default | meaning |
|---|---:|---|
| `ROCKSDB_KEYS` | `1000000` | key-space size |
| `ROCKSDB_OPS` | case-calibrated | reads/writes/transactions per case; see below |
| `ROCKSDB_THREADS` | `1` | reader/worker threads (`timeseries` uses 2) |
| `ROCKSDB_VALUE_SIZE` | `100` | fixed value size in bytes |
| `ROCKSDB_PROFILING` | `1` | emit `nemu-trap 257` before each selected workload (`0` disables it) |
| `ROCKSDB_CASES` | all seven | comma-separated case subset |
| `ROCKSDB_DB` | `/tmp/rocksdb` | database parent directory |

For an NEMU smoke test, use a small operation count and a guest instruction
budget, for example `-I 10000000`, with `ROCKSDB_OPS=1000` and
`ROCKSDB_KEYS=1000`. A fixed NEMU `-I` budget keeps comparisons between cases at
an exact common length; natural completion is bounded by `ROCKSDB_OPS`.

Profiling is enabled by default. The run script emits `nemu-trap 257` after any
database preparation and immediately before the selected benchmark; this is the
marker NEMU uses to begin workload-only instruction profiling. To omit this
begin marker, use the same top-level switch as the other Linux workloads:

```sh
PROFILING=0 make linux/rocksdb
PROFILING=0 make rocksdb-images
```

`ROCKSDB_PROFILING=0` is an equivalent workload-specific spelling. The final
`nemu-trap` that terminates the guest is always retained.

## NEMU instruction-category pressure

The following calibration used `ROCKSDB_KEYS=10000` with both 1,000 and 10,000
operations on NEMU's `riscv64-xs_defconfig`, with
`CONFIG_INSTR_CNT_BY_CATEGORY=y` enabled for measurement. Counters were reset
at the profiling marker after database preparation. The default operation
counts are fitted from the marginal instruction cost between those two points,
then given 5% headroom over `1e12` profiled instructions. The fitted target is
about 10,500 seconds at 100 million retired instructions per second. For a
100 MHz core, that time conversion assumes one retired instruction per cycle;
actual time depends on IPC.

| case | 1k-op instructions | 10k-op instructions | default ops | load + store | vector |
|---|---:|---:|---:|---:|---:|
| `readwhilewriting` | 72,881,050 | 221,830,687 | 63,440,860 | 39.561% | 5.026% |
| `readrandomwriterandom` | 64,945,523 | 152,808,692 | 107,547,946 | 39.448% | 4.754% |
| `updaterandom` | 73,661,954 | 217,846,055 | 65,537,609 | 39.576% | 5.100% |
| `seekrandomwhilewriting` | 77,840,365 | 300,104,781 | 42,514,775 | 39.852% | 4.735% |
| `randomtransaction` | 209,527,942 | 1,215,197,841 | 9,395,846 | 36.336% | 6.556% |
| `timeseries` | 90,551,592 | 243,730,605 | 61,688,204 | 37.865% | 4.633% |
| `mixgraph` | 66,301,710 | 164,868,787 | 95,868,744 | 39.671% | 4.599% |

These are empirical estimates; database state and compaction behavior can make
long runs non-linear. NEMU's scalar `load` and `store` categories exclude RVV
loads/stores, which are counted in the separate `vector` category. Thus the
table reports scalar load+store pressure and RVV instruction pressure as two
separate percentages. `seekrandomwhilewriting` has the largest scalar
load/store share, followed by `mixgraph`. `randomtransaction` has the largest
RVV share and vector-instruction count. A literal 100,000 yi (`100000`
hundred-million) instructions is `1e13`, not `1e12`; use ten times the listed
operation count for that target.
