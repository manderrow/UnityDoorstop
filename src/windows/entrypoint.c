#include "../config/config.h"
#include "../crt.h"
#include "../hooks.h"
#include "../util/logging.h"
#include "paths.h"
#include "proxy/proxy.h"

#define LOG_FILE_CMD_START L" -logFile \""
#define LOG_FILE_CMD_START_LEN STR_LEN(LOG_FILE_CMD_START)
#define LOG_FILE_CMD_EXTRA 1024

#define LOG_FILE_CMD_END L"\\output_log.txt\""
#define LOG_FILE_CMD_END_LEN STR_LEN(LOG_FILE_CMD_END)

HANDLE stdout_handle;
HANDLE stderr_handle;
bool_t WINAPI close_handle_hook(void *handle);

HANDLE WINAPI create_file_hook(LPCWSTR lpFileName, DWORD dwDesiredAccess,
                               DWORD dwShareMode,
                               LPSECURITY_ATTRIBUTES lpSecurityAttributes,
                               DWORD dwCreationDisposition,
                               DWORD dwFlagsAndAttributes,
                               HANDLE hTemplateFile);

HANDLE WINAPI create_file_hook_narrow(
    LPSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode,
    LPSECURITY_ATTRIBUTES lpSecurityAttributes, DWORD dwCreationDisposition,
    DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);

void *WINAPI dlsym_hook(HMODULE module, char *name);

void inject(DoorstopPaths const *paths) {

    if (!config.enabled) {
        LOG("Doorstop disabled!");
        return;
    }

    LOG("Doorstop enabled!");
    HMODULE target_module = GetModuleHandle(TEXT("UnityPlayer"));
    HMODULE app_module = GetModuleHandle(NULL);

    if (!target_module) {
        LOG("No UnityPlayer module found! Using executable as the hook "
            "target.");
        target_module = app_module;
    }

    LOG("Installing IAT hooks");
    bool_t ok = TRUE;

#define HOOK_SYS(mod, from, to) ok &= iat_hook(mod, "kernel32.dll", &from, &to)

    installHooks(target_module);

#undef HOOK_SYS

    if (!ok) {
        log_err("Failed to install IAT hook!");
    } else {
        LOG("Hooks installed, marking DOORSTOP_DISABLE = TRUE");
        setenv(TEXT("DOORSTOP_DISABLE"), TEXT("TRUE"), TRUE);
    }
}

extern HMODULE doorstop_module;

BOOL WINAPI DllEntry(HINSTANCE hInstDll, DWORD reasonForDllLoad,
                     LPVOID reserved) {
    if (IS_TEST)
        return TRUE;

    doorstop_module = hInstDll;

    if (reasonForDllLoad == DLL_PROCESS_DETACH)
        SetEnvironmentVariableW(L"DOORSTOP_DISABLE", NULL);
    if (reasonForDllLoad != DLL_PROCESS_ATTACH)
        return TRUE;

    DoorstopPaths *paths = paths_init(hInstDll);

    stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);

    LOG("Standard output handle at %p", stdout_handle);
    char_t handle_path[MAX_PATH] = L"";
    GetFinalPathNameByHandle(stdout_handle, handle_path, MAX_PATH, 0);
    LOG("Standard output handle path: %" Ts, handle_path);

    load_proxy(paths->doorstop_path);
    LOG("Proxy loaded");

    load_config();
    LOG("Config loaded");

    if (!file_exists(config.target_assembly)) {
        LOG("Could not find target assembly!");
        config.enabled = FALSE;
    }

    inject(paths);

    paths_free(paths);

    return TRUE;
}
