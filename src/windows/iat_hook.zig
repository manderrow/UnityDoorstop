const builtin = @import("builtin");
const std = @import("std");

const root = @import("../root.zig");
const logger = root.logger;

/// PE format uses RVAs (Relative Virtual Addresses) to save addresses relative
/// to the base of the module More info:
/// https://en.wikibooks.org/wiki/X86_Disassembly/Windows_Executable_Files#Relative_Virtual_Addressing_(RVA)
///
/// This helper macro converts the saved RVA to a fully valid pointer to the data
/// in the PE file
inline fn RVA2PTR(comptime T: type, base: *anyopaque, rva: usize) T {
    return @ptrCast(@alignCast(@as([*]u8, @ptrCast(base)) + rva));
}

const winnt = @cImport({
    @cInclude("minwindef.h");
    @cInclude("winnt.h");
});

///
/// @brief Hooks the given function through the Import Address Table.
/// This is a simplified version that doesn't does lookup directly in the
/// initialized IAT.
/// This is usable to hook system DLLs like kernel32.dll assuming the process
/// wasn't already hooked.
///
/// @param dll Module to hook
/// @param target_dll Name of the target DLL to search in the IAT
/// @param target_function Address of the target function to hook
/// @param detour_function Address of the detour function
/// @return bool_t TRUE if successful, otherwise FALSE
///
pub fn iatHook(
    dll: std.os.windows.HMODULE,
    target_dll: [:0]const u8,
    target_function: anytype,
    detour_function: @TypeOf(target_function),
) !void {
    return iatHookUntyped(dll, target_dll, target_function, detour_function);
}

fn iatHookUntyped(
    dll: std.os.windows.HMODULE,
    target_dll: [:0]const u8,
    target_function: *anyopaque,
    detour_function: *anyopaque,
) !void {
    const mz: *winnt.IMAGE_DOS_HEADER = @alignCast(@ptrCast(dll));

    const nt = RVA2PTR(*winnt.IMAGE_NT_HEADERS, mz, @intCast(mz.e_lfanew));

    const imports = RVA2PTR(
        [*]std.coff.ImportDirectoryEntry,
        mz,
        @as(
            *const std.coff.ImageDataDirectory,
            @ptrCast(&nt.OptionalHeader.DataDirectory[@intFromEnum(std.coff.DirectoryEntry.IMPORT)]),
        ).virtual_address,
    );

    var i: usize = 0;
    while (imports[i].import_lookup_table_rva != 0) : (i += 1) {
        const name = RVA2PTR([*:0]const u8, mz, imports[i].name_rva);

        if (builtin.mode == .Debug) {
            logger.debug("import {s}:", .{name});
        }

        if (!std.mem.eql(u8, std.mem.span(name), target_dll)) {
            continue;
        }

        var thunks = RVA2PTR([*:null]?*anyopaque, mz, imports[i].import_address_table_rva);

        while (thunks[0]) |*thunk| : (thunks += 1) {
            const import = thunk.*;
            if (import != target_function)
                continue;

            if (builtin.mode == .Debug) {
                logger.debug("  matched {}", .{root.util.fmtAddress(import)});
            }

            var old_state: std.os.windows.DWORD = undefined;
            try std.os.windows.VirtualProtect(@as(*anyopaque, @ptrCast(thunk)), @sizeOf(@TypeOf(thunk)), std.os.windows.PAGE_READWRITE, &old_state);

            thunk.* = detour_function;

            std.os.windows.VirtualProtect(@as(*anyopaque, @ptrCast(thunk)), @sizeOf(@TypeOf(thunk)), old_state, &old_state) catch |e| {
                logger.warn("Failed to restore memory protection to thunk page: {}", .{e});
            };

            return;
        }
    }

    logger.warn("did not match {}", .{root.util.fmtAddress(target_function)});

    return error.NoMatch;
}
