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

int fclose_hook(FILE *stream);

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

    installHooks(hook);

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
