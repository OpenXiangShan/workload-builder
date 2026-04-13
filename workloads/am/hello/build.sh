#!/usr/bin/env bash
set -e

mkdir -p "$PKG_DIR"/{bin,elf}
make -C "$AM_HOME"/apps/hello ${AM_MAKEARGS} -j1
cp "$AM_HOME"/apps/hello/build/*.bin "$PKG_DIR"/bin/
cp "$AM_HOME"/apps/hello/build/*.elf "$PKG_DIR"/elf/
