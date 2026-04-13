#!/usr/bin/env bash
set -e

build-test() {
    test_dir="$1"
    make -C "$test_dir" ${AM_MAKEARGS} -j1
    cp "$test_dir"/build/*.bin "$PKG_DIR"/bin/
    cp "$test_dir"/build/*.elf "$PKG_DIR"/elf/
}

mkdir -p "$PKG_DIR"/{bin,elf}
build-test "$AM_HOME"/tests/cputest
