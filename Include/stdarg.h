#ifndef _STDARG_H
#define _STDARG_H

typedef char* va_list;

/* Align to word boundary */
#define _VA_ALIGN(t) ((sizeof(t) + sizeof(long) - 1) & ~(sizeof(long) - 1))

#define va_start(ap, last) (ap = (va_list)&last + _VA_ALIGN(last))
#define va_arg(ap, type)   (*(type *)((ap += _VA_ALIGN(type)) - _VA_ALIGN(type)))
#define va_end(ap)         (ap = (va_list)0)

#endif
