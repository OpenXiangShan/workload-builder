.data
msg:    .ascii "Hello, world!\n"
len = . - msg

.text
.globl _start

_start:
    li a0, 1              # File descriptor: stdout = 1
    # This is a freestanding entry point, so no C runtime has initialized gp.
    # Disable linker relaxation to keep symbol addresses PC-relative.
    .option push
    .option norelax
    la a1, msg            # Load address of message string
    .option pop
    li a2, len            # Length of the string
    li a7, 64             # Linux syscall number for write (64)
    ecall                 # Make system call
    li t0, len
    bne a0, t0, fail

    li a0, 0              # Exit status = 0
    .word 0x0000006b      # NEMU trap instruction

fail:
    li a0, 1
    .word 0x0000006b
