const std = @import("std");

const root = @import("../root.zig");

const alloc = root.alloc;
const os_char = root.util.os_char;

extern var stdout_handle: ?std.os.windows.HANDLE;
extern var stderr_handle: ?std.os.windows.HANDLE;
export fn close_handle_hook(handle: std.os.windows.HANDLE) callconv(.winapi) root.util.c_bool {
    if (handle == stdout_handle)
        return .true;
    return @enumFromInt(@intFromBool(std.os.windows.ntdll.NtClose(handle) == .SUCCESS));
}

extern "kernel32" fn CreateFileA(
    lpFileName: std.os.windows.LPCSTR,
    dwDesiredAccess: std.os.windows.DWORD,
    dwShareMode: std.os.windows.DWORD,
    lpSecurityAttributes: ?*std.os.windows.SECURITY_ATTRIBUTES,
    dwCreationDisposition: std.os.windows.DWORD,
    dwFlagsAndAttributes: std.os.windows.DWORD,
    hTemplateFile: ?std.os.windows.HANDLE,
) callconv(.winapi) std.os.windows.HANDLE;

fn create_file_hook(comptime char: type, comptime real_fn: fn (
    lpFileName: [*:0]const char,
    dwDesiredAccess: std.os.windows.DWORD,
    dwShareMode: std.os.windows.DWORD,
    lpSecurityAttributes: ?*std.os.windows.SECURITY_ATTRIBUTES,
    dwCreationDisposition: std.os.windows.DWORD,
    dwFlagsAndAttributes: std.os.windows.DWORD,
    hTemplateFile: ?std.os.windows.HANDLE,
) callconv(.winapi) std.os.windows.HANDLE) *const anyopaque {
    return struct {
        fn create_file_hook(
            lpFileName: [*:0]const char,
            dwDesiredAccess: std.os.windows.DWORD,
            dwShareMode: std.os.windows.DWORD,
            lpSecurityAttributes: ?*std.os.windows.SECURITY_ATTRIBUTES,
            dwCreationDisposition: std.os.windows.DWORD,
            dwFlagsAndAttributes: std.os.windows.DWORD,
            hTemplateFile: ?std.os.windows.HANDLE,
        ) callconv(.winapi) std.os.windows.HANDLE {
            const handle = real_fn(
                lpFileName,
                dwDesiredAccess,
                dwShareMode,
                lpSecurityAttributes,
                dwCreationDisposition,
                dwFlagsAndAttributes,
                hTemplateFile,
            );
            if (handle == std.os.windows.INVALID_HANDLE_VALUE) {
                // caller can handle the error
                return handle;
            }

            const id = root.util.file_identity.getFileIdentity(handle, &.{}) catch |e| {
                root.logger.err("Failed to get identity of file \"{s}\": {}", .{ switch (char) {
                    u8 => lpFileName,
                    u16 => std.unicode.fmtUtf16Le(std.mem.span(lpFileName)),
                    else => comptime unreachable,
                }, e });
                return handle;
            };

            if (root.util.file_identity.are_same(id, root.hooks.defaultBootConfig)) {
                std.os.windows.CloseHandle(handle);
                root.logger.debug("Overriding boot.config to \"{s}\"", .{std.unicode.fmtUtf16Le(std.mem.span(root.config.boot_config_override))});
                // caller can handle the error
                return std.os.windows.kernel32.CreateFileW(
                    root.config.boot_config_override,
                    dwDesiredAccess,
                    dwShareMode,
                    lpSecurityAttributes,
                    dwCreationDisposition,
                    dwFlagsAndAttributes,
                    hTemplateFile,
                );
            }

            return handle;
        }
    }.create_file_hook;
}

comptime {
    @export(&create_file_hook(std.os.windows.WCHAR, std.os.windows.kernel32.CreateFileW), .{ .name = "create_file_hook" });
    @export(&create_file_hook(std.os.windows.CHAR, CreateFileA), .{ .name = "create_file_hook_narrow" });
}
