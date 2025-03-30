#ifndef LOGGING_H
#define LOGGING_H

void load_logger_config();

#define LOG_FN(f)                                                              \
    void log_##f(const char *message, ...)                                     \
        __attribute__((format(printf, 1, 2)));

LOG_FN(err);
LOG_FN(warn);
LOG_FN(info);
LOG_FN(debug);

#undef LOG_FN

#define LOG(message, ...) log_debug(message, ##__VA_ARGS__)

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
