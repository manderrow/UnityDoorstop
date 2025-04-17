/*
 * IAT hooking for Windows.
 *
 * More IAT/EAT hooking methods at
 * https://gist.github.com/denikson/93ea22c1f4e79e68466a26cbfc58af05
 */

#ifndef HOOK_H
#define HOOK_H

#include <stdbool.h>
#include <stdint.h>
#include <windows.h>

#include "../util/logging.h"

bool s_sl_eql(const char *a, const char *b, uintptr_t b_len);

// PE format uses RVAs (Relative Virtual Addresses) to save addresses relative
// to the base of the module More info:
// https://en.wikibooks.org/wiki/X86_Disassembly/Windows_Executable_Files#Relative_Virtual_Addressing_(RVA)
//
// This helper macro converts the saved RVA to a fully valid pointer to the data
// in the PE file
#define RVA2PTR(t, base, rva) ((t)(((PCHAR)(base)) + (rva)))

/**
 * @brief Hooks the given function through the Import Address Table.
 * This is a simplified version that doesn't does lookup directly in the
 * initialized IAT.
 * This is usable to hook system DLLs like kernel32.dll assuming the process
 * wasn't already hooked.
 *
 * @param dll Module to hook
 * @param target_dll Name of the target DLL to search in the IAT
 * @param target_function Address of the target function to hook
 * @param detour_function Address of the detour function
 * @return bool_t TRUE if successful, otherwise FALSE
 */
static bool iat_hook(void *dll, char const *target_dll,
                     uintptr_t target_dll_len, const void *target_function,
                     const void *detour_function) {
  IMAGE_DOS_HEADER *mz = (PIMAGE_DOS_HEADER)dll;

  IMAGE_NT_HEADERS *nt = RVA2PTR(PIMAGE_NT_HEADERS, mz, mz->e_lfanew);

  IMAGE_IMPORT_DESCRIPTOR *imports =
      RVA2PTR(IMAGE_IMPORT_DESCRIPTOR *, mz,
              nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT]
                  .VirtualAddress);

  for (int i = 0; imports[i].Characteristics; i++) {
    char *name = RVA2PTR(char *, mz, imports[i].Name);

    log_warn("import %s:", name);

    if (!s_sl_eql(name, target_dll, target_dll_len))
      continue;

    void **thunk = RVA2PTR(void **, mz, imports[i].FirstThunk);

    for (; *thunk; thunk++) {
      void *import = *thunk;

      if (import != target_function) {
        log_warn("  skipped 0x%p", import);
        continue;
      }

      log_warn("  matched 0x%p", import);

      DWORD old_state;
      if (!VirtualProtect(thunk, sizeof(void *), PAGE_READWRITE, &old_state))
        return false;

      *thunk = (void *)detour_function;

      VirtualProtect(thunk, sizeof(void *), old_state, &old_state);

      return true;
    }
  }

  log_warn("did not match 0x%p", target_function);

  return false;
}

#endif
