#ifndef WIN_CRT_H
#define WIN_CRT_H

#include "../util/util.h"
#include <windows.h>

#define STR_LEN(str) (sizeof(str) / sizeof((str)[0]))

#ifdef UNICODE
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused"
static size_t strlen_wide(const char_t *str) { return wcslen(str) * 2; }
#pragma clang diagnostic pop
#define strlen strlen_wide
#endif

extern char_t *strcat_wide(char_t *dst, const char_t *src);
#define strcat strcat_wide

extern char_t *strcpy_wide(char_t *dst, const char_t *src);
#define strcpy strcpy_wide

extern char_t *strncpy_wide(char_t *dst, const char_t *src, size_t len);
#define strncpy strncpy_wide

extern void *dlsym(HMODULE handle, const char *name);

#define RTLD_LAZY 0x00001

extern HMODULE dlopen(const char_t *filename, int flag);

extern int setenv(const char_t *name, const char_t *value, int overwrite);
extern char_t *getenv_wide(const char_t *name);
#define getenv getenv_wide

#ifndef UNICODE

#define strcmpi lstrcmpiA
#else
#define strcmpi lstrcmpiW
#endif

#endif
