#ifndef LOGGING_H
#define LOGGING_H

extern void load_logger_config();

#ifdef _WIN32

extern void log_err(const char *message);
extern void log_warn(const char *message);
extern void log_info(const char *message);
extern void log_debug(const char *message);

#define LOG_L(f, message, ...)                                                 \
    {                                                                          \
        char message_buf[128];                                                 \
        int result = snprintf(&message_buf, 128, message, ##__VA_ARGS__);      \
        if (result < 0) {                                                      \
            log_err("error formatting log message");                           \
        } else if (result > 128) {                                             \
            int cap = result;                                                  \
            char *big_buf = malloc(cap);                                       \
            result = snprintf(&message_buf, cap, message, ##__VA_ARGS__);      \
            if (result < 0) {                                                  \
                log_err("error formatting log message");                       \
            } else if (result > cap) {                                         \
                log_err("error formatting log message: buffer too small "      \
                        "again?!");                                            \
            } else {                                                           \
                f(big_buf);                                                    \
            }                                                                  \
            free(big_buf);                                                     \
        } else {                                                               \
            f(message_buf);                                                    \
        }                                                                      \
    }

#define LOG(message, ...) LOG_L(log_debug, message, ##__VA_ARGS__)

#define ASSERT_F(test, message, ...)                                           \
    if (!(test)) {                                                             \
        LOG_L(log_err, message, ##__VA_ARGS__);                                \
        exit(1);                                                               \
    }

#else

extern void log_err(const char *message, ...);
extern void log_warn(const char *message, ...);
extern void log_info(const char *message, ...);
extern void log_debug(const char *message, ...);

#define LOG(message, ...) log_debug(message, ##__VA_ARGS__)

#define ASSERT_F(test, message, ...)                                           \
    if (!(test)) {                                                             \
        log_err(message, ##__VA_ARGS__);                                       \
        exit(1);                                                               \
    }

#endif

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
