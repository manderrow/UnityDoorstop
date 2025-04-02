const builtin = @import("builtin");

const table = @import("func_import.zig").defineFuncImportTable("coreclr_", &.{
    .{ .name = "initialize", .ret = i32, .params = &.{
        .{ .name = "exe_path", .type = [*:0]const u8 },
        .{ .name = "app_domain_friendly_name", .type = [*:0]const u8 },
        .{ .name = "property_count", .type = i32 },
        .{ .name = "property_keys", .type = [*]const [*:0]const u8 },
        .{ .name = "property_values", .type = [*]const [*:0]const u8 },
        .{ .name = "host_handle", .type = *?*anyopaque },
        .{ .name = "domain_id", .type = *u32 },
    } },
    .{ .name = "create_delegate", .ret = i32, .params = &.{
        .{ .name = "host_handle", .type = *anyopaque },
        .{ .name = "domain_id", .type = u32 },
        .{ .name = "entry_point_assembly_name", .type = [*:0]const u8 },
        .{ .name = "entry_point_type_name", .type = [*:0]const u8 },
        .{ .name = "entry_point_method_name", .type = [*:0]const u8 },
        .{ .name = "delegate", .type = *?*anyopaque },
    } },
}, if (builtin.os.tag == .windows) .{ .x86_stdcall = .{} } else .c);

pub const addrs = &table.addrs;
pub const load = table.load;
