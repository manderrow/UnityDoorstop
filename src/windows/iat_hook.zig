const builtin = @import("builtin");
const std = @import("std");

const root = @import("../root.zig");
const logger = root.logger;

const winnt = @import("winnt.zig");

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

fn iatHookUntyped(
    module: std.os.windows.HMODULE,
    target_dll: [:0]const u8,
    target_function: *const anyopaque,
    detour_function: *const anyopaque,
) !void {
    const thunk = try getDllThunk(module, target_dll, target_function);
    try thunk.write(@constCast(detour_function));
}

fn getDllThunks(module: std.os.windows.HMODULE, target_dll: [:0]const u8) ?[*:null]const ?*anyopaque {
    const hdr = winnt.getDosHeader(module);

    const imports = hdr.getNtHeaders().getDataDirectory(hdr, .IMPORT);

    for (imports, 0..) |import, i| {
        if (import.name_rva == 0) {
            if (i != imports.len - 1) {
                logger.warn("  skipping import with null name_rva", .{});
            }
            break;
        }
        const name = winnt.resolveRva([*:0]const u8, hdr, import.name_rva);

        logger.debug("import {s}:", .{name});

        if (import.import_address_table_rva == 0) {
            logger.warn("  skipping import with null import_address_table_rva", .{});
            continue;
        }

        if (std.ascii.eqlIgnoreCase(std.mem.span(name), target_dll)) {
            return winnt.resolveRva([*:null]const ?*anyopaque, hdr, import.import_address_table_rva);
        }
    }

    return null;
}

fn Protected(comptime T: type) type {
    return struct {
        ptr: *const T,

        pub fn write(self: @This(), value: T) !void {
            const ptr = @constCast(self.ptr);

            var old_state: std.os.windows.DWORD = undefined;
            try std.os.windows.VirtualProtect(@ptrCast(ptr), @sizeOf(T), std.os.windows.PAGE_READWRITE, &old_state);

            ptr.* = value;

            std.os.windows.VirtualProtect(@ptrCast(ptr), @sizeOf(T), old_state, &old_state) catch |e| {
                logger.err("Failed to restore memory protection to protected page: {}", .{e});
            };
        }
    };
}

fn getDllThunk(module: std.os.windows.HMODULE, target_dll: [:0]const u8, target_function: *const anyopaque) !Protected(*const anyopaque) {
    var thunks = getDllThunks(module, target_dll) orelse return error.NoDllMatch;

    logger.debug("  searching for {}", .{root.util.fmtAddress(target_function)});

    while (thunks[0]) |*thunk| : (thunks += 1) {
        if (thunk.* == target_function) {
            logger.debug("    found {} in {}", .{ root.util.fmtAddress(target_function), root.util.fmtAddress(thunk) });
            return .{ .ptr = thunk };
        }
    }

    return error.NoFuncMatch;
}

test "getDllThunks" {
    logger.debug("foo bar baz", .{});

    const module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("test.exe")) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };

    _ = getDllThunks(module, "kernel32.dll") orelse return error.NoDllMatch;
}

test "getDllThunk non-existent dll" {
    const module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("test.exe")) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };

    const test_func_addr: usize = 0xF00F00F00F00;

    try std.testing.expectError(error.NoDllMatch, getDllThunk(module, "foobar.dll", @ptrFromInt(test_func_addr)));
}

test "getDllThunk non-existent function" {
    const module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("test.exe")) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };

    const test_func_addr: usize = 0xF00F00F00F00;

    try std.testing.expectError(error.NoFuncMatch, getDllThunk(module, "kernel32.dll", @ptrFromInt(test_func_addr)));
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

    {
        const kernel32 = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("kernel32")) orelse {
            return std.os.windows.unexpectedError(std.os.windows.GetLastError());
        };
        const result = std.os.windows.kernel32.GetProcAddress(kernel32, "GetProcAddress") orelse {
            return std.os.windows.unexpectedError(std.os.windows.GetLastError());
        };
        try iatHookUntyped(module, "kernel32.dll", result, &detour.detourGetProcAddress);
    }

    const result = std.os.windows.kernel32.GetProcAddress(module, test_func_name) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };
    try std.testing.expectEqual(test_func_addr, @intFromPtr(result));
}
