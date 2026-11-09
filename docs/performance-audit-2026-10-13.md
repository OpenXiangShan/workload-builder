# 香山 SPEC 性能优化检查（2026-10-13）

THP 经用户测试后已排除。下面保留检查时的配置快照与其余实验建议。

目标是香山执行 SPEC 的性能。此次检查覆盖配置、实际 SPEC2006 产物、编译器能力、内核 Kconfig 和运行脚本；没有进行香山性能 A/B 测量，因此下面的优先级表示实验价值，不表示已经取得加速。

检查基于当前工作区，包括尚未提交的 SPEC2026 LMUL 配置。实际产物集中在 `build/images/spec2006`，55 个 case 的导出内核配置相同，并与当前内核 `.config` 一致。SPEC2017/2026 的结论来自仓库配置，未验证其实际构建或运行产物。

**当前基线**

| 项目 | 核对结果 | 含义 |
| --- | --- | --- |
| SPEC2006 | GCC 16.1.0（g6afcc4f6d）；默认 RVA23 标量 cfg | 实际日志包含 `-O3 -flto -ffast-math -fno-strict-aliasing`，静态链接 jemalloc；povray 有去掉 fast-math 的例外 |
| SPEC2006 向量化 | 实际产物含 `-fno-tree-vectorize -fno-tree-loop-vectorize`，DTB 为 `xiangshan-fpga-noAIA-novec` | 内核支持 RVV，不等于当前程序已使用 RVV |
| SPEC2017 | cfg 已有 O3、LTO、fast-math、静态链接和 jemalloc | 默认 cfg 关闭自动向量化，另有 LMUL 1/2/4/8 向量配置；运行脚本固定 `OMP_NUM_THREADS=1` 和 `OMP_THREAD_LIMIT=1` |
| SPEC2026 | cfg 的共同基线是 `-g -O3`；有 novec 和 LMUL 1/2/4/8 版本 | 当前 cfg **没有** `-flto`、`-ffast-math` 或 `-static`；静态加入 `libjemalloc.a` 不代表整个程序静态链接 |
| 内核 | Linux 7.1.13；Buildroot 工具链 GCC 15.1.0 | 与 SPEC 程序的 GCC 16 是两套工具链 |
| 内核优化 | `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y`，实际命令为 `-O2` | 已按性能模式编译；此版本没有 `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3` 选项 |
| 内核内存 | 4 KiB 页；HugeTLB 已开启；THP 关闭 | 普通 malloc/mmap 不会因开启 HugeTLB 而自动获得大页 |
| 内核调度 | `PREEMPT_LAZY`、`NO_HZ_IDLE`、HZ=250；NO_HZ_FULL 关闭 | tickless idle 不等于运行中无周期 tick |
| RVV/ISA | 内核 RVV、Zba/Zbb、Zicboz 等支持已开启；FPGA DTB 宣告 Sstc | 这些已有支持，不需要重复开启；实际使用仍受硬件和所选 DTB 限制 |

SPEC2026 的 [LMUL4 cfg](../workloads/linux/spec2026/configs/riscv_gcc16_rva23u64_lmul4.cfg) 和 [novec cfg](../workloads/linux/spec2026/configs/riscv_gcc16_rva23u64_novec.cfg) 当前未启用 `-static -ffast-math -flto -fno-strict-aliasing`。应先以实际编译、链接命令建立基线，再选择是否启用这些选项。

**值得开展的工作，按优先级排序**

| 优先级 | 工作 | 建议实验 | 首先观察 |
| --- | --- | --- | --- |
| 高 | 透明大页 THP | 4 KiB 基线，对比 THP always；分配器支持明确请求时再试 madvise | AnonHugePages、DTLB miss、page walk、RSS |
| 高，依程序而定 | RVV 自动向量化和 LMUL | 同一 GCC 下，novec 对比 LMUL1/2/4/8 | cycles、向量化报告、实际 RVV 指令、寄存器 spill |
| 高，限 SPEC2026 | 补充 LTO 实验 | 先单独加 `-flto`；再分别评估 fast-math、静态链接 | 最终链接命令、结果正确性、cycles |
| 中 | jemalloc 参数和构建 | 基线对比关闭统计；单线程试 narenas=1，分别试 THP 和 decay | malloc 热点、RSS、系统调用、cycles |
| 中，限多线程 | 线程数、绑核与 OpenMP 等待策略 | 按实际 hart 数配置线程，并单独比较 active/passive 等待 | 吞吐、CPU 利用率、上下文切换、锁竞争 |
| 低或有条件 | HZ=100、NO_HZ_FULL、内核裁剪 | 仅在真实 timer 中断或内核占比明显时测试 | 中断数、内核 cycles、调度开销 |

**THP 是当前内核最明确的性能候选**

当前仅有 `CONFIG_HUGETLBFS=y`，缺少 `CONFIG_TRANSPARENT_HUGEPAGE`。优先选择 mcf、omnetpp、xalancbmk、lbm 等代表程序，确认 TLB/page-walk 是否构成瓶颈。

已经通过该版本 Kconfig 解析的最小片段是：

```text
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y
```

在 Buildroot 的独立实验输出目录中，将片段加入 `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` 后重新构建内核和固件。需要修改运行策略时，在 guest 挂载 sysfs 后、启动 benchmark 前设置：

```sh
echo always > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
```

`defrag=never` 限制分配路径的直接整理开销，不保证一定分配到大页，也不关闭所有后台合并活动。记录进程 `/proc/<pid>/smaps` 的 `AnonHugePages` 以及 `/proc/vmstat` 的 THP 计数，确认大页真的进入测量区间。

当前 jemalloc 的 `malloc` 符号已经进入 mcf ELF，构建开启了 `JEMALLOC_STATS`，关闭了 debug 和 allocator profiling。新版本源码用 `JEMALLOC_HAVE_MADVISE_HUGE` 控制大页能力；当前该宏已开启，不能用遗留的 `JEMALLOC_THP` 宏未定义来认定 allocator 不支持 THP。

可单独尝试 `MALLOC_CONF=thp:always`；若采用内核 madvise 模式，需确认 allocator 确实发送了大页请求。`metadata_thp:auto` 是分配器元数据的另一项实验，不等于整个应用堆均使用大页。`hugepages=N` 只预留显式 HugeTLB 页，还需要应用或分配器主动使用，并会占用普通内存。

**RVV 配置已具备，但需要搭配正确的 DTB 和测量**

SPEC2006 已有 GCC15/16 的 LMUL1/2/4/8 cfg。切换 vector cfg 时，必须显式选择包含 V 的 DTB；其默认 DTB 仍是 novec。例如：

```sh
make linux/spec2006 BENCH=lbm SPEC2006_ISO=/path/to/cpu2006.iso \
  SPEC2006_CFG=workloads/linux/spec2006/configs/gcc16-linux-riscv64-rva23u64_lmul2.cfg \
  DEFAULT_DTB=xiangshan-fpga-noAIA
```

SPEC2026 根据 cfg 文件名的 `_lmul1.cfg` / `_lmul2.cfg` / `_lmul4.cfg` / `_lmul8.cfg` 后缀选 vector DTB。自定义 cfg 即使使用 RVV，若不符合命名规则，也应显式指定 vector `DEFAULT_DTB`。

GCC16 最小编译探针已确认四种 LMUL 都能生成 `vle32.v`、`vfadd.vv`、`vse32.v` 和相应的 `vsetvli`。现有 cfg 的 `-mrvv-vector-bits=zvl` 与 `zvl128b` 得到 `__riscv_v_fixed_vlen=128`；旁边香山源码的默认 VLEN 也是 128。实际运行必须以所实例化硬件/仿真配置为准。`mrvv-max-lmul` 是上限，真实 benchmark 未必使用该 LMUL；LMUL8 也可能增加寄存器压力而退化。

建议开启 `-fopt-info-vec-optimized -fopt-info-vec-missed`，并检查最终反汇编。SPEC2017 已有 GCC15/16 的 LMUL1/2/4/8 cfg，选择时同样会默认使用 vector DTB。不能用 NEMU/QEMU 的 host 耗时判断 RVV 在香山上的加速。

**SPEC2026 编译和线程配置需要单独补齐实验**

先在当前 `OPTIMIZE` 中只加 `-flto`，核对链接阶段也带有 LTO，再单独比较 fast-math。保留现有 `-fno-fast-math` 和 `-fno-finite-math-only` 等 benchmark portability；fast-math 可能改变数值结果。`-fno-strict-aliasing` 放宽别名假设，一般是兼容性选择，不能将它作为必然提速的开关。

静态链接可以作为单独实验，但动态链接不代表必然较慢。`-g` 通常不改变热路径执行速度，删除 debug 信息主要影响文件大小和调试能力。现有 `basepeak=yes` 也意味着只切换到 peak 不会自动得到另一套优化。

SPEC2026 cfg 中 `threads=4`，DO CONCURRENT 使用 `-ftree-parallelize-loops=8`；当前固件路径按单 hart 装配，尚无完整的 SPEC2026 多 hart workload 流程。speed 程序应核对实际 `doit.sh`、程序参数和 guest 环境中的线程数，避免单 hart 上运行多个计算线程。要测多核 speed，需先补齐 DTB、固件和启动流程。

SPEC2017 的固定单线程环境适合当前 rate/copy 用途；扩展 speed 时，需要另外开放线程参数。多 hart rate launcher 已使用 taskset，不应再把每个 copy 的 OpenMP 线程数改成全部 hart 数。

`OMP_PLACES=cores`、`OMP_PROC_BIND=close`、`OMP_WAIT_POLICY` 和 libgomp 的 `GOMP_SPINCOUNT` 可作为 speed 实验；active 会消耗空闲 CPU，passive 会增加唤醒开销，选择取决于 hart 数和并行区域长度。

**allocator 还有空间**

当前 jemalloc 编译已有 `-O3 -funroll-loops`。值得比较的是重建时 `--disable-stats`，以及单线程 `MALLOC_CONF=narenas:1,background_thread:false`。dirty/muzzy decay 的修改应与 RSS 一起评估，长时间保留脏页可能降低回收开销，也可能造成内存压力。`thp`、arena 和 decay 分别改变，便于解释收益。

当前 SPEC2006 的构建元数据没有 jemalloc 库内容 hash，也没有编译器内容/版本指纹；SPEC2017/2026 已记录 jemalloc 库 hash，但仍没有编译器版本指纹。在相同路径替换工具链或 allocator 后，需保证 Make 重新执行 helper 并真正重链，避免测到旧 ELF。后续可以将这两类指纹纳入 Make 依赖和缓存元数据。

**内核和计时参数中，哪些应后做**

当前 SPEC2006 默认 `PROFILING=1` 会发出 trap 256/257；SPEC2026 经 `nemu-exec` 也发出这两个 trap。旁边 NEMU 源码中 trap 256 会关闭 M/S/VS timer 中断。如果该状态保留到 checkpoint，测量区间已没有这些周期中断，改 HZ=100 的收益会很有限。真实 FPGA或保留 timer 的流程可以单独比较 HZ=100。

NO_HZ_FULL 已通过 Kconfig 解析，但需要至少一个 CPU 负责时钟维护，单 hart 不能把唯一 CPU 作为 full-dynticks CPU。多 hart 的 `nohz_full` / RCU offload 应与 housekeeping CPU 和 taskset 一起规划；当前 rate launcher 占用全部 hart，直接预留 CPU 会改变可运行的 copy 数和吞吐口径。

此 Linux 7.1.13 的 `PREEMPT_NONE` 依赖 `ARCH_NO_PREEMPT`，RISC-V 不满足。隔离试验中强行设置会被 Kconfig 丢弃，禁用 LAZY 后转而选择 `PREEMPT=y`。不要直接照搬 `CONFIG_PREEMPT_NONE=y`；当前动态 preemption 也未开启，不能依赖 `preempt=none` 启动参数完成切换。

内核实际已有 stack protector、栈变量自动清零、frame pointer 和 list hardening。关闭这些属于专用性能镜像的独立权衡，而且收益取决于内核执行占比；`FRAME_POINTER` 还由 RISC-V 的 `PERF_EVENTS` 选择，直接取消可能不生效。当前 ftrace、KASAN、SLUB_DEBUG_ON 等常见运行期开销并未开启。裁掉网络、KVM、显示和其他闲置驱动主要缩小镜像/启动工作量，不保证用户态计算热路径更快。

FPGA DTS 默认 `loglevel=8`，可在最终性能镜像中降低到 3，减少运行期日志；只影响实际打印的部分。Sstc 已在当前 FPGA profile 中宣告，QEMU profile 有意移除，不能仅为性能宣告目标未实现的扩展。

旁边 NEMU 当前 `CONFIG_CYCLES_PER_MTIME_TICK=128`，FPGA DTS 的 `timebase-frequency=1000000`。这不是“调快 RTC”的优化开关；若程序按 guest 时间执行，必须核对目标 CPU/RTC 比例，例如 3.003 GHz / 1 MHz 对应 3003。当前值是否符合特定运行流程需要结合启动命令确认。NEMU 的 cycle 计数按其执行模型生成，不能直接代替香山周期数。

**建议的第一轮实验**

先选 4～6 个代表程序，分别覆盖指针追踪/大工作集、分支和规则浮点循环。先建立默认基线，再做 vector LMUL 扫描；SPEC2026 另加单独 LTO 对照，之后再比较 allocator 参数。

每组保留独立的 `SPEC*_BUILD_DIR`、`SPEC*_IMAGE_DIR` 和 cfg；镜像导出目标会清理所选输出目录，不应把上一组产物覆盖。使用显式的同一工具链和 allocator 路径，保存最终 ELF、内核、DTB 和 cfg hash。

编译选项、RVV、内核或页策略改变后，应重新生成 checkpoint 和采样权重：旧 checkpoint 的指令地址、页表或程序进度不能用于公平比较新程序。记录总 cycles、retired instructions、IPC、branch miss、I/D-TLB miss、page walk、I-cache miss、RSS 和内核占比。采样运行应使用各自重新生成的权重计算结果；能运行完整 ref 时再复核整体趋势。

程序退出 0 / Hit GOOD TRAP 只是执行成功，不等于 SPEC 输出已经通过参考结果比较。每个候选应检查 test/train/ref 结果，数值、链接和线程参数变化尤其如此。

**此次完成的验证**

GCC16 编译探针验证了四种 LMUL，且向量汇编实际包含 RVV 指令。内核隔离配置验证了 THP、HZ=100、NO_HZ_FULL 可选，并验证了 PREEMPT_NONE 不可选；活动内核 `.config`、`auto.conf` 和 `autoconf.h` 的内容 hash 均保持一致。

探针结果、候选完整内核配置、最小 THP/HZ 片段和输入 hash 位于 `build/performance-audit-2026-10-13/`。这些是编译/配置能力验证，尚未完成候选内核构建、启动、SPEC 正确性验证和香山性能测量。
