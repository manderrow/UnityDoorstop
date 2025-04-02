#if _WIN32
void installHooks(HMODULE module);
#else
void installHooks();
#endif
