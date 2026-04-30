#!/bin/sh
set -x

if [ -r /etc/default/geekbench ]; then
    . /etc/default/geekbench
fi
GEEKBENCH_ARGS="${GEEKBENCH_ARGS:---cpu --iterations 1}"

mkdir -p /proc /sys
mount -t proc proc /proc
mount -t sysfs sysfs /sys

cd /geekbench
./geekbench_riscv64 $GEEKBENCH_ARGS
# Geekbench may fail after the benchmark when it cannot upload results, so
# treat reaching this point as successful workload completion.
nemu-trap 0
