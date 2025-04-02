const table = @import("func_import.zig").defineFuncImportTable("il2cpp_", &.{
    .{ .name = "init", .ret = i32, .params = &.{
        .{ .name = "domain_name", .type = [*:0]const u8 },
    } },
    .{ .name = "runtime_invoke", .ret = i32, .params = &.{
        .{ .name = "method", .type = *anyopaque },
        .{ .name = "obj", .type = ?*anyopaque },
        .{ .name = "params", .type = *?*anyopaque },
        .{ .name = "exec", .type = *?*anyopaque },
    } },
    .{ .name = "method_get_name", .ret = [*:0]const u8, .params = &.{
        .{ .name = "method", .type = *anyopaque },
    } },
}, .c);

pub const addrs = &table.addrs;
pub const load = table.load;
