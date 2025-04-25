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

pub fn defineFuncImportTable(comptime prefix: []const u8, comptime defns: type) type {
    comptime {
        const Type = std.builtin.Type;
        const defns_fields = @typeInfo(defns).@"struct".fields;
        var fields: [defns_fields.len]Type.StructField = undefined;
        for (defns_fields, &fields) |defn, *field| {
            const T = ?*const defn.type;
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
                inline for (defns_fields) |defn| {
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
