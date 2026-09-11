if [ -z "$(ls -A build)" ]; then
    echo "The build directory is empty. Creating the directory..."
    mkdir build
fi
python3 DTSGen.py \
    --nr-harts 8 \
    --rva-profile rva23s64 \
    --bootargs "console=hvc0 earlycon=sbi" \
    -r 0x80000000 0x100000 \
    -r 0x80300000 0x1400000 \
    --mmu-type riscv,sv48 | \
dtc -O dtb -o build/xiangshan_eightcore.dtb -
