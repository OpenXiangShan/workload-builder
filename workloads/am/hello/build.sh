#!/usr/bin/env bash
set -e

mkdir -p "$PKG_DIR"/{bin,elf}
make -C "$AM_HOME"/apps/hello ${AM_MAKEARGS} -j1
cp "$AM_HOME/apps/hello/build/hello-$AM_ARCH.bin" "$PKG_DIR/bin/"
cp "$AM_HOME/apps/hello/build/hello-$AM_ARCH.elf" "$PKG_DIR/elf/"
