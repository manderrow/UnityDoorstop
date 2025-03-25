#include <dlfcn.h>

extern int dladdr1(const void *addr, Dl_info *info, void **extra_info,
                   int flags);

static int RTLD_DL_LINKMAP = 2;
