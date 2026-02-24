#ifndef _CTYPE_H
#define _CTYPE_H

static inline int isdigit(int c) { return (c >= '0' && c <= '9'); }
static inline int isalpha(int c) { return ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')); }
static inline int isspace(int c) { return (c==' '||c=='\n'||c=='\t'||c=='\r'||c=='\f'||c=='\v'); }

#endif
