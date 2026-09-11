if [ -z "$(ls -A build)" ]; then
    echo "The build directory is empty. Creating the directory..."
    mkdir build
fi
python3 DTSGen.py \
    --nr-harts 1 \
    --nemu-sdhci-addr 0x40002000 \
    --rva-profile rva23s64 \
    --bootargs "console=hvc0 earlycon=sbi" \
    --mmu-type riscv,sv48 | \
dtc -O dtb -o build/xiangshan.dtb -
