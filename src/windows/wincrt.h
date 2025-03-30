/*
 * Custom implementation for common C runtime functions
 * This makes the DLL essentially freestanding on Windows without having to rely
 * on msvcrt.dll
 */
#ifndef WIN_CRT_H
#define WIN_CRT_H

#include "../util/util.h"
#include <windows.h>

// Fix for MinGW's headers
#ifdef UNICODE
#undef GetFinalPathNameByHandle
#define GetFinalPathNameByHandle GetFinalPathNameByHandleW
#else
#undef GetFinalPathNameByHandle
#define GetFinalPathNameByHandle GetFinalPathNameByHandleA
#endif

extern void init_crt();

#define STR_LEN(str) (sizeof(str) / sizeof((str)[0]))

extern void *memset(void *dst, int c, size_t n);

extern void *memcpy(void *dst, const void *src, size_t n);

#ifdef UNICODE
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused"
static size_t strlen_wide(const char_t *str) { return wcslen(str) * 2; }
static size_t strlen_narrow(const char *str) { return strlen(str); }
#pragma clang diagnostic pop
#define strlen strlen_wide
#endif

extern void *malloc(size_t size);

extern void *calloc(size_t num, size_t size);

extern char_t *strcat_wide(char_t *dst, const char_t *src);
#define strcat strcat_wide

extern char_t *strcpy_wide(char_t *dst, const char_t *src);
#define strcpy strcpy_wide

extern char_t *strncpy_wide(char_t *dst, const char_t *src, size_t len);
#define strncpy strncpy_wide

extern void *dlsym(void *handle, const char *name);

#define RTLD_LAZY 0x00001

extern void *dlopen(const char_t *filename, int flag);

extern void free(void *mem);

extern int setenv(const char_t *name, const char_t *value, int overwrite);
extern char_t *getenv_wide(const char_t *name);
#define getenv getenv_wide

#ifndef UNICODE
#define CommandLineToArgv CommandLineToArgvA
extern LPSTR *CommandLineToArgvA(LPCSTR cmd_line, int *argc);

#define strcmpi lstrcmpiA
#else
#define CommandLineToArgv CommandLineToArgvW
#define strcmpi lstrcmpiW
#endif

#endif
