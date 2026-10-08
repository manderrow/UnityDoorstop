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
        var field_names: [defns_fields.len][]const u8 = undefined;
        var field_types: [defns_fields.len]type = undefined;
        var field_attrs: [defns_fields.len]Type.Struct.FieldAttributes = undefined;
        for (defns_fields, &field_names, &field_types, &field_attrs) |defn, *fname, *ftype, *fattrs| {
            const T = ?*const defn.type;
            fname.* = defn.name;
            ftype.* = T;
            fattrs.* = .{
                .@"comptime" = false,
                .@"align" = null,
                .default_value_ptr = @ptrCast(&@as(T, null)),
            };
        }
        const AddrTable = @Struct(.{
            .layout = .auto,
            .BackingInt = null,
            .field_names = &field_names,
            .field_types = &field_types,
            .field_attrs = &field_attrs,
        });

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
