const std = @import("std");

const root = @import("../root.zig");

const alloc = root.alloc;
const os_char = root.util.os_char;

const iter_proxy_funcs = std.mem.splitScalar(u8, @embedFile("proxy/proxylist.txt"), '\n');

var proxy_func_addrs = blk: {
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

    break :blk @as(@Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } }), undefined);
};

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

fn load_functions(dll: std.os.windows.HMODULE) void {
    inline for (comptime std.meta.fieldNames(@TypeOf(proxy_func_addrs))) |field| {
        @field(proxy_func_addrs, field) = std.os.windows.kernel32.GetProcAddress(dll, field).?;
    }
}

export fn load_proxy(module_path: [*:0]const os_char) void {
    const module_name = root.util.paths.getFileName(std.mem.span(module_path), true);

    const proxy_name = root.util.osStrLiteral("winhttp.dll");
    if (module_name.len == proxy_name.len) {
        var eq = true;
        for (module_name, proxy_name) |a, b| {
            if (a != b) {
                eq = false;
                break;
            }
        }
        if (eq) {
            root.logger.debug("Detected injection as supported proxy. Loading delegate.", .{});
        }
    }

    // includes null-terminator
    const sys_len = std.os.windows.kernel32.GetSystemDirectoryW(root.util.empty(u16), 0);
    const sys_full_path = alloc.allocSentinel(os_char, sys_len + proxy_name.len, 0) catch @panic("Out of memory");
    defer alloc.free(sys_full_path);
    const n = std.os.windows.kernel32.GetSystemDirectoryW(sys_full_path, sys_len);
    std.debug.assert(n == sys_len - 1);
    sys_full_path[sys_len] = std.fs.path.sep;
    @memcpy(sys_full_path[sys_len + 1 ..], proxy_name);

    root.logger.debug("Looking for delegate DLL at {s}", .{std.unicode.fmtUtf16Le(sys_full_path)});

    const handle = std.os.windows.LoadLibraryW(sys_full_path) catch |e| {
        std.debug.panic("Failed to load delegate DLL: {}", .{e});
    };

    load_functions(handle);
}
