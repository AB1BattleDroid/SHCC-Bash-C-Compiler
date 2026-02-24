#ifndef _STDIO_H
#define _STDIO_H

#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>

#define NULL ((void *)0)

static inline int fputs(const char *s, int fd) {
    size_t n = strlen(s);
    if (n==0) return 0;
    ssize_t w = write(fd, s, n);
    return (int)((w<0)?-1:w);
}

static inline int puts(const char *s) {
    int r = fputs(s, STDOUT_FILENO);
    if (r<0) return r;
    char nl='\n';
    write(STDOUT_FILENO,&nl,1);
    return r+1;
}

static inline int putchar(int c) {
    char ch=(char)c;
    write(STDOUT_FILENO,&ch,1);
    return c;
}

static inline int print_s(const char *s) { return fputs(s, STDOUT_FILENO); }

static inline int print_d(int v) {
    char buf[32];
    itoa(v, buf);
    return fputs(buf, STDOUT_FILENO);
}

/* internal formatter */
static inline int vformat(int fd, char *buf, size_t buflen,
                          const char *fmt, va_list args) {
    int total = 0;
    char tmpbuf[64];

    for (const char *p = fmt; *p; ++p) {
        if (*p == '%' && *(p+1)) {
            ++p;
            if (*p == 's') {
                char *s = va_arg(args, char*);
                size_t n = strlen(s);
                if (buf) {
                    if (total + n < buflen) memcpy(buf+total, s, n);
                } else {
                    write(fd, s, n);
                }
                total += (int)n;
            } else if (*p == 'd') {
                int v = va_arg(args, int);
                itoa(v, tmpbuf);
                size_t n = strlen(tmpbuf);
                if (buf) {
                    if (total + n < buflen) memcpy(buf+total, tmpbuf, n);
                } else {
                    write(fd, tmpbuf, n);
                }
                total += (int)n;
            } else if (*p == 'c') {
                char c = (char)va_arg(args, int);
                if (buf) {
                    if (total+1 < buflen) buf[total] = c;
                } else {
                    write(fd, &c, 1);
                }
                total++;
            } else if (*p == 'x') {
                unsigned int v = va_arg(args, unsigned int);
                char *q = tmpbuf;
                if (v == 0) { *q++ = '0'; }
                while (v) {
                    int digit = v & 0xF;
                    *q++ = (digit < 10) ? ('0'+digit) : ('a'+digit-10);
                    v >>= 4;
                }
                *q = '\0';
                reverse(tmpbuf);
                size_t n = strlen(tmpbuf);
                if (buf) {
                    if (total+n < buflen) memcpy(buf+total, tmpbuf, n);
                } else {
                    write(fd, tmpbuf, n);
                }
                total += (int)n;
            } else {
                if (buf) {
                    if (total+2 < buflen) { buf[total++]='%'; buf[total++]=*p; }
                } else {
                    char out[2]={'%',*p};
                    write(fd,out,2);
                }
                total+=2;
            }
        } else {
            if (buf) {
                if (total+1 < buflen) buf[total]=*p;
            } else {
                write(fd,p,1);
            }
            total++;
        }
    }

    if (buf && total < buflen) buf[total] = '\0';
    return total;
}

/* printf: to stdout */
static inline int printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int r = vformat(STDOUT_FILENO, NULL, 0, fmt, args);
    va_end(args);
    return r;
}

/* fprintf: to any fd */
static inline int fprintf(int fd, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int r = vformat(fd, NULL, 0, fmt, args);
    va_end(args);
    return r;
}

/* snprintf: to buffer */
static inline int snprintf(char *buf, size_t buflen, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int r = vformat(-1, buf, buflen, fmt, args);
    va_end(args);
    return r;
}


#endif
