#include "dlfcn_extra.h"
#include "link_extra.h"

#include "../vendor/plthook_elf.c"

struct handle_by_name_helper {
    const char *find_name;
    void *result;
};

int proc_handles(struct dl_phdr_info *info, size_t size, void *data) {
    struct handle_by_name_helper *result = (struct handle_by_name_helper *)data;

    if (result->result)
        return 1;

    if (info->dlpi_name && strstr(info->dlpi_name, result->find_name)) {
        result->result = (void *)info->dlpi_addr;
        return 1;
    }
    return 0;
}

void *plthook_handle_by_name(const char *name) {
    struct handle_by_name_helper result = {name, NULL};
    dl_iterate_phdr(&proc_handles, &result);
    return result.result;
}
