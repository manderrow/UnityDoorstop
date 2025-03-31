#ifndef CRT_H
#define CRT_H

#include <stddef.h>

extern void *malloc_custom(size_t size);
extern void *calloc_custom(size_t num, size_t size);
extern void free_custom(void *mem);

#define malloc malloc_custom
#define calloc calloc_custom
#define free free_custom

#if _WIN32
#include "windows/wincrt.h"
// Better default to account for longer name support
#undef MAX_PATH
#define MAX_PATH 1024

#if _WIN64
#define ENV64
#else
#define ENV32
#endif

#define TSTR(t) L##t
#define Ts "ls"

#elif defined(__APPLE__) || defined(__linux__)
#define _GNU_SOURCE
#include <dlfcn.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define TSTR(t) t
#define Ts "s"

#define strlen_narrow strlen

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

#if __x86_64__ || __ppc64__
#define ENV64
#else
#define ENV32
#endif

#define MAX_PATH PATH_MAX

#endif

#endif
