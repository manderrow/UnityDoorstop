#include "vendor/plthook.h"

#if defined(__APPLE__)
void *plthook_handle_by_filename(const char *name);
#endif

plthook_t *plthook_open_by_filename(const char *name);
