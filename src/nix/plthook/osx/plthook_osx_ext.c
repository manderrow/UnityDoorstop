#include "mach-o_fixup-chains.h"

#include "../vendor/plthook_osx.c"

void *plthook_handle_by_name(const char *name) {
    void *mono_handle = NULL;
    uint32_t cnt = _dyld_image_count();
    for (uint32_t idx = 0; idx < cnt; idx++) {
        const char *image_name = idx ? _dyld_get_image_name(idx) : NULL;
        if (image_name && strstr(image_name, name)) {
            mono_handle = dlopen(image_name, RTLD_LAZY | RTLD_NOLOAD);
            return mono_handle;
        }
    }
    return NULL;
}
