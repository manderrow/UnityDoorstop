const std = @import("std");

const root = @import("../root.zig");

const alloc = root.alloc;
const os_char = root.util.os_char;

const dll_name = "winhttp";

const iter_proxy_funcs = std.mem.splitScalar(u8, @embedFile("proxy/" ++ dll_name ++ ".txt"), '\n');

const ProxyFuncAddrs = blk: {
    @setEvalBranchQuota(8000);

    var fields: []const std.builtin.Type.StructField = &.{};

    var funcs = iter_proxy_funcs;
    while (funcs.next()) |name| {
        if (std.mem.indexOfScalar(u8, name, ' ') != null) {
            @compileError("proxy function name \"" ++ name ++ "\" contains whitespace");
        }
        fields = fields ++ .{std.builtin.Type.StructField{
            .name = @ptrCast(name ++ .{0}),
            .type = std.os.windows.FARPROC,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(std.os.windows.FARPROC),
        }};
    }

    break :blk @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
};

var proxy_func_addrs: ProxyFuncAddrs = undefined;

comptime {
    @setEvalBranchQuota(8000);
    var funcs = iter_proxy_funcs;
    while (funcs.next()) |name| {
        @export(&struct {
            fn f() callconv(.c) void {
                return @as(*fn () callconv(.c) void, @ptrCast(@field(proxy_func_addrs, name)))();
            }
        }.f, .{ .name = name });
    }
}

fn loadFunctions(dll: std.os.windows.HMODULE) void {
    inline for (comptime std.meta.fieldNames(ProxyFuncAddrs)) |field| {
        @field(proxy_func_addrs, field) = std.os.windows.kernel32.GetProcAddress(dll, field).?;
    }
}

fn eqlIgnoreCase(a: []const u16, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }
    for (a, b) |a_c16, b_c| {
        const a_c = std.math.cast(u8, a_c16) orelse return false;
        if (std.ascii.toLower(a_c) != b_c) {
            return false;
        }
    }
    return true;
}

pub fn loadProxy(module_path: [:0]const os_char) void {
    const module_name = root.util.paths.getFileName(os_char, module_path, true);

    const proxy_name = dll_name ++ ".dll";
    if (!eqlIgnoreCase(module_name, proxy_name)) {
        return;
    }
    root.logger.debug("Detected injection as supported proxy. Loading actual.", .{});

    // includes null-terminator
    const sys_len = std.os.windows.kernel32.GetSystemDirectoryW(root.util.empty(u16), 0);
    const sys_full_path = alloc.allocSentinel(os_char, sys_len + 1 + module_name.len, 0) catch @panic("Out of memory");
    defer alloc.free(sys_full_path);
    const n = std.os.windows.kernel32.GetSystemDirectoryW(sys_full_path, sys_len);
    std.debug.assert(n == sys_len - 1);
    sys_full_path[sys_len] = std.fs.path.sep;
    @memcpy(sys_full_path[sys_len + 1 ..], module_name);

    root.logger.debug("Looking for actual DLL at {s}", .{std.unicode.fmtUtf16Le(sys_full_path)});

    const handle = std.os.windows.LoadLibraryW(sys_full_path) catch |e| {
        std.debug.panic("Failed to load actual DLL: {}", .{e});
    };

    loadFunctions(handle);
}
