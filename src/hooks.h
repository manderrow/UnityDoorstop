#if _WIN32
void hookBootConfig(HMODULE module);
#else
#include "nix/plthook/vendor/plthook.h"

void hookBootConfig(plthook_t *hook);
#endif
