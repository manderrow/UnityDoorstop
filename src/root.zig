const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

pub const std_options = std.Options{
    .log_level = std.log.Level.debug,
};

const logging = @import("util/logging.zig");
const windows_proxy = if (builtin.os.tag == .windows) @import("windows/proxy/proxy.zig");

comptime {
    _ = logging;
    _ = windows_proxy;
}
