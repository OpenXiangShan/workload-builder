#define DISABLE_TIME_INTR 0x100
#define NOTIFY_PROFILER 0x101

static void nemu_signal(int code) {
    asm volatile(
        "mv a0, %0\n\t"
        ".insn r 0x6B, 0, 0, x0, x0, x0\n\t"
        :
        : "r"(code)
        : "a0");
}

int main(void) {
    nemu_signal(DISABLE_TIME_INTR);
    nemu_signal(NOTIFY_PROFILER);
    return 0;
}
