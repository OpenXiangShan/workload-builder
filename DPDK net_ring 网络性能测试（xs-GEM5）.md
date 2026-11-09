位置：`/nfs/home/share/hushunchao/performance-test-for-infra-team/network/`

内容：`dts/`、`firmware/`、`checkpoint/`、`patches/`、`results/`

---

## 1. DPDK 测试
`rootfs` 里的 `run.sh` 实际执行：

```shell
{
    echo "set fwd io"
    echo "start tx_first"
    sleep 1
    echo "show port stats all"
    echo "stop"
    echo "quit"
} | /usr/bin/dpdk-testpmd --lcores='(0-1)@0' -n 1 --no-pci --no-huge \
    --vdev=net_ring0 --vdev=net_ring1 -- \
    --nb-cores=1 --port-topology=loop --total-num-mbufs=2048 \
    --rxd=128 --txd=128 --interactive
```

脚本最后打印 `dpdk-ring: testpmd exited with status <N>`，再调用 `/bin/nemu-trap` 让 gem5 退出。



相对通用 DPDK 用法，这里为 gem5 做了四处裁剪：

1. 单核。
2. 命令一次性从管道送入，不走交互输入。
3. 不采集 guest 侧 perf。
4. 转发窗口由 `sleep <N>` 控制。



参数含义：

+ 单 hart：`--lcores='(0-1)@0'` 把逻辑 lcore 0 和 1 都放到物理 CPU 0，`--nb-cores=1`。
+ `--no-huge`，mbuf 池只要 2048 个，`--rxd=128 --txd=128`，不依赖大页和真实网卡。
+ `--vdev=net_ring0/1` 加 `--port-topology=loop`，两个 net_ring 口互打。
+ `sleep <N>` 是控制模拟时长的参数。单核 O3 上，纯转发阶段大约一个 guest 秒要十几个小时 host。

输出：

+ 业务结果在串口，也就是运行目录的 `run.log`：两个口的 `TX-packets`、`TX-dropped`、`TX-total`，以及 `dpdk-ring: testpmd exited with status 0`。
+ gem5 性能统计在运行目录的 `stats.txt`。



`network/results/dpdk-ring-sleep0.1-xsgem5-20260923/` 是 `sleep 0.1` 冷启动的一次完整实测。`run.log` 和 `stats.txt` 都在里面：host 12209.94 s，guest 0.213781 s，两个口各 `TX-total: 6665920`，`TX-dropped: 0`，退出码 0。

---

## 2. workload-builder 构建
### DTB
模板是 `dts/xiangshan-gem5-16550-1core-2g.dts.in`，来源是仓库里的 `dts/xiangshan.dts.in`。对照 gem5 为 `linux.bin` 生成的 DTS，改了两处：

+ **memory 从 128 MiB 改为 2 GiB。** DPDK rootfs 有 31 MB，128 MiB 内存解包不下。
+ **串口从 uartlite@0x40600000 改为 ns16550a@0x310b0000。** Linux 的 xlnx-uartlite 驱动使用 32-bit MMIO，而 gem5 的 uartlite 模型会在非 1 字节访问时 assert。

### Linux
使用 `BR2_DEFCONFIG_NAME=nemu-linux618_defconfig`，指向本地 `riscv-linux` commit `03f150c0abaae2ae26a27157d8a624ffe824fb20`，kernelrelease 为 6.18.34。

### DPDK
版本 25.11.2。meson 只打开 `net/ring` PMD 和 `test-pmd`：

```latex
-Dexamples= -Dtests=false -Denable_drivers=net/ring -Denable_apps=test-pmd \
-Ddisable_libs=bpf -Dbuildtype=release
```

### initrd
+ 内核内嵌的是 Buildroot 基础 rootfs，约 8.4 MB，对应 `output/images/rootfs.cpio`。
+ DPDK 的 31.6 MB cpio 是外部 initrd，由 DTB 的 `linux,initrd-start` 和 `linux,initrd-end` 传入，启动时覆盖内嵌的那份。
+ rootfs 解包后约 30 MB。`dpdk-testpmd` 的 `NEEDED` 只有 `libc.so.6`、`libm.so.6` 和 `ld-linux-riscv64-lp64d.so.1`。`usr/lib` 下的 DPDK `.so` / `.a`（约 25 MB，其中 `.a` 占 13.9 MB）以及 `libstdc++` / `libgfortran`（4.1 MB）运行时用不到，testpmd 本身也没有 strip。按 `NEEDED` 精简并 strip 后，rootfs 可以降到 5 MB 量级，固件从 59 MB 降到约 34 MB。目前交付的固件还是未精简的版本。

---

## 3. checkpoint 恢复
测试用 `sleep` 等待，恢复后还要继续走真实的时间延迟，所以 timer 在三处做了对齐。gem5 侧的 patch 在 `patches/xsgem5/`。

**xs-GEM5：** `src/dev/riscv/clint.cc` 里的 `mtime` 从只读改为可写。restorer 通过 MMIO 把 checkpoint 里的 `mtime` 和 `mtimecmp` 写回 CLINT。只读时写入会被丢掉，恢复后时钟从 0 开始，而内存里的 deadline 仍停在旧时间基准上，定时器中断就不再触发。

**NEMU（生成 checkpoint 时）：** `configs/riscv64-xs-cpt_defconfig` 关掉 `CONFIG_RV_SSTC`，并把 `CONFIG_CYCLES_PER_MTIME_TICK` 设为 3003，对齐 xs-GEM5 的 3.003 GHz 和 1 MHz RTC。本目录的 checkpoint 已经按这个配置生成。

**校验：** 不要用 `mtimecmp - mtime` 判断还剩多少 guest 时间。`mtimecmp` 只是内核的下一个定时器，量级是几毫秒，不是 `sleep` 的截止点。NEMU 日志里 `Record mtime` 与 `Taking checkpoint @ instruction count` 的比值应为 3003。

本次使用的 checkpoint 是 `boot/dpdk-ring/550000000/_550000006_memory_.zstd`，打在 `start tx_first` 之后。目录名按 `--cpt-interval` 对齐到 550000000，文件名里的精确指令数是 550000006。恢复时不加 `--raw-cpt`。

---

## 4. 各窗口耗时
下面除单独注明的一行外，都是 `SimpleMemory`。`sleep 1` 的 DRAMsim3 没记录。

| guest 窗口 | 方式 | 内存 | host 时间 | 结果 |
| --- | --- | --- | --- | --- |
| `sleep 0.05` | 冷启动全程 | SimpleMemory | 2 h 45 m（实测 `real 9917.77` s） | 更早的转发配置，`TX-dropped` 不为 0 |
| `sleep 0.1` | 冷启动全程 | SimpleMemory | 3 h 23 m（实测 `real 12209.94` s） | guest 0.213781 s，每口 `TX-total` 6,665,920 |
| `sleep 0.1` 剩余约 0.059 s | 从 400M checkpoint 恢复 | SimpleMemory | 1964.92 s | 累计 `TX-total` 873,664 |
| `sleep 0.1` 剩余约 0.059 s | 从 400M checkpoint 恢复 | DRAMsim3 | 2118.91 s | 累计 `TX-total` 1,050,560，`TX-dropped` 0 |
| `sleep 1` 剩余 0.967 s | 从 550M checkpoint 恢复 | SimpleMemory | 15 h 59 m（实测 `real 57512.87` s） | 见下方 |
| `sleep 3` | 冷启动全程 | SimpleMemory | 约 5 天（历史估算） | 未作为本次交付 |


`sleep 1` 的 SimpleMemory 实测目录是 `xsGEM5/m5out/restore-open-550m-1s-sync3003-20260924/`，已于 2026-09-25 04:40 自然退出。交付副本在本文开头的 `result/` 目录，里面是 `run.log` 和 `stats.txt`。

+ guest `simSeconds` 0.967015，`simInsts` 5,672,501,035，IPC 1.95。
+ host：`/usr/bin/time` 的 `real 57512.87` s，stats 里的 `hostSeconds` 57510.27。
+ 两个口各 `TX-total: 106777472`，`TX-dropped: 0`；合计 `TX-packets: 213554944`。
+ `dpdk-ring: testpmd exited with status 0`，随后 `Exiting @ tick 967015398618 because m5_exit`。
+ `config.ini` 确认 `[system.mem_ctrls] type=SimpleMemory`，不是 DRAMsim3。

冷启动走到 `start tx_first` 本身大约 3 小时，所以 `sleep 0.05` 和 `sleep 0.1` 的差别大部分被启动时间吃掉。纯转发阶段大约是 1.7e-5 guest 秒 / host 秒（XiangShan O3、单核 3.003 GHz、SimpleMemory）：这次 0.967 guest 秒用了 57513 host 秒。按这个速率，一个 guest 秒大约 16.5 host 小时。窗口越长，越适合 checkpoint 恢复，而不是冷启动。

`sleep 0.05` 用的是更早的转发配置，`TX-dropped` 不为 0，包数不要和后面几次比较。之前把 `sleep 1` 估成约 13 host 小时、剩余约 0.92 guest 秒；实测是 0.967 guest 秒、15 小时 59 分。

---

## 5. 交付物
```latex
/nfs/home/share/hushunchao/performance-test-for-infra-team/
├── network/
│   ├── DESCRIPTION.md                                         说明
│   ├── README.md                                              英文清单和 SHA-256
│   ├── dts/
│   │   ├── xiangshan-gem5-16550-1core-2g.dts.in               DTS 模板
│   │   └── xiangshan-gem5-16550-1core-2g.dts                  实际展开版
│   ├── firmware/
│   │   └── fw_payload-dpdk-ring-sleep1s-16550-1core-2g.bin    58,919,424 B
│   ├── checkpoint/
│   │   └── dpdk-ring-sleep1s-nemu-rvgcpt-550M-16550-1core-2g.zstd
│   ├── patches/
│   │   └── xsgem5/
│   │       ├── 0001-clint-mtime-writable-for-nemu-rvgcpt.patch
│   │       └── 0002-uartlite-1-2-4-byte-mmio.patch
│   └── results/
│       └── dpdk-ring-sleep0.1-xsgem5-20260923/
│           ├── run.log                                        sleep 0.1 串口输出
│           └── stats.txt                                      sleep 0.1 gem5 统计
└── result/
    └── dpdk-ring-sleep1-550m-simplememory-20260925/
        ├── run.log                                            sleep 1 SimpleMemory 串口
        ├── stats.txt                                          sleep 1 SimpleMemory 统计
        └── SOURCE.txt                                         来源和结果摘要
```
