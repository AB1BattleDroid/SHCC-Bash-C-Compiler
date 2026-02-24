#ifndef _STRING_H
#define _STRING_H

typedef unsigned long size_t;

static inline size_t strlen(const char *s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
}

static inline char *strcpy(char *dest, const char *src) {
    char *d = dest;
    while ((*d++ = *src++));
    return dest;
}

static inline int strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return (unsigned char)*s1 - (unsigned char)*s2;
}

static inline void *memset(void *s, int c, size_t n) {
    unsigned char *p = (unsigned char *)s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}

static inline void *memcpy(void *dest, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) *d++ = *s++;
    return dest;
}

#endif
