const std = @import("std");

const root = @import("../root.zig");

const alloc = root.alloc;
const os_char = root.util.os_char;

var actual_dll: ?std.os.windows.HMODULE = null;

pub fn loadProxy(module_path: [*:0]const os_char) void {
    const module_name = root.util.paths.getFileName(os_char, std.mem.span(module_path), true);

    const proxy_name = root.util.osStrLiteral("winhttp.dll");
    if (module_name.len != proxy_name.len) return;

    var eq = true;
    for (module_name, proxy_name) |a, b| {
        if (a != b) {
            eq = false;
            break;
        }
    }
    if (!eq) {
        return;
    }

    root.logger.debug("Detected injection as proxy. Loading actual DLL.", .{});

    // includes null-terminator
    const sys_len = std.os.windows.kernel32.GetSystemDirectoryW(root.util.empty(u16), 0);
    const sys_full_path = alloc.allocSentinel(os_char, sys_len + proxy_name.len, 0) catch @panic("Out of memory");
    defer alloc.free(sys_full_path);
    const n = std.os.windows.kernel32.GetSystemDirectoryW(sys_full_path, sys_len);
    std.debug.assert(n == sys_len - 1);
    sys_full_path[sys_len] = std.fs.path.sep;
    @memcpy(sys_full_path[sys_len + 1 ..], proxy_name);

    root.logger.debug("Looking for actual DLL at {s}", .{std.unicode.fmtUtf16Le(sys_full_path)});

    actual_dll = std.os.windows.LoadLibraryW(sys_full_path) catch |e| {
        std.debug.panic("Failed to load actual DLL: {}", .{e});
    };

    root.logger.info("Proxy loaded", .{});
}

pub fn proxyGetProcAddress(module: std.os.windows.HMODULE, name: [:0]const u8) ?*anyopaque {
    if (module == root.entrypoint.windows.doorstop_module) {
        if (actual_dll) |dll| {
            return std.os.windows.kernel32.GetProcAddress(dll, name);
        }
    }

    return null;
}
