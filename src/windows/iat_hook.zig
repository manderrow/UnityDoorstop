const builtin = @import("builtin");
const std = @import("std");

const root = @import("../root.zig");
const logger = root.logger;

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
    const c = @cImport(@cInclude("windows/iat_hook.h"));
    if (!c.iat_hook(module, target_dll.ptr, target_dll.len, target_function, detour_function)) {
        return error.IatHookFailed;
    }
}

export fn s_sl_eql(a: [*:0]const u8, b: [*]const u8, b_len: usize) bool {
    return std.mem.eql(u8, std.mem.span(a), b[0..b_len]);
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

    try iatHook(module, "kernel32.dll", &std.os.windows.kernel32.GetProcAddress, &detour.detourGetProcAddress);

    const result = std.os.windows.kernel32.GetProcAddress(module, test_func_name) orelse {
        return std.os.windows.unexpectedError(std.os.windows.GetLastError());
    };
    try std.testing.expectEqual(test_func_addr, @intFromPtr(result));
}
