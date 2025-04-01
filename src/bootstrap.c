#if defined(__APPLE__) || defined(__linux__)
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#endif

#include "bootstrap.h"
#include "config/config.h"
#include "crt.h"
#include "runtimes/coreclr.h"
#include "runtimes/il2cpp.h"
#include "runtimes/mono.h"
#include "util/logging.h"
#include "util/util.h"

bool_t mono_debug_init_called = FALSE;
bool_t mono_is_net35 = FALSE;

void mono_doorstop_bootstrap(void *mono_domain) {
    if (getenv(TEXT("DOORSTOP_INITIALIZED"))) {
        LOG("DOORSTOP_INITIALIZED is set! Skipping!");
        return;
    }
    setenv(TEXT("DOORSTOP_INITIALIZED"), TEXT("TRUE"), TRUE);

    mono.thread_set_main(mono.thread_current());

    char_t *app_path = program_path();
    if (mono.domain_set_config) {
#define CONFIG_EXT TEXT(".config")
        char_t *config_path =
            calloc(strlen(app_path) + 1 + STR_LEN(CONFIG_EXT), sizeof(char_t));
        strcpy(config_path, app_path);
        strcat(config_path, CONFIG_EXT);
        char_t *folder_path = get_folder_name(app_path);

        char *config_path_n = narrow(config_path);
        char *folder_path_n = narrow(folder_path);
        free(folder_path);
        free(config_path);

        LOG("Setting config paths: base dir: %s; config path: %s",
            folder_path_n, config_path_n);

        mono.domain_set_config(mono_domain, folder_path_n, config_path_n);

        free(config_path_n);
        free(folder_path_n);
#undef CONFIG_EXT
    }

    setenv(TEXT("DOORSTOP_INVOKE_DLL_PATH"), config.target_assembly, TRUE);
    setenv(TEXT("DOORSTOP_PROCESS_PATH"), app_path, TRUE);
    free(app_path);

    char *assembly_dir = mono.assembly_getrootdir();
    char_t *norm_assembly_dir = widen(assembly_dir);

    mono.config_parse(NULL);

    LOG("Assembly dir: %" Ts, norm_assembly_dir);
    setenv(TEXT("DOORSTOP_MANAGED_FOLDER_DIR"), norm_assembly_dir, TRUE);
    free(norm_assembly_dir);

    LOG("Opening assembly: %" Ts, config.target_assembly);

    char *dll_path = narrow(config.target_assembly);
    void *image;
    {
        MonoImageOpenFileStatus s = (MonoImageOpenFileStatus)MONO_IMAGE_OK;
        image = mono_image_open_from_file_with_name(config.target_assembly, &s,
                                                    FALSE, dll_path);
        if (s != (MonoImageOpenFileStatus)MONO_IMAGE_OK) {
            log_err("Failed to open assembly image: %" Ts ". Got result: %d",
                    config.target_assembly, s);
            return;
        }
    }

    LOG("Image opened; loading included assembly");

    MonoImageOpenStatus s = MONO_IMAGE_OK;
    mono.assembly_load_from_full(image, dll_path, &s, FALSE);
    free(dll_path);
    if (s != MONO_IMAGE_OK) {
        log_err("Failed to load assembly: %" Ts ". Got result: %d",
                config.target_assembly, s);
        return;
    }

    LOG("Assembly loaded; looking for Doorstop.Entrypoint:Start");
    void *desc = mono.method_desc_new("Doorstop.Entrypoint:Start", TRUE);
    void *method = mono.method_desc_search_in_image(desc, image);
    mono.method_desc_free(desc);
    if (!method) {
        log_err("Failed to find method Doorstop.Entrypoint:Start");
        return;
    }

    void *signature = mono.method_signature(method);
    unsigned int params = mono.signature_get_param_count(signature);
    if (params != 0) {
        log_err("Method has %d parameters; expected 0", params);
        return;
    }

    LOG("Invoking method %p", method);
    void *exc = NULL;
    mono.runtime_invoke(method, NULL, NULL, &exc);
    if (exc != NULL) {
        log_err("Error invoking code!");
        if (mono.object_to_string) {
            void *str = mono.object_to_string(exc, NULL);
            char *exc_str = mono.string_to_utf8(str);
            log_err("Error message: %s", exc_str);
        }
    }
    LOG("Done");
}

void *init_mono(const char *root_domain_name, const char *runtime_version) {
    LOG("Starting mono domain \"%s\"", root_domain_name);
    LOG("Runtime version: %s", runtime_version);
    if (runtime_version[0] != 0 && runtime_version[1] != 0 &&
        (runtime_version[1] == '2' || runtime_version[1] == '1')) {
        mono_is_net35 = TRUE;
    }
    char *root_dir_n = mono.assembly_getrootdir();
    char_t *root_dir = widen(root_dir_n);
    LOG("Current root: %s", root_dir_n);

    LOG("Overriding mono DLL search path");

    size_t mono_search_path_len = strlen(root_dir) + 1;

    char_t *override_dir_full = NULL;
    const char_t *config_path_value = config.mono_dll_search_path_override;
    bool_t has_override = config_path_value && strlen(config_path_value);
    if (has_override) {
        size_t path_start = 0;
        override_dir_full = calloc(MAX_PATH, sizeof(char_t));

        bool_t found_path = FALSE;
        for (size_t i = 0; i <= strlen(config_path_value); i++) {
            char_t current_char = config_path_value[i];
            if (current_char == *PATH_SEP || current_char == 0) {
                if (i <= path_start) {
                    path_start++;
                    continue;
                }

                size_t path_len = i - path_start;
                char_t *path = calloc(path_len + 1, sizeof(char_t));
                strncpy(path, config_path_value + path_start, path_len);
                path[path_len] = 0;

                char_t *full_path = get_full_path(path);

                if (strlen(override_dir_full) + strlen(full_path) + 2 >
                    MAX_PATH) {
                    log_warn("Ignoring this root path because its absolute "
                             "version is too long: %" Ts,
                             full_path);
                    free(path);
                    free(full_path);
                    path_start = i + 1;
                    continue;
                }

                if (found_path) {
                    strcat(override_dir_full, PATH_SEP);
                }

                strcat(override_dir_full, full_path);
                LOG("Adding root path: %" Ts, full_path);

                free(path);
                free(full_path);

                found_path = TRUE;
                path_start = i + 1;
            }
        }

        mono_search_path_len += strlen(override_dir_full) + 1;
    }

    char_t *mono_search_path = calloc(mono_search_path_len + 1, sizeof(char_t));
    if (override_dir_full && strlen(override_dir_full)) {
        strcat(mono_search_path, override_dir_full);
        strcat(mono_search_path, PATH_SEP);
    }
    strcat(mono_search_path, root_dir);

    LOG("Mono search path: %" Ts, mono_search_path);
    char *mono_search_path_n = narrow(mono_search_path);
    mono.set_assemblies_path(mono_search_path_n);
    setenv(TEXT("DOORSTOP_DLL_SEARCH_DIRS"), mono_search_path, TRUE);
    free(mono_search_path);
    free(mono_search_path_n);
    if (override_dir_full) {
        free(override_dir_full);
    }

    hook_mono_jit_parse_options(0, NULL);

    bool_t debugger_already_enabled = mono_debug_init_called;
    if (mono.debug_enabled) {
        debugger_already_enabled |= mono.debug_enabled();
    }

    void *domain = NULL;
    if (config.mono_debug_enabled && !debugger_already_enabled) {
        LOG("Detected mono debugger is not initialized; initializing it");
        mono.debug_init(MONO_DEBUG_FORMAT_MONO);
    }
    domain = mono.jit_init_version(root_domain_name, runtime_version);

    mono_doorstop_bootstrap(domain);

    return domain;
}

void il2cpp_doorstop_bootstrap() {
    if (!config.clr_corlib_dir || !config.clr_runtime_coreclr_path) {
        LOG("No CoreCLR paths set, skipping loading");
        return;
    }

    LOG("CoreCLR runtime path: %" Ts, config.clr_runtime_coreclr_path);
    LOG("CoreCLR corlib dir: %" Ts, config.clr_corlib_dir);

    if (!file_exists(config.clr_runtime_coreclr_path) ||
        !folder_exists(config.clr_corlib_dir)) {
        LOG("CoreCLR startup dirs are not set up skipping invoking Doorstop");
        return;
    }

    void *coreclr_module = dlopen(config.clr_runtime_coreclr_path, RTLD_LAZY);
    LOG("Loaded coreclr.dll: %p", coreclr_module);
    if (!coreclr_module) {
        LOG("Failed to load CoreCLR runtime!");
        return;
    }

    load_coreclr_funcs(coreclr_module);

    char_t *app_path = program_path();
    char *app_path_n = narrow(app_path);

    char_t *target_dir = get_folder_name(config.target_assembly);
    char_t *target_name = get_file_name(config.target_assembly, FALSE);
    char *target_name_n = narrow(target_name);

    char_t *app_paths_env =
        calloc(strlen(config.clr_corlib_dir) + 1 + strlen(target_dir) + 1,
               sizeof(char_t));
    strcat(app_paths_env, config.clr_corlib_dir);
    strcat(app_paths_env, PATH_SEP);
    strcat(app_paths_env, target_dir);
    const char *app_paths_env_n = narrow(app_paths_env);

    LOG("App path: %" Ts, app_path);
    LOG("Target dir: %" Ts, target_dir);
    LOG("Target name: %" Ts, target_name);
    LOG("APP_PATHS: %" Ts, app_paths_env);

    const char *props = "APP_PATHS";

    setenv(TEXT("DOORSTOP_INITIALIZED"), TEXT("TRUE"), TRUE);
    setenv(TEXT("DOORSTOP_INVOKE_DLL_PATH"), config.target_assembly, TRUE);
    setenv(TEXT("DOORSTOP_MANAGED_FOLDER_DIR"), config.clr_corlib_dir, TRUE);
    setenv(TEXT("DOORSTOP_PROCESS_PATH"), app_path, TRUE);
    setenv(TEXT("DOORSTOP_DLL_SEARCH_DIRS"), app_paths_env, TRUE);

    void *host = NULL;
    unsigned int domain_id = 0;
    int result = coreclr.initialize(app_path_n, "Doorstop Domain", 1, &props,
                                    &app_paths_env_n, &host, &domain_id);
    if (result != 0) {
        LOG("Failed to initialize CoreCLR: 0x%08x", result);
        return;
    }

    void (*startup)() = NULL;
    result = coreclr.create_delegate(host, domain_id, target_name_n,
                                     "Doorstop.Entrypoint", "Start",
                                     (void **)&startup);
    if (result != 0) {
        LOG("Failed to get entrypoint delegate: 0x%08x", result);
        return;
    }

    LOG("Invoking Doorstop.Entrypoint.Start()");
    startup();
}

int init_il2cpp(const char *domain_name) {
    LOG("Starting IL2CPP domain \"%s\"", domain_name);
    const int orig_result = il2cpp.init(domain_name);
    il2cpp_doorstop_bootstrap();
    return orig_result;
}

#define MONO_DEBUG_ARG_START                                                   \
    TEXT("--debugger-agent=transport=dt_socket,server=y,address=")
#define MONO_DEBUG_NO_SUSPEND TEXT(",suspend=n")
#define MONO_DEBUG_NO_SUSPEND_NET35 TEXT(",suspend=n,defer=y")

void hook_mono_jit_parse_options(int argc, char **argv) {
    char_t *debug_options = getenv(TEXT("DNSPY_UNITY_DBG2"));
    if (debug_options) {
        config.mono_debug_enabled = TRUE;
    }

    if (config.mono_debug_enabled) {
        LOG("Configuring mono debug server");

        int size = argc + 1;
        char **new_argv = calloc(size, sizeof(char *));
        memcpy(new_argv, argv, argc * sizeof(char *));

        const char_t *mono_debug_address = config.mono_debug_address;
        if (!mono_debug_address) {
            mono_debug_address = TSTR("127.0.0.1:10000");
        }
        size_t debug_args_len =
            STR_LEN(MONO_DEBUG_ARG_START) + strlen(mono_debug_address);
        if (!config.mono_debug_suspend) {
            if (mono_is_net35) {
                debug_args_len += STR_LEN(MONO_DEBUG_NO_SUSPEND_NET35);
            } else {
                debug_args_len += STR_LEN(MONO_DEBUG_NO_SUSPEND);
            }
        }

        if (!debug_options) {
            debug_options = calloc(debug_args_len + 1, sizeof(char_t));
            strcat(debug_options, MONO_DEBUG_ARG_START);
            strcat(debug_options, mono_debug_address);
            if (!config.mono_debug_suspend) {
                if (mono_is_net35) {
                    strcat(debug_options, MONO_DEBUG_NO_SUSPEND_NET35);
                } else {
                    strcat(debug_options, MONO_DEBUG_NO_SUSPEND);
                }
            }
        }

        LOG("Debug options: %" Ts, debug_options);

        char *debug_options_n = narrow(debug_options);
        new_argv[argc] = debug_options_n;
        mono.jit_parse_options(size, new_argv);

        free(debug_options);
        free(debug_options_n);
        free(new_argv);
    } else {
        mono.jit_parse_options(argc, argv);
    }
}

void *hook_mono_image_open_from_data_with_name(void *data,
                                               unsigned long data_len,
                                               int need_copy,
                                               MonoImageOpenStatus *status,
                                               int refonly, const char *name) {
    void *result = NULL;
    if (config.mono_dll_search_path_override) {
        char_t *name_wide = widen(name);
        char_t *name_file = get_file_name(name_wide, TRUE);
        free(name_wide);

        size_t name_file_len = strlen(name_file);
        size_t bcl_root_len = strlen(config.mono_dll_search_path_override);

        char_t *new_full_path =
            calloc(name_file_len + bcl_root_len + 2, sizeof(char_t));
        strcat(new_full_path, config.mono_dll_search_path_override);
        strcat(new_full_path, TEXT("/"));
        strcat(new_full_path, name_file);

        MonoImageOpenFileStatus attemptStatus =
            (MonoImageOpenFileStatus)*status;
        result = mono_image_open_from_file_with_name(
            new_full_path, &attemptStatus, refonly, name);
        if (attemptStatus != (MonoImageOpenFileStatus)MONO_IMAGE_OK &&
            attemptStatus != MONO_IMAGE_FILE_NOT_FOUND) {
            log_err("Failed to load overridden Mono image: Error code %d",
                    attemptStatus);

            if (attemptStatus > 0) {
                *status = (MonoImageOpenStatus)attemptStatus;
                return NULL;
            }

            switch (attemptStatus) {
            case MONO_IMAGE_FILE_NOT_FOUND:
                __builtin_unreachable();
            case MONO_IMAGE_FILE_ERROR:
                // not sure what is the best way to adapt this error
                *status = MONO_IMAGE_IMAGE_INVALID;
                break;
            }
            return NULL;
        }
        free(new_full_path);
    }

    if (!result) {
        result = mono.image_open_from_data_with_name(data, data_len, need_copy,
                                                     status, refonly, name);
    }
    return result;
}

void hook_mono_debug_init(MonoDebugFormat format) {
    mono_debug_init_called = TRUE;
    mono.debug_init(format);
}
