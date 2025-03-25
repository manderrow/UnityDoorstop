const builtin = @import("builtin");
const std = @import("std");

pub const logger = std.log.scoped(.doorstop);

comptime {
    _ = switch (builtin.os.tag) {
        .windows => @import("logging/windows.zig"),
        else => @import("logging/default.zig"),
    };
}
