#include <stdarg.h>
#include <stdio.h>

#include "logging.h"

void log_lvl_msg(const char *level, const char *message, ...) {
    lockStdErr();

    fprintf(stderr, "%s doorstop ", level);
    va_list args;
    va_start(args, message);
    vfprintf(stderr, message, args);
    va_end(args);
    fprintf(stderr, "\n");

    unlockStdErr();
}
