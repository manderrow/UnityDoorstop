#ifndef LOGGING_H
#define LOGGING_H

#ifdef VERBOSE

#define LOG(message, ...) printf("[Doorstop] " message "\n", ##__VA_ARGS__)

#define ASSERT_F(test, message, ...)                                           \
    if (!(test)) {                                                             \
        printf("[Doorstop][Fatal] " message "\n", ##__VA_ARGS__);              \
        exit(1);                                                               \
    }

#define ASSERT(test, message)                                                  \
    if (!(test)) {                                                             \
        printf("[Doorstop][Fatal] " message "\n");                             \
        exit(1);                                                               \
    }

#define ASSERT_SOFT(test, ...)                                                 \
    if (!(test)) {                                                             \
        return __VA_ARGS__;                                                    \
    }

#else

/**
 * @brief Log a message in verbose mode
 */
#define LOG(message, ...)

#define ASSERT_F(test, message, ...)
#define ASSERT(test, message)
#define ASSERT_SOFT(test, ...)

#endif

#endif
