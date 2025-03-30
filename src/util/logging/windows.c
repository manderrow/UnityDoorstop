#include <stdarg.h>
#include <stdio.h>

#define LOG_FN(f)                                                              \
    void log_##f(const char *message, ...) {                                   \
        va_list args;                                                          \
        va_start(args, message);                                               \
        fprintf(stderr, #f " doorstop ");                                      \
        vfprintf(stderr, message, args);                                       \
        va_end(args);                                                          \
    }

LOG_FN(err);
LOG_FN(warn);
LOG_FN(info);
LOG_FN(debug);
