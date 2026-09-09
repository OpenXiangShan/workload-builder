# SPECjbb2015 Linux workload

SPECjbb2015 is not distributed with this repository. Set `SPECJBB_INPUT` to a
licensed ISO, archive, or directory and `SPECJBB_RV_JDK_INPUT` to an RV64 JDK
25 directory or archive. No benchmark or JDK files are committed.

Build a two-hart XiangShan image:

```sh
make linux/specjbb2015 \
  SPECJBB_INPUT=/path/to/SPECjbb2015-1.03.iso \
  SPECJBB_RV_JDK_INPUT=/path/to/jdk25 \
  SPECJBB_MODE=COMPOSITE SPECJBB_JVM_XMS=4g SPECJBB_JVM_XMX=4g \
  MULTIHART=1 HARTS=2 \
  DEFAULT_DTB=xiangshan-fpga-noAIA-2hart-mem8g-novec -jN
```

The output is `build/linux-workloads/specjbb2015/fw_payload.bin`. The image
uses one multithreaded JVM shared by all guest harts and the standard
multi-hart checkpoint memory layout. The selected DTB must match `HARTS` and
provide enough memory for the configured Java heap.
