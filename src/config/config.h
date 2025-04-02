#ifndef CONFIG_H
#define CONFIG_H

#include <stdbool.h>

#include "../util/util.h"

extern const char_t *target_assembly;
extern const char_t *mono_dll_search_path_override;
extern bool mono_debug_enabled;
extern bool mono_debug_suspend;
extern const char_t *mono_debug_address;
extern const char_t *clr_runtime_coreclr_path;
extern const char_t *clr_corlib_dir;

#endif
