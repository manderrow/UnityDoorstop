#include <stdarg.h>
#include <stdio.h>

#define LOG_FN(f)                                                              \
    void log_##f(const char *message, ...) {                                   \
        fprintf(stderr, #f " doorstop ");                                      \
        va_list args;                                                          \
        va_start(args, message);                                               \
        vfprintf(stderr, message, args);                                       \
        va_end(args);                                                          \
        fprintf(stderr, "\n");                                                 \
    }

LOG_FN(err);
LOG_FN(warn);
LOG_FN(info);
LOG_FN(debug);
