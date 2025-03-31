const std = @import("std");

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

export fn load_functions(dll: std.os.windows.HMODULE) void {
    inline for (comptime std.meta.fieldNames(@TypeOf(proxy_func_addrs))) |field| {
        @field(proxy_func_addrs, field) = std.os.windows.kernel32.GetProcAddress(dll, field).?;
    }
}
