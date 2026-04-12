#!/usr/bin/env bash
set -e

artifact_prefix="coremark-$AM_ARCH"

mkdir -p "$PKG_DIR"/{bin,elf}

cd "$AM_HOME"/apps/coremark

make ${AM_MAKEARGS} clean
make ${AM_MAKEARGS} CC_OPT="-O2 -march=rv64gc" -j1
cp "build/$artifact_prefix.bin" "$PKG_DIR"/bin/"$artifact_prefix"-rv64gc-o2.bin
cp "build/$artifact_prefix.elf" "$PKG_DIR"/elf/"$artifact_prefix"-rv64gc-o2.elf

make ${AM_MAKEARGS} clean
make ${AM_MAKEARGS} CC_OPT="-O3 -march=rv64gc" -j1
cp "build/$artifact_prefix.bin" "$PKG_DIR"/bin/"$artifact_prefix"-rv64gc-o3.bin
cp "build/$artifact_prefix.elf" "$PKG_DIR"/elf/"$artifact_prefix"-rv64gc-o3.elf

make ${AM_MAKEARGS} clean
make ${AM_MAKEARGS} CC_OPT="-O3 -march=rv64gcb" -j1
cp "build/$artifact_prefix.bin" "$PKG_DIR"/bin/"$artifact_prefix"-rv64gcb-o3.bin
cp "build/$artifact_prefix.elf" "$PKG_DIR"/elf/"$artifact_prefix"-rv64gcb-o3.elf
