void trap(int code) {
    asm volatile("mv a0, %0; .word 0x0005006b" : :"r"(code));
}

int atoi_lite(char *a) {
    int ans = 0;
    if (a[0] == '-') {
        for (int i=0; a[i]; ++i) {
            ans = (ans<<3) + (ans<<1);
            ans -= a[i] - '0';
        }
    } else {
        for (int i=0; a[i]; ++i) {
            ans = (ans<<3) + (ans<<1);
            ans += a[i] - '0';
        }
    }
    return ans;
}

int main(int argc, char** argv) {
    if (argc <= 1) {
        trap(0);
    } else {
        trap(atoi_lite(argv[1]));
    }
    return 0;
}
