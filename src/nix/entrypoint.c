#if defined(__APPLE__) || defined(__linux__)
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#endif

#include "../bootstrap.h"
#include "../config/config.h"
#include "../crt.h"
#include "../util/logging.h"
#include "../util/util.h"
#include "./plthook/plthook_ext.h"
#include "./plthook/vendor/plthook.h"

void capture_mono_path(void *handle) {
    char_t *result;
    get_module_path(handle, &result, NULL, 0);
    setenv(TEXT("DOORSTOP_MONO_LIB_PATH"), result, TRUE);
}

static bool_t initialized = FALSE;
void *dlsym_hook(void *handle, const char *name) {
#define REDIRECT_INIT(init_name, init_func, target, extra_init)                \
    if (!strcmp(name, init_name)) {                                            \
        if (!initialized) {                                                    \
            initialized = TRUE;                                                \
            init_func(handle);                                                 \
            extra_init;                                                        \
        }                                                                      \
        return (void *)target;                                                 \
    }

    // Resolve dnsym always so that it can be passed to capture_mono_path.
    // On Unix, we use dladdr which allows to use arbitrary symbols for
    // resolving their location.
    // However, using handle seems to cause issues on some distros, so we pass
    // the resolved symbol instead.
    void *res = dlsym(handle, name);
    REDIRECT_INIT("il2cpp_init", load_il2cpp_funcs, init_il2cpp, {});
    REDIRECT_INIT("mono_jit_init_version", load_mono_funcs, init_mono,
                  capture_mono_path(res));
    REDIRECT_INIT("mono_image_open_from_data_with_name", load_mono_funcs,
                  hook_mono_image_open_from_data_with_name,
                  capture_mono_path(res));
    REDIRECT_INIT("mono_jit_parse_options", load_mono_funcs,
                  hook_mono_jit_parse_options, capture_mono_path(res));
    REDIRECT_INIT("mono_debug_init", load_mono_funcs, hook_mono_debug_init,
                  capture_mono_path(res));

#undef REDIRECT_INIT
    return res;
}

int fclose_hook(FILE *stream) {
    // Some versions of Unity wrongly close stdout, which prevents writing
    // to console
    if (stream == stdout)
        return F_OK;
    return fclose(stream);
}

char_t *default_boot_config_path = NULL;
#if !defined(__APPLE__)
extern FILE *fopen64(const char *filename, const char *mode);

FILE *fopen64_hook(const char *filename, const char *mode) {
    const char *actual_file_name = filename;

    if (strcmp(filename, default_boot_config_path) == 0) {
        actual_file_name = config.boot_config_override;
        LOG("Overriding boot.config to %s", actual_file_name);
    }

    return fopen64(actual_file_name, mode);
}
#endif

FILE *fopen_hook(const char *filename, const char *mode) {
    const char *actual_file_name = filename;

    if (strcmp(filename, default_boot_config_path) == 0) {
        actual_file_name = config.boot_config_override;
        LOG("Overriding boot.config to %s", actual_file_name);
    }

    return fopen(actual_file_name, mode);
}

int dup2_hook(int od, int nd) {
    // Newer versions of Unity redirect stdout to player.log, we don't want
    // that
    if (nd == fileno(stdout) || nd == fileno(stderr))
        return F_OK;
    return dup2(od, nd);
}

__attribute__((constructor)) void doorstop_ctor() {
    if (IS_TEST)
        return;

    load_logger_config();

    log_info("Injecting");

    load_config();

    if (!config.enabled) {
        LOG("Doorstop not enabled! Skipping!");
        return;
    }

    plthook_t *hook = plthook_open_by_filename("UnityPlayer");

    if (hook) {
        LOG("Found UnityPlayer, hooking into it instead");
    } else if (plthook_open(&hook, NULL) != 0) {
        log_err("Failed to open current process PLT! Cannot run Doorstop! "
                "Error: %s",
                plthook_error());
        return;
    }

    if (plthook_replace(hook, "dlsym", &dlsym_hook, NULL) != 0)
        log_warn("Failed to hook dlsym, ignoring it. Error: %s",
                 plthook_error());

    if (config.boot_config_override) {
        if (file_exists(config.boot_config_override)) {
            default_boot_config_path = calloc(MAX_PATH, sizeof(char_t));
            memset(default_boot_config_path, 0, MAX_PATH * sizeof(char_t));
            strcat(default_boot_config_path, get_working_dir());
            strcat(default_boot_config_path, TEXT("/"));
            strcat(default_boot_config_path,
                   get_file_name(program_path(), FALSE));
            strcat(default_boot_config_path, TEXT("_Data/boot.config"));

#if !defined(__APPLE__)
            if (plthook_replace(hook, "fopen64", &fopen64_hook, NULL) != 0)
                log_warn("Failed to hook fopen64, ignoring it. Error: %s",
                         plthook_error());
#endif
            if (plthook_replace(hook, "fopen", &fopen_hook, NULL) != 0)
                log_warn("Failed to hook fopen, ignoring it. Error: %s",
                         plthook_error());
        } else {
            LOG("The boot.config file won't be overriden because the provided "
                "one does not exist: %s",
                config.boot_config_override);
        }
    }

    if (plthook_replace(hook, "fclose", &fclose_hook, NULL) != 0)
        log_warn("Failed to hook fclose, ignoring it. Error: %s",
                 plthook_error());

    if (plthook_replace(hook, "dup2", &dup2_hook, NULL) != 0)
        log_warn("Failed to hook dup2, ignoring it. Error: %s",
                 plthook_error());

#if defined(__APPLE__)
    /*
        On older Unity versions, Mono methods are resolved by the OS's
       loader directly. Because of this, there is no dlsym, in which case we
       need to apply a PLT hook.
    */
    if (plthook_replace(hook, "mono_jit_init_version", &init_mono, NULL) != 0)
        log_warn("Failed to hook jit_init_version, ignoring it. Error: %s",
                 plthook_error());
    else {
        void *mono_handle = plthook_handle_by_filename("libmono");
        if (mono_handle) {
            load_mono_funcs(mono_handle);
        }
    }
#endif

    plthook_close(hook);
}
