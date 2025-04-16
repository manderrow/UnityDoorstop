const builtin = @import("builtin");
const std = @import("std");

pub const Defn = struct {
    name: [:0]const u8,
    ret: type,
    params: []const Param,

    pub const Param = struct {
        name: [:0]const u8,
        type: type,
    };
};

pub fn defineFuncImportTable(comptime prefix: []const u8, comptime defns: []const Defn, comptime calling_convention: std.builtin.CallingConvention) type {
    comptime {
        const Type = std.builtin.Type;
        var fields: [defns.len]Type.StructField = undefined;
        for (defns, &fields) |defn, *field| {
            var params: [defn.params.len]Type.Fn.Param = undefined;
            for (defn.params, &params) |defn_param, *param| {
                param.* = .{
                    .type = defn_param.type,
                    .is_noalias = false,
                    .is_generic = false,
                };
            }
            const T = ?*const @Type(.{
                .@"fn" = Type.Fn{
                    .return_type = defn.ret,
                    .params = &params,
                    .is_var_args = false,
                    .is_generic = false,
                    .calling_convention = calling_convention,
                },
            });
            field.* = .{
                .name = defn.name,
                .type = T,
                .is_comptime = false,
                .default_value_ptr = @ptrCast(&@as(T, null)),
                .alignment = 0,
            };
        }
        const AddrTable = @Type(.{ .@"struct" = Type.Struct{
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
            .layout = .auto,
        } });

        return struct {
            pub var addrs: AddrTable = .{};

            pub fn load(lib: if (builtin.os.tag == .windows) std.os.windows.HMODULE else ?*anyopaque) void {
                inline for (defns) |defn| {
                    const name = prefix ++ defn.name;
                    const ptr = switch (builtin.os.tag) {
                        .windows => std.os.windows.kernel32.GetProcAddress(lib, name),
                        else => std.c.dlsym(lib, name),
                    };
                    @field(addrs, defn.name) = @ptrCast(@alignCast(ptr));
                }
            }
        };
    }
}
