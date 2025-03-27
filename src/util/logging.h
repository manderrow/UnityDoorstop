#ifndef LOGGING_H
#define LOGGING_H

void load_logger_config();

#ifdef _WIN32

#define LOG_FN(f)                                                              \
    void log_##f##_msg(const char *message);                                   \
    void log_##f(const char *message, ...);

LOG_FN(err);
LOG_FN(warn);
LOG_FN(info);
LOG_FN(debug);

#undef LOG_FN

#else

void log_err(const char *message, ...);
void log_warn(const char *message, ...);
void log_info(const char *message, ...);
void log_debug(const char *message, ...);

#endif

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
