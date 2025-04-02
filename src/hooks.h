#if _WIN32
void installHooks(HMODULE module);
#else
#include "nix/plthook/vendor/plthook.h"

void installHooks(plthook_t *hook);
#endif
