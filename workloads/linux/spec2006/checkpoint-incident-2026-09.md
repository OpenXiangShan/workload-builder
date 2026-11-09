# SPEC2006 Checkpoint 卡住问题总结与修复记录

## 结论

2026-09-28 启动的 `lmul1/lmul2/lmul4/lmul8` checkpoint 批任务并非同一种故障：

1. `lmul1/bzip2_liberty` 的 initramfs 是 0 字节，属于 workload-builder 打包失败被错误地当成成功。
2. 四组 `astar_rivers` 的 payload 都来自 2026-09-22，旧 bin 在 Linux 启动后执行 `./astar rivers.cfg` 时长期占用 NEMU CPU，未生成 SimPoint BBV。
3. `lmul8/gcc_expr2` 也停在 profiling，日志只到 Linux 启动早期，旧 payload 没有被替换。
4. `generate_checkpoint.py` 对 profiling/checkpoint 子进程直接 `wait()`，没有超时；任一 NEMU 永久运行都会阻塞整个 batch。

## 证据

原始 archive：

```text
/nfs/home/wujiabin/work/minjie-playground/archive/2026-09-28-10-11-39_bin
/nfs/home/wujiabin/work/minjie-playground/archive/2026-09-28-10-12-03_bin
/nfs/home/wujiabin/work/minjie-playground/archive/2026-09-28-10-12-46_bin
/nfs/home/wujiabin/work/minjie-playground/archive/2026-09-28-10-13-01_bin
```

`astar_rivers/profiling.err.log` 在四组中均停在：

```text
[0.183712] riscv-pmu-sbi: 16 firmware and 2 hardware counters
```

旧 `lmul1/bzip2_liberty.rootfs.cpio`：

```text
size = 0
cpio: premature end of archive
```

其他 lmul 的同名 rootfs 约 8 MB，并包含 `spec/bzip2`、`spec/liberty.jpg` 和 `spec/run.sh`。

## 已实施修复

文件：`scripts/build-workload-linux.sh`

- shell 改为 `set -euo pipefail`。
- cpio 写入临时文件，成功后再替换目标文件。
- 生成后强制检查非空和 `cpio -it` 可读。
- cpio/fakeroot 失败时立即返回错误，不再留下 0 字节伪成功 rootfs。

修复后的核心行为：

```bash
find . -print0 | fakeroot cpio --null -o -H newc > "$temp_file"
cpio -it < "$temp_file"
mv "$temp_file" "$cpio_file"
```

## 重建情况

使用：

```text
/nfs/home/share/cpu2006-1.2.iso
```

已成功重建 `lmul1/bzip2_liberty`。新文件位于：

```text
/nfs/home/share/wujiabin/workload_bin/260930_spec06_gcc16_rva23_lmul1/
```

关键结果：

```text
rootfs/bzip2_liberty.rootfs.cpio: 7990272 bytes
bin/bzip2_liberty.fw_payload.bin: 35253248 bytes
```

cpio 内容完整，包含：

```text
spec/bzip2
spec/liberty.jpg
spec/run.sh
etc/inittab
```

四组 `astar_rivers` 和 `gcc_expr2` 的重建任务曾启动，但构建进程很快退出，输出目录没有生成有效新 payload；因此原始 `astar_rivers` 和 `gcc_expr2` bin 仍未替换。

## NEMU 处理

没有修改原始 `NEMU_HOME`。诊断副本为：

```text
/nfs/home/wujiabin/work/NEMU-astar-debug
```

副本成功编译，并加入了信号快照日志。快照显示 `astar_rivers` 长时间位于 Linux 内核中断/锁路径附近，说明它不是单纯的 cpio 空文件问题；但目前没有提交 NEMU 功能修复。

## 任务处理

- 原四个 tmux 批处理及其旧 NEMU 子进程已停止。
- 旧 archive 中已完成的 checkpoint 文件保留，没有删除。
- 之后启动的 `--resume-after auto` 使用了各自正确的 lmul bin 路径。
- `lmul4/lmul8` 曾重新进入 profiling，但仍使用旧 `astar_rivers` bin；`lmul1/lmul2` 的旧 tmux shell 被控制字符污染，命令未正常执行。

## 后续运行建议

1. 先完成四组 `astar_rivers` 和 `lmul8/gcc_expr2` 的新 payload 构建。
2. 确认新 payload 的 mtime、SHA256、rootfs cpio 完整性。
3. 使用原 archive 和正确 lmul `bin/` 执行：

```bash
python3 scripts/checkpoint/generate_checkpoint.py \
  --input-path /nfs/home/share/wujiabin/workload_bin/260922_spec06_gcc16_rva23_lmulN/bin \
  --archive-id 2026-09-28-10-XX-XX_bin \
  --interval 20000000 \
  --max-workers 100 \
  --resume-after auto
```

4. 每组使用干净 tmux session，避免复用已经被终端控制字符污染的 shell。
5. 在脚本中加入 NEMU 子进程超时和失败回收，防止单个 workload 再次永久阻塞整个 batch。
