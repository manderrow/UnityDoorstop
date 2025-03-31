#ifndef LOGGING_H
#define LOGGING_H

void lockStdErr();
void unlockStdErr();

void log_lvl_msg(const char *level, const char *message, ...)
    __attribute__((format(printf, 2, 3)));

#define log_err(message, ...) log_lvl_msg("err", message, ##__VA_ARGS__)
#define log_warn(message, ...) log_lvl_msg("warn", message, ##__VA_ARGS__)
#define log_info(message, ...) log_lvl_msg("info", message, ##__VA_ARGS__)
#define log_debug(message, ...) log_lvl_msg("debug", message, ##__VA_ARGS__)

#define LOG log_debug

#define ASSERT_F(test, message, ...)                                           \
    if (!(test)) {                                                             \
        log_err(message, ##__VA_ARGS__);                                       \
        exit(1);                                                               \
    }

#define ASSERT(test, message)                                                  \
    if (!(test)) {                                                             \
        log_err(message);                                                      \
        exit(1);                                                               \
    }

#define ASSERT_SOFT(test, ...)                                                 \
    if (!(test)) {                                                             \
        return __VA_ARGS__;                                                    \
    }

#endif
