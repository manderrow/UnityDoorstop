const std = @import("std");

const root = @import("../root.zig");

const alloc = root.alloc;
const os_char = root.util.os_char;

// TODO: use GetFileInformationByHandleEx to compare the files with absolute certainty instead comparing paths.

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

fn create_file_hook(comptime char: type) *const anyopaque {
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
            const normalized_path = switch (char) {
                os_char => alloc.dupeZ(os_char, std.mem.span(lpFileName)) catch @panic("Out of memory"),
                u8 => std.unicode.utf8ToUtf16LeAllocZ(alloc, std.mem.span(lpFileName)) catch |e| switch (e) {
                    error.OutOfMemory => @panic("Out of memory"),
                    error.InvalidUtf8 => @panic("Invalid ASCII provided to CreateFileA"),
                },
                else => @compileError("Unexpected char type: " ++ @typeName(char)),
            };

            defer alloc.free(normalized_path);
            for (normalized_path) |*c| {
                if (c.* == '/') {
                    c.* = '\\';
                }
            }

            var open_path: [*:0]const u16 = normalized_path.ptr;

            if (std.mem.eql(os_char, normalized_path, root.hooks.defaultBootConfigPath)) {
                open_path = root.config.boot_config_override;
                root.logger.debug("Overriding boot.config to {s}", .{std.unicode.fmtUtf16Le(std.mem.span(open_path))});
            }

            return std.os.windows.kernel32.CreateFileW(
                open_path,
                dwDesiredAccess,
                dwShareMode,
                lpSecurityAttributes,
                dwCreationDisposition,
                dwFlagsAndAttributes,
                hTemplateFile,
            );
        }
    }.create_file_hook;
}

comptime {
    @export(&create_file_hook(std.os.windows.WCHAR), .{ .name = "create_file_hook" });
    @export(&create_file_hook(std.os.windows.CHAR), .{ .name = "create_file_hook_narrow" });
}
