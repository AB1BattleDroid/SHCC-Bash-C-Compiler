#ifndef _STDLIB_H
#define _STDLIB_H

#include <string.h>

static inline int atoi(const char *s) {
    int sign = 1;
    int res = 0;
    while (*s==' '||*s=='\t'||*s=='\n') s++;
    if (*s=='-'||*s=='+') { if (*s=='-') sign=-1; s++; }
    while (*s>='0'&&*s<='9') { res=res*10+(*s-'0'); s++; }
    return sign*res;
}

static inline void reverse(char *s) {
    char *e = s;
    while (*e) e++;
    e--;
    while (s<e) { char tmp=*s; *s=*e; *e=tmp; s++; e--; }
}

static inline char *itoa(int value, char *buf) {
    unsigned int v = (value<0)?-value:value;
    char *p = buf;
    if (value==0) { buf[0]='0'; buf[1]='\0'; return buf; }
    while (v) { *p++='0'+(v%10); v/=10; }
    if (value<0) *p++='-';
    *p='\0';
    reverse(buf);
    return buf;
}

#endif
