const std = @import("std");

const root = @import("../root.zig");

const alloc = root.alloc;
const os_char = root.util.os_char;

pub var stdout_handle: ?std.os.windows.HANDLE = null;
pub var stderr_handle: ?std.os.windows.HANDLE = null;

pub extern "kernel32" fn CloseHandle(handle: std.os.windows.HANDLE) callconv(.winapi) i32;

pub fn close_handle_hook(handle: std.os.windows.HANDLE) callconv(.winapi) i32 {
    if (handle == stdout_handle or handle == stderr_handle)
        return 1;
    return @intFromBool(std.os.windows.ntdll.NtClose(handle) == .SUCCESS);
}

pub extern "kernel32" fn CreateFileA(
    lpFileName: std.os.windows.LPCSTR,
    dwDesiredAccess: std.os.windows.DWORD,
    dwShareMode: std.os.windows.DWORD,
    lpSecurityAttributes: ?*std.os.windows.SECURITY_ATTRIBUTES,
    dwCreationDisposition: std.os.windows.DWORD,
    dwFlagsAndAttributes: std.os.windows.DWORD,
    hTemplateFile: ?std.os.windows.HANDLE,
) callconv(.winapi) std.os.windows.HANDLE;

fn CreateFileFn(comptime char: type) type {
    return fn (
        lpFileName: [*:0]const char,
        dwDesiredAccess: std.os.windows.DWORD,
        dwShareMode: std.os.windows.DWORD,
        lpSecurityAttributes: ?*std.os.windows.SECURITY_ATTRIBUTES,
        dwCreationDisposition: std.os.windows.DWORD,
        dwFlagsAndAttributes: std.os.windows.DWORD,
        hTemplateFile: ?std.os.windows.HANDLE,
    ) callconv(.winapi) std.os.windows.HANDLE;
}

fn genCreateFileHook(comptime char: type, comptime real_fn: CreateFileFn(char)) CreateFileFn(char) {
    return struct {
        fn CreateFileHook(
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
                const boot_config_override = root.config.boot_config_override.?;
                root.logger.debug("Overriding boot.config to \"{s}\"", .{std.unicode.fmtUtf16Le(boot_config_override)});
                // caller can handle the error
                return std.os.windows.kernel32.CreateFileW(
                    boot_config_override,
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
    }.CreateFileHook;
}

pub const createFileWHook = genCreateFileHook(std.os.windows.WCHAR, std.os.windows.kernel32.CreateFileW);
pub const createFileAHook = genCreateFileHook(std.os.windows.CHAR, CreateFileA);
