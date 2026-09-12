# DTS Generator

This directory is the canonical source for workload-builder device-tree
generation. It contains `DTSGen.py`, the profile generator, the build-facing
basename generator, and profile data. Recognized `DEFAULT_DTB` names are
generated into `build/generated-dts` during the build. An unsupported custom
basename can be supplied explicitly as `dts/<name>.dts.in`; the build copies it
into the generated directory before packing the firmware.

## Generate A Template

The profile-oriented CLI is useful when creating a template explicitly:

```sh
python3 dts/generate-workload-builder-dts.py \
  --profile fpga-noaia-novec \
  --memory-gib 16 \
  --output /tmp/custom-fpga.dts.in
```

Supported profiles are `fpga-noaia-novec`, `qemu-nemu`, and `nemu`. Use
`--harts 2..128` with `qemu-nemu` for multi-hart output. `--memory-gib` and
`--memory-size` select the DRAM capacity; `--no-vector` removes vector ISA
declarations. This CLI is for inspecting or exporting a profile; Make selects
profiles through `DEFAULT_DTB` and regenerates its own build-tree copy. The
generated file contains `INITRAMFS_BEGIN_*` and
`INITRAMFS_END_*` placeholders and must be processed by the firmware packer
before it is compiled into a DTB.

The build-facing CLI accepts a complete basename and is what Make invokes:

```sh
python3 dts/generate-nemu-board-dts.py \
  --name xiangshan-qemu-nemu-2hart-mem16g \
  --output build/generated-dts/xiangshan-qemu-nemu-2hart-mem16g.dts.in
```

Built-in names include the `xiangshan`, `yanqihu`, `nutshell`, and `spike`
profiles, FPGA noAIA names, and QEMU `nemu` names of the form
`<board>[-<harts>hart][-mem<size>g][-novec]`. Unknown names use a matching
custom template passed through `--custom-template-dir`; otherwise generation
fails with an `unsupported DTS basename` error.

For generated FPGA noAIA names, select the ISA declaration independently of
the basename:

```sh
make linux/coremark \
  DEFAULT_DTB=xiangshan-fpga-noAIA-mem16g-novec \
  DTS_ISA_CONFIG=kunminghu-v2
```

`DTS_ISA_CONFIG` accepts `kunminghu-v2` and `kunminghu-v3`, with V3 as the
default. The `-novec` suffix still controls vector advertisement.

## Direct DTSGen CLI

`DTSGen.py` remains available for low-level generation:

```sh
python3 dts/DTSGen.py --nr-harts 2 --memory-size 0x400000000 \
  --rva-profile rva23s64 | dtc -O dtb -o build/example.dtb -
```

## Profiles And Validation

Profile data is stored in `workload-builder-profiles.json`. The `source` URLs
in that file document the historical workload-builder templates from which
the declarations were derived; generation itself is offline.

The build invokes the generator and then uses `dtc` to compile the generated
template. This validates DTS generation, DTB compilation, and image assembly;
it does not prove that NEMU, QEMU, or FPGA hardware boots a workload
successfully.

## Contributors

The generator incorporates the `DTSGen` implementation and device-tree
conventions from OpenXiangShan's `nemu_board`. The vendored source revision is
commit `15db1e6` of
[`OpenXiangShan/nemu_board`](https://github.com/OpenXiangShan/nemu_board/commit/15db1e6cdf4dcbf4cc016cb8938a5f8f35b59faf).

GitHub authors and co-authors represented in that revision are:

- `chenguokai`
- `xyyy1420`
- `dzwduan`
- `cyyself`
- `Gs-ygc`
