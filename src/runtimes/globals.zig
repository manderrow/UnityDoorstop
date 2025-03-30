const builtin = @import("builtin");

const coreclr = @cImport(@cInclude("runtimes/coreclr.h"));
const il2cpp = @cImport(@cInclude("runtimes/il2cpp.h"));
const mono = @cImport(@cInclude("runtimes/mono.h"));

var coreclr_addrs: coreclr.coreclr_struct = .{};
var il2cpp_addrs: il2cpp.il2cpp_struct = .{};
var mono_addrs: mono.mono_struct = .{};

comptime {
    @export(&coreclr_addrs, .{ .name = "coreclr" });
    @export(&il2cpp_addrs, .{ .name = "il2cpp" });
    @export(&mono_addrs, .{ .name = "mono" });
}
