#include <unistd.h>
#include <sys/wait.h>

#define DISABLE_TIME_INTR 0x100
#define NOTIFY_PROFILER 0x101
#define GOOD_TRAP 0
#define BAD_TRAP -1

void trap(int code);

int main(int argc, char *argv[]) {
    if (argc < 2) {
        // usage: nemu-exec cmd ...
        trap(BAD_TRAP);
    }

    pid_t pid = fork();
    
    if (pid == -1) {
        // should not reach here
        trap(BAD_TRAP);
    } else if (pid == 0) {
        // child process, enable profiling and run workload
        trap(DISABLE_TIME_INTR);
        trap(NOTIFY_PROFILER);
        execvp(argv[1], argv+1);
        // should not reach here
        trap(BAD_TRAP);
    } else {
        // Parent process
        int status;
        pid_t waited_pid = waitpid(pid, &status, 0);
        if (waited_pid == -1) {
            // should not reach here
            trap(BAD_TRAP);
        }
        trap(status);
    }

    // should not reach here
    return 0;
}

void trap(int code) {
    asm volatile("mv a0, %0; .word 0x0005006b" : :"r"(code));
}
