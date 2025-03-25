const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const windows_proxy = if (builtin.os.tag == .windows) @import("windows/proxy/proxy.zig");

comptime {
    _ = windows_proxy;
}
