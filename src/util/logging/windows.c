#include <stdarg.h>
#include <stdio.h>

#include "../../windows/wincrt.h"
#include "../logging.h"

char *log_alloc_fallback(const char *message, va_list args, int cap) {
    char *buf = malloc(cap);

    int result = vsnprintf(buf, cap, message, args);

    va_end(args);

    if (result < 0) {
        log_err("error formatting log message (%s)", message);
        free(buf);
        return NULL;
    } else if (result > cap) {
        log_err("error formatting log message: buffer too small "
                "again?! (%s)",
                message);
        free(buf);
        return NULL;
    } else {
        return buf;
    }
}

#define LOG_FN(f)                                                              \
    void log_##f(const char *message, ...) {                                   \
        va_list args;                                                          \
        va_start(args, message);                                               \
                                                                               \
        char short_buf[128];                                                   \
        /* one less than buffer size to guarantee null-termination */          \
        int result = vsnprintf(short_buf, 127, message, args);                 \
                                                                               \
        va_end(args);                                                          \
                                                                               \
        if (result < 0) {                                                      \
            log_err("error formatting log message (%s)", message);             \
        } else if (result > 127) { /* one less than buffer size, see above */  \
            va_start(args, message);                                           \
            char *buf = log_alloc_fallback(message, args, result);             \
            if (buf) {                                                         \
                free(buf);                                                     \
                log_##f##_msg(buf);                                            \
            }                                                                  \
        } else {                                                               \
            log_##f##_msg(short_buf);                                          \
        }                                                                      \
    }

LOG_FN(err);
LOG_FN(warn);
LOG_FN(info);
LOG_FN(debug);
