# 生成 workload-builder 设备树模板

`generate-workload-builder-dts.py` 复用本目录的 `DTSGen`，可以独立输出
workload-builder 使用的 `.dts.in` 模板。当前 workload-builder 构建会通过
`scripts/generate-nemu-board-dts.py` 自动调用同一个 `DTSGen`，并将模板写入
`build/generated-dts`。

需要 **Python 3.12 或更高版本**（现有 DTSGen 使用 Python 3.12 的 f-string 语法）。
生成阶段不需要 dtc；workload-builder 构建时仍使用自己的 dtc。

## 单核 FPGA：当前 noAIA-novec 配置

假设 nemu_board 和 workload-builder 在同一父目录，在 nemu_board 根目录执行：

```sh
python3 dts/generate-workload-builder-dts.py \
  --profile fpga-noaia-novec \
  --memory-gib 2 \
  --output ../workload-builder/build/generated-dts/generated-fpga-noaia-novec.dts.in

make -C ../workload-builder linux/coremark \
  DEFAULT_DTB=generated-fpga-noaia-novec
```

输出使用新名称，避免覆盖已有模板。将 `--memory-gib` 改为 8、16、24、
64 等可以生成其他内存容量。声明容量必须与实际目标一致。

## QEMU nemu：单核或多核

```sh
python3 dts/generate-workload-builder-dts.py \
  --profile qemu-nemu --harts 4 --memory-gib 16 --no-vector \
  --output ../workload-builder/build/generated-dts/generated-qemu-4hart-mem16g-novec.dts.in

make -C ../workload-builder linux/coremark \
  PLATFORM=qemu MULTIHART=1 HARTS=4 \
  DEFAULT_DTB=generated-qemu-4hart-mem16g-novec
```

单核使用 `--harts 1`，构建时使用 `PLATFORM=qemu MULTIHART=0`。
多核范围为 2..128，生成器与 make 的核数必须一致。
当前 builder 的多核镜像用于 QEMU checkpoint 流程，因此多核只接受
`qemu-nemu` profile；不把它标称为已验证的多核 FPGA 启动方案。

## NEMU：UARTLite 配置

```sh
python3 dts/generate-workload-builder-dts.py \
  --profile nemu --memory-gib 8 \
  --output ../workload-builder/build/generated-dts/generated-nemu-mem8g.dts.in

make -C ../workload-builder linux/coremark \
  DEFAULT_DTB=generated-nemu-mem8g
```

不指定容量时，`nemu` profile 使用现有 `xiangshan.dts.in` 的 128 MiB。
较大的 workload 需要显式增加内存。

## Profile 定义和边界

| Profile | 默认内存 | UART | PLIC 中断源 | MMU | 默认 ISA 来源 |
|---|---|---|---|---|---|
| fpga-noaia-novec | 2 GiB | 16550A @ 0x310b0000，无 IRQ | 66 | Sv48 | xiangshan-fpga-noAIA-novec.dts.in |
| qemu-nemu | 2 GiB | 16550A @ 0x310b0000，无 IRQ | 66 | Sv48 | xiangshan-qemu-nemu-mem2g.dts.in |
| nemu | 128 MiB | UARTLite @ 0x40600000，PLIC IRQ 3 | 64 | Sv39 | xiangshan.dts.in |

所有 profile 使用 DRAM 基地址 0x80000000、CLINT 0x38000000、
PLIC 0x3c000000 和 1 MHz 时间基准，默认使用 SBI 控制台。
NEMU profile 保留其源模板的 PLIC S/M context 顺序；另外两个使用 M/S 顺序。

ISA 来源固定于 workload-builder 提交
`aaf4d8bd7d2da5351fc2640c8d61c9d849d69342`，完整来源链接在
`workload-builder-profiles.json` 中。生成时不联网。
这些列表是现有模板的声明，不是硬件能力验证结果。FPGA 默认保留
`smcntrpmf`、`smcdeleg` 等原有声明，不擅自认定目标支持或不支持。
NEMU 源模板没有结构化列表，其默认列表由原有单字母 ISA 字符串推导。

这是接口兼容生成器，不是源模板的逐字复制。FPGA profile 将 CLINT/PLIC、
PLIC 节点名、SoC compatible、`reg-names` 和 CPU/ISA 属性对齐到现有 FPGA
模板；节点标签、空白和其他描述性属性仍可能不同。NEMU 原模板将
`next-level-cache` 指向 memory 节点，生成器不复制这一引用。
FPGA/QEMU 仍描述 64 KiB L1、1 MiB L2 和 48-entry I/D TLB。
不支持 AIA 节点生成，也不复制 kmh-v2.dtsi 的 PCIe、PMEM 或 EINJ/ERST 节点。

## 调整 ISA 和启动配置

- FPGA profile 默认使用现有 Kunminghu V3 ISA 声明；传入
  `--isa-config kunminghu-v2` 可切换为 Kunminghu V2。该选项只改变
  CPU ISA 声明，不改变板级拓扑；CBO block-size 属性会按所选扩展列表
  一并生成或省略。
- `--isa-extensions i m a f d c zicsr zifencei`：完全替换扩展列表，不与
  RVA profile 合并。此时 legacy ISA 字符串也按该列表生成。
- `--exclude-isa smcntrpmf smcdeleg`：从默认或自定义列表移除指定扩展，
  同时从 legacy ISA 字符串删除对应声明。
- `--no-vector`：同时移除 `v` 和所有 `zv*`，保留 `rv64` 前缀。
- QEMU profile 始终去掉 `sstc`，匹配当前 builder 的 timer 限制。
- `fpga-noaia-novec` 拒绝向量声明；所有 profile 拒绝 `smaia/ssaia`，
  避免生成与其中断拓扑明显不一致的模板。
- `--timebase-freq 1000000`：计时基准，单位 Hz，不是 CPU 主频。
- `--mmu-type riscv,sv48`：覆盖 MMU 类型。
- `--bootargs "console=hvc0 earlycon=sbi loglevel=8"`：覆盖内核参数。
- `--memory-size 0x200000000`：按字节指定容量，与 `--memory-gib` 互斥。
- 省略 `--output` 输出到 stdout；指定路径必须以 `.dts.in` 结尾。

除了上述基本一致性检查，生成器不验证所有 ISA 扩展之间的依赖关系。
内存、计时频率、缓存信息和 ISA 声明仍需与实际 RTL/模拟器配置核对。

## 与 builder 的地址契约

生成的 chosen 节点包含：

```dts
linux,initrd-start = <INITRAMFS_BEGIN_HI INITRAMFS_BEGIN_LO>;
linux,initrd-end = <INITRAMFS_END_HI INITRAMFS_END_LO>;
```

这些是模板占位符，必须由 builder 根据实际内核及 rootfs 大小替换，
不能直接将 .dts.in 交给 dtc 编译。

| 项目 | 单核 | 多核 |
|---|---|---|
| GCPT no-map 保留区 | [0x80000000, 0x80100000) | 相同 |
| checkpoint 状态 no-map 保留区 | 无 | [0x80300000, 0x88600000)，131 MiB |
| OpenSBI 地址（builder 放置） | 0x80100000 | 0x80100000 |
| DTB 地址（builder 放置） | 0x80200000 | 0x80200000 |
| 内核地址（builder 放置） | 0x80400000 | 0x88600000 |

多核保留区大小特意写成 `0x08300000`，兼容现有 builder 的文本检查，
所以无需修改 builder 的 awk 代码。生成器不负责打包或重新计算启动地址。
使用 workload-builder 已识别的 basename 时，make 会自动生成模板。上面的
显式命令用于自定义 profile 或 basename；只要模板已存在，builder 会保留
无法由内置规则识别的自定义 basename。

## 验证

```sh
python3 -m unittest discover -s dts -p 'test_*.py' -v

# 安装 dtc/fdtget 后，使用真实 builder 打包脚本执行集成验证：
WORKLOAD_BUILDER=../workload-builder \
  python3 -m unittest discover -s dts -p 'test_*.py' -v
```

可通过 `DTC` 和 `FDTGET` 指定工具路径。
集成测试覆盖 FPGA 单核、NEMU 单核、QEMU 单核、双核和 128 核，
检查 DTB 内存/中断/hart 信息、占位符替换、保留区检查，以及
GCPT、OpenSBI、DTB、内核、initramfs 的镜像位置和内容。
测试使用小型标记 payload，不构建真实 Linux，也不验证硬件启动。

原有 `DTSGen.py` CLI 保留。公共生成器同时修复了
`--timebase-freq` 未传入构造函数、保留内存在实例之间共享，以及
hart ID >= 10 时节点 unit-address 未用十六进制表示的问题。
