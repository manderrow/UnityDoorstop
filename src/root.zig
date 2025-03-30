const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const logging = @import("util/logging.zig");

pub const alloc = std.heap.smp_allocator;

pub const std_options = std.Options{
    .log_level = std.log.Level.debug,
    .logFn = logging.log,
};

comptime {
    _ = @import("config.zig");
    _ = logging;
    _ = @import("runtimes/globals.zig");
    if (builtin.os.tag == .windows) {
        _ = @import("windows/proxy/proxy.zig");
    }
    if (builtin.os.tag != .windows) {
        _ = @import("nix/plthook/plthook_ext.zig");
    }
}
