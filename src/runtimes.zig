const builtin = @import("builtin");

pub const coreclr = @cImport(@cInclude("runtimes/coreclr.h"));
pub const il2cpp = @cImport(@cInclude("runtimes/il2cpp.h"));

pub var coreclr_addrs: coreclr.coreclr_struct = .{};
pub var il2cpp_addrs: il2cpp.il2cpp_struct = .{};

comptime {
    @export(&coreclr_addrs, .{ .name = "coreclr" });
    @export(&il2cpp_addrs, .{ .name = "il2cpp" });

    _ = @import("runtimes/mono.zig");
}
