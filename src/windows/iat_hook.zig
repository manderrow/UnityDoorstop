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

        pub fn getDataDirectories(self: *const @This()) []const std.coff.ImageDataDirectory {
            const number_of_rva_and_sizes_ptr: [*]const u32 = @ptrCast(switch (self.optional_header.base.magic) {
                std.coff.IMAGE_NT_OPTIONAL_HDR32_MAGIC => &self.optional_header.pe32.number_of_rva_and_sizes,
                std.coff.IMAGE_NT_OPTIONAL_HDR64_MAGIC => &self.optional_header.pe64.number_of_rva_and_sizes,
                else => unreachable, // We assume we get a valid header from Windows
            });
            return @as([*]const std.coff.ImageDataDirectory, @ptrCast(number_of_rva_and_sizes_ptr + 1))[0..number_of_rva_and_sizes_ptr[0]];
        }

        pub fn getDataDirectoryRaw(self: *const @This(), base: *IMAGE_DOS_HEADER, id: std.coff.DirectoryEntry) []const u8 {
            const entry = self.getDataDirectories()[@intFromEnum(id)];
            const ptr = RVA2PTR([*]const u8, base, entry.virtual_address);
            return ptr[0..entry.size];
        }

        pub fn GetDataDirectory(comptime id: std.coff.DirectoryEntry) type {
            return switch (id) {
                .IMPORT => std.coff.ImportDirectoryEntry,
                else => @compileError("Unsupported name " ++ @tagName(id)),
            };
        }

        pub fn getDataDirectory(self: *const @This(), base: *IMAGE_DOS_HEADER, comptime id: std.coff.DirectoryEntry) []const GetDataDirectory(id) {
            const T = GetDataDirectory(id);
            const raw = self.getDataDirectoryRaw(base, id);
            return @as([*]const T, @ptrCast(@alignCast(raw.ptr)))[0..@divExact(raw.len, @sizeOf(T))];
        }
    };
};

/// Hooks the given function through the Import Address Table.
/// This is a simplified version that doesn't does lookup directly in the
/// initialized IAT.
/// This is usable to hook system DLLs like kernel32.dll assuming the process
/// wasn't already hooked.
///
/// - *module* is the module to hook
/// - *target_dll* is the name of the target DLL to search in the IAT
/// - *target_function* is the address of the target function to hook
/// - *detour_function* is the address of the detour function
///
pub fn iatHook(
    module: std.os.windows.HMODULE,
    target_dll: [:0]const u8,
    target_function: anytype,
    detour_function: @TypeOf(target_function),
) !void {
    return iatHookUntyped(module, target_dll, target_function, detour_function);
}

fn getDosHeader(module: std.os.windows.HMODULE) *winnt.IMAGE_DOS_HEADER {
    return @alignCast(@ptrCast(module));
}

fn isKnownDirectoryEntry(id: std.coff.DirectoryEntry) bool {
    inline for (std.meta.tags(@TypeOf(id))) |tag| {
        if (id == tag) return true;
    }
    return false;
}

fn getDllThunks(module: std.os.windows.HMODULE, target_dll: [:0]const u8) ?[*:null]const ?*anyopaque {
    const mz = getDosHeader(module);

    const nt = RVA2PTR(*winnt.IMAGE_NT_HEADERS, mz, @intCast(mz.e_lfanew));

    if (builtin.is_test) {
        logger.warn("{X}", .{nt.file_header.time_date_stamp});
        for (nt.getDataDirectories(), 0..) |dir, i| {
            const max_name_len = @tagName(std.coff.DirectoryEntry.COM_DESCRIPTOR).len;
            const name = std.meta.intToEnum(std.coff.DirectoryEntry, i) catch unreachable;
            logger.warn(
                std.fmt.comptimePrint("{{?s:<{}}} ({{x:0>4}})    rva: {{x:0>8}}    size: {{x:0>8}}", .{max_name_len}),
                .{ if (isKnownDirectoryEntry(name)) @tagName(name) else null, @intFromEnum(name), dir.virtual_address, dir.size },
            );
        }

        logger.warn("done looking at directories", .{});
    }

    const imports = nt.getDataDirectory(mz, .IMPORT);

    if (builtin.is_test) {
        logger.warn("found {} imports", .{imports.len});
    }

    for (imports) |import| {
        if (import.import_lookup_table_rva == 0) {
            // we should be at the end now, but just continue anyway
            continue;
        }
        const name = RVA2PTR([*:0]const u8, mz, import.name_rva);

        if (builtin.mode == .Debug) {
            if (builtin.is_test) {
                logger.warn("import {} {s}:", .{ import, name });
            } else {
                logger.debug("import {s}:", .{name});
            }
        }

        if (import.import_address_table_rva == 0) {
            if (builtin.is_test) {
                logger.warn("  skipping import with null import_address_table_rva", .{});
            }
            continue;
        }

        if (std.ascii.eqlIgnoreCase(std.mem.span(name), target_dll)) {
            return RVA2PTR([*:null]const ?*anyopaque, mz, import.import_address_table_rva);
        }
    }

    return null;
}

const Thunk = struct {
    ptr: *const *anyopaque,

    pub fn write(self: Thunk, target: *anyopaque) !void {
        var old_state: std.os.windows.DWORD = undefined;
        const ptr = @as(*anyopaque, @constCast(@ptrCast(self.ptr)));
        const dwSize = @sizeOf(@TypeOf(self.ptr));
        try std.os.windows.VirtualProtect(ptr, dwSize, std.os.windows.PAGE_READWRITE, &old_state);

        @constCast(self.ptr).* = target;

        std.os.windows.VirtualProtect(ptr, dwSize, old_state, &old_state) catch |e| {
            logger.warn("Failed to restore memory protection to thunk page: {}", .{e});
        };
    }
};

fn getDllThunk(
    module: std.os.windows.HMODULE,
    target_dll: [:0]const u8,
    target_function: *const anyopaque,
) !Thunk {
    var thunks = getDllThunks(module, target_dll) orelse return error.NoDllMatch;

    logger.warn("  searching for {}", .{root.util.fmtAddress(target_function)});

    while (thunks[0]) |*thunk| : (thunks += 1) {
        const import = thunk.*;
        if (import != target_function) {
            if (builtin.is_test) {
                logger.warn("  skipping {} in {}", .{ root.util.fmtAddress(import), root.util.fmtAddress(thunk) });
            }
            continue;
        }

        if (builtin.mode == .Debug) {
            logger.debug("  matched {} in {}", .{ root.util.fmtAddress(import), root.util.fmtAddress(thunk) });
        }

        return .{ .ptr = thunk };
    }

    return error.NoFuncMatch;
}

fn iatHookUntyped(
    module: std.os.windows.HMODULE,
    target_dll: [:0]const u8,
    target_function: *const anyopaque,
    detour_function: *const anyopaque,
) !void {
    const thunk = getDllThunk(module, target_dll, target_function) catch |e| switch (e) {
        error.NoDllMatch => {
            logger.warn("did not match DLL {s}", .{target_dll});
            return e;
        },
        error.NoFuncMatch => {
            logger.warn("did not match function {}", .{root.util.fmtAddress(target_function)});
            return e;
        },
        else => return e,
    };

    try thunk.write(@constCast(detour_function));
}

test "iatHook" {
    const module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("test.exe")) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };

    const test_func_name = "test iathook";
    const test_func_addr: usize = 0xF00F00F00F00;

    const detour = struct {
        var actual: ?@TypeOf(&std.os.windows.kernel32.GetProcAddress) = null;

        fn detourGetProcAddress(
            hModule: std.os.windows.HMODULE,
            lpProcName: std.os.windows.LPCSTR,
        ) callconv(.winapi) ?std.os.windows.FARPROC {
            if (std.mem.eql(u8, std.mem.span(lpProcName), test_func_name)) {
                return @ptrFromInt(test_func_addr);
            }
            return actual.?(hModule, lpProcName);
        }
    };

    const thunk = try getDllThunk(module, "kernel32.dll", &std.os.windows.kernel32.GetProcAddress);
    detour.actual = @ptrCast(@alignCast(thunk.ptr.*));

    try thunk.write(@constCast(&detour.detourGetProcAddress));

    const result = std.os.windows.kernel32.GetProcAddress(module, test_func_name) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };
    try std.testing.expectEqual(test_func_addr, @intFromPtr(result));
}

test "getDllThunk non-existent dll" {
    const module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("test.exe")) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };

    const test_func_addr: usize = 0xF00F00F00F00;

    try std.testing.expectError(error.NoDllMatch, getDllThunk(module, "foobar.dll", @ptrFromInt(test_func_addr)));
}

test "getDllThunks" {
    logger.debug("foo bar baz", .{});

    const module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("test.exe")) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };

    _ = getDllThunks(module, "kernel32.dll") orelse return error.NoDllMatch;
}

test "getDllThunk non-existent function" {
    const module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("test.exe")) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };

    const test_func_addr: usize = 0xF00F00F00F00;

    try std.testing.expectError(error.NoFuncMatch, getDllThunk(module, "kernel32.dll", @ptrFromInt(test_func_addr)));
}
