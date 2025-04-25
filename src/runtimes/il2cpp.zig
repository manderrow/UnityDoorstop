const std = @import("std");

const cc: std.builtin.CallingConvention = .c;

const table = @import("func_import.zig").defineFuncImportTable("il2cpp_", struct {
    init: fn (domain_name: [*:0]const u8) callconv(cc) i32,
    runtime_invoke: fn (
        method: *anyopaque,
        obj: ?*anyopaque,
        params: *?*anyopaque,
        exec: *?*anyopaque,
    ) callconv(cc) i32,
    method_get_name: fn (method: *anyopaque) callconv(cc) [*:0]const u8,
});

pub const addrs = &table.addrs;
pub const load = table.load;
