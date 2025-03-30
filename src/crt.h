#ifndef CRT_H
#define CRT_H

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

void *fopen_custom(const char_t *filename, const char_t *mode);
size_t fread_custom(void *ptr, size_t size, size_t count, void *stream);
int fclose_custom(void *stream);

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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused"
static void *fopen_custom(const char *filename, const char *mode) {
    return fopen(filename, mode);
}

static size_t fread_custom(void *ptr, size_t size, size_t count, void *stream) {
    return fread(ptr, size, count, stream);
}

static int fclose_custom(void *stream) { return fclose(stream); }
#pragma clang diagnostic pop

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
