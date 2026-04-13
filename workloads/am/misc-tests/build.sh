#!/usr/bin/env bash
set -e

build-test() {
    test_dir="$1"
    make -C "$test_dir" ${AM_MAKEARGS} -j1
    cp "$test_dir"/build/*.bin "$PKG_DIR"/bin/
    cp "$test_dir"/build/*.elf "$PKG_DIR"/elf/
}

tests=(
    aliasgenerator aliastest amtest cacheoptest/icache cacheoptest/dcache cacheoptest/llc
    countertest dualcoretest frequencytest frontendtest mmiotest
    oraclebptest softmdutest softprefetchtest zacas
)

mkdir -p "$PKG_DIR"/{bin,elf}
for test in "${tests[@]}" ; do
    build-test "$AM_HOME"/tests/"$test"
done

# build test bitmanip
(
    set -e
    cd "$AM_HOME"/tests/bitmanip
    cd src
    find -iname '*.S' -exec rm -f {} +
    python3 randtest.py 10000 1
    cd ..
    make ${AM_MAKEARGS}
    cp "build/bitmanip-$AM_ARCH.bin" "$PKG_DIR"/bin/bitmanip.bin
    cp "build/bitmanip-$AM_ARCH.elf" "$PKG_DIR"/elf/bitmanip.elf
)
