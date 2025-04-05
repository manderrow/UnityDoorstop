const builtin = @import("builtin");
const std = @import("std");

const root = @import("../root.zig");
const logger = root.logger;

fn RVA2PTRBase(comptime T: type) type {
    return comptime if (@typeInfo(T).pointer.is_const) *const anyopaque else *anyopaque;
}

fn RVA2PTRBytes(comptime T: type) type {
    return comptime if (@typeInfo(T).pointer.is_const) [*]const u8 else [*]u8;
}

/// PE format uses RVAs (Relative Virtual Addresses) to save addresses relative
/// to the base of the module More info:
/// https://en.wikibooks.org/wiki/X86_Disassembly/Windows_Executable_Files#Relative_Virtual_Addressing_(RVA)
///
/// This helper macro converts the saved RVA to a fully valid pointer to the data
/// in the PE file
fn RVA2PTR(comptime T: type, base: RVA2PTRBase(T), rva: usize) T {
    return @ptrCast(@alignCast(@as(RVA2PTRBytes(T), @ptrCast(base)) + rva));
}

const winnt = struct {
    pub const IMAGE_DOS_HEADER = extern struct {
        e_magic: u16,
        e_cblp: u16,
        e_cp: u16,
        e_crlc: u16,
        e_cparhdr: u16,
        e_minalloc: u16,
        e_maxalloc: u16,
        e_ss: u16,
        e_sp: u16,
        e_csum: u16,
        e_ip: u16,
        e_cs: u16,
        e_lfarlc: u16,
        e_ovno: u16,
        e_res: [4]u16,
        e_oemid: u16,
        e_oeminfo: u16,
        e_res2: [10]u16,
        e_lfanew: i32,
    };

    pub const IMAGE_NT_HEADERS = extern struct {
        signature: u32,
        file_header: std.coff.CoffHeader,
        optional_header: OptionalHeader,

        pub const OptionalHeader = extern union {
            base: std.coff.OptionalHeader,
            pe32: std.coff.OptionalHeaderPE32,
            pe64: std.coff.OptionalHeaderPE64,
        };

        pub fn getNumberOfDataDirectories(self: *const @This()) u32 {
            return switch (self.optional_header.base.magic) {
                std.coff.IMAGE_NT_OPTIONAL_HDR32_MAGIC => self.optional_header.pe32.number_of_rva_and_sizes,
                std.coff.IMAGE_NT_OPTIONAL_HDR64_MAGIC => self.optional_header.pe64.number_of_rva_and_sizes,
                else => unreachable,
            };
        }

        pub fn getDataDirectories(self: *const @This()) []const std.coff.ImageDataDirectory {
            const size: usize = switch (self.optional_header.base.magic) {
                std.coff.IMAGE_NT_OPTIONAL_HDR32_MAGIC => @sizeOf(std.coff.OptionalHeaderPE32),
                std.coff.IMAGE_NT_OPTIONAL_HDR64_MAGIC => @sizeOf(std.coff.OptionalHeaderPE64),
                else => unreachable, // We assume we have validated the header already
            };
            const offset = @sizeOf(@This()) - @sizeOf(std.coff.OptionalHeader) + size;
            return RVA2PTR([*]const std.coff.ImageDataDirectory, self, offset)[0..self.getNumberOfDataDirectories()];
        }
    };
};

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
        nt.getDataDirectories()[@intFromEnum(std.coff.DirectoryEntry.IMPORT)].virtual_address,
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
