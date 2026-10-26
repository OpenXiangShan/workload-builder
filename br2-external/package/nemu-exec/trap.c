void trap(int code) {
    asm volatile("mv a0, %0; .word 0x0005006b" : : "r"(code) : "a0", "memory");
}
