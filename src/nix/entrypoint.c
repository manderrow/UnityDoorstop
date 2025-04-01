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
#include "../hooks.h"
#include "../util/logging.h"
#include "../util/util.h"
#include "./plthook/plthook_ext.h"
#include "./plthook/vendor/plthook.h"

void *dlsym_hook(void *handle, const char *name);

int fclose_hook(FILE *stream);

#if !defined(__APPLE__)
FILE *fopen64_hook(const char *filename, const char *mode);
#endif

FILE *fopen_hook(const char *filename, const char *mode);

int dup2_hook(int oldfd, int newfd);

__attribute__((constructor)) void doorstop_ctor() {
    if (IS_TEST)
        return;

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
            initDefaultBootConfigPath();

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
