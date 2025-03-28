#ifndef CONFIG_H
#define CONFIG_H

#include <stdbool.h>

#include "../util/util.h"

/**
 * @brief Doorstop configuration
 */
typedef struct {
    /**
     * @brief Whether Doorstop is enabled (enables hooking methods and executing
     * target assembly).
     */
    bool enabled;

    /**
     * @brief Whether to redirect Unity output log.
     *
     * If enabled, Doorstop will append `-logFile` command line argument to
     * process command line arguments. This will force Unity to write output
     * logs to the game folder.
     */
    bool redirect_output_log;

    /**
     * @brief Whether to ignore DOORSTOP_DISABLE.
     *
     * If enabled, Doorstop will ignore DOORSTOP_DISABLE environment variable.
     * This is sometimes useful with Steam games that break env var isolation.
     */
    bool ignore_disabled_env;

    /**
     * @brief Path to a managed assembly to invoke.
     */
    const char_t *target_assembly;

    /**
     * @brief Path to a custom boot.config file to use. If enabled, this file
     * takes precedence over the default one in the Data folder.
     */
    const char_t *boot_config_override;

    /**
     * @brief Path to use as the main DLL search path. If enabled, this folder
     * takes precedence over the default Managed folder.
     */
    const char_t *mono_dll_search_path_override;

    /**
     * @brief Whether to enable the mono debugger.
     */
    bool mono_debug_enabled;

    /**
     * @brief Whether to enable the debugger in suspended state.
     *
     * If enabled, the runtime will force the game to wait until a debugger is
     * connected.
     */
    bool mono_debug_suspend;

    /**
     * @brief Debug address to use for the mono debugger.
     */
    const char_t *mono_debug_address;

    /**
     * @brief Path to the CoreCLR runtime library.
     */
    const char_t *clr_runtime_coreclr_path;

    /**
     * @brief Path to the CoreCLR core libraries folder.
     */
    const char_t *clr_corlib_dir;
} Config;

extern Config config;

/**
 * @brief Load configuration.
 */
void load_config();

/**
 * @brief Clean up configuration.
 */
void cleanup_config();
#endif
