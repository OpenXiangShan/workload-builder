#define NOTIFY_WORKLOAD_EXIT 0x102

static void nemu_signal(int code) {
    asm volatile(
        "mv a0, %0\n\t"
        ".insn r 0x6B, 0, 0, x0, x0, x0\n\t"
        :
        : "r"(code)
        : "a0");
}

int main(void) {
    nemu_signal(NOTIFY_WORKLOAD_EXIT);
    return 0;
}
