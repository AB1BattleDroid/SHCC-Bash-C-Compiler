#ifndef _UNISTD_H
#define _UNISTD_H

typedef long ssize_t;
typedef unsigned long size_t;

/* File descriptors */
#define STDIN_FILENO  0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

// Syscall numbers per architecture

#if defined(__x86_64__)

#define SYS_read   0
#define SYS_write  1
#define SYS_exit   60

#elif defined(__i386__)

/* x86-32 Linux syscall numbers */
#define SYS_read   3
#define SYS_write  4
#define SYS_exit   1

#elif defined(__aarch64__)

#define SYS_read   63
#define SYS_write  64
#define SYS_exit   93

#elif defined(__arm__)

#define SYS_read   3
#define SYS_write  4
#define SYS_exit   1

#elif defined(__riscv)

#define SYS_read   63
#define SYS_write  64
#define SYS_exit   93

#else
#error "Unsupported architecture"
#endif

// Syscall backend per architecture   

#if defined(__x86_64__)

/* x86-64: syscall, rax=sysno, rdi, rsi, rdx */
static inline long sys_call3(long n, long a0, long a1, long a2) {
    long ret;
    asm volatile (
        "syscall"
        : "=a"(ret)
        : "a"(n), "D"(a0), "S"(a1), "d"(a2)
        : "rcx", "r11", "memory"
    );
    return ret;
}

#elif defined(__i386__)

/* x86-32: int 0x80, eax=sysno, ebx, ecx, edx */
static inline long sys_call3(long n, long a0, long a1, long a2) {
    long ret;
    asm volatile (
        "int $0x80"
        : "=a"(ret)
        : "a"(n), "b"(a0), "c"(a1), "d"(a2)
        : "memory"
    );
    return ret;
}

#elif defined(__aarch64__)

/* ARM64: svc #0, x8=sysno, x0-x5 args */
static inline long sys_call3(long n, long a0, long a1, long a2) {
    register long x8 asm("x8") = n;
    register long x0 asm("x0") = a0;
    register long x1 asm("x1") = a1;
    register long x2 asm("x2") = a2;
    asm volatile (
        "svc #0"
        : "+r"(x0)
        : "r"(x8), "r"(x1), "r"(x2)
        : "memory"
    );
    return x0;
}

#elif defined(__arm__)

/* ARM32: svc #0, r7=sysno, r0-r6 args */
static inline long sys_call3(long n, long a0, long a1, long a2) {
    register long r7 asm("r7") = n;
    register long r0 asm("r0") = a0;
    register long r1 asm("r1") = a1;
    register long r2 asm("r2") = a2;
    asm volatile (
        "svc #0"
        : "+r"(r0)
        : "r"(r7), "r"(r1), "r"(r2)
        : "memory"
    );
    return r0;
}

#elif defined(__riscv)

/* RISC-V: ecall, a7=sysno, a0-a5 args */
static inline long sys_call3(long n, long a0, long a1, long a2) {
    register long a7 asm("a7") = n;
    register long a0r asm("a0") = a0;
    register long a1r asm("a1") = a1;
    register long a2r asm("a2") = a2;
    asm volatile (
        "ecall"
        : "+r"(a0r)
        : "r"(a7), "r"(a1r), "r"(a2r)
        : "memory"
    );
    return a0r;
}

#endif

// Public wrappers  

static inline ssize_t read(int fd, void *buf, size_t count) {
    return (ssize_t)sys_call3(SYS_read, fd, (long)buf, count);
}

static inline ssize_t write(int fd, const void *buf, size_t count) {
    return (ssize_t)sys_call3(SYS_write, fd, (long)buf, count);
}

static inline void _exit(int status) {
    sys_call3(SYS_exit, status, 0, 0);
    for (;;) {}
}

#endif /* _UNISTD_H */
