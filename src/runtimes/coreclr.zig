const builtin = @import("builtin");
const std = @import("std");

const cc: std.builtin.CallingConvention = .c;

const table = @import("func_import.zig").defineFuncImportTable(
    "coreclr_",
    struct {
        initialize: fn (
            exe_path: [*:0]const u8,
            app_domain_friendly_name: [*:0]const u8,
            property_count: i32,
            property_keys: [*]const [*:0]const u8,
            property_values: [*]const [*:0]const u8,
            host_handle: *?*anyopaque,
            domain_id: *u32,
        ) callconv(cc) i32,
        create_delegate: fn (
            host_handle: *anyopaque,
            domain_id: u32,
            entry_point_assembly_name: [*:0]const u8,
            entry_point_type_name: [*:0]const u8,
            entry_point_method_name: [*:0]const u8,
            delegate: *?*anyopaque,
        ) callconv(cc) i32,
    },
);

pub const addrs = &table.addrs;
pub const load = table.load;
