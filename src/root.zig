const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

pub const alloc = std.heap.smp_allocator;

pub const config = &@import("config.zig").config;
pub const hooks = @import("hooks.zig");
const logging = @import("util/logging.zig");
pub const util = @import("util.zig");

pub const logger = logging.logger;

pub const std_options = std.Options{
    .log_level = std.log.Level.debug,
    .logFn = logging.log,
};

comptime {
    _ = config;
    _ = hooks;
    _ = @import("runtimes.zig");
    _ = util;
    _ = logging;
    _ = @import("util/paths.zig");
    if (builtin.os.tag == .windows) {
        _ = @import("windows/paths.zig");
        _ = @import("windows/proxy.zig");
    }
    if (builtin.os.tag != .windows) {
        _ = @import("nix/plthook_ext.zig");
    }
}
