const builtin = @import("builtin");
const std = @import("std");

const alloc = @import("../root.zig").alloc;

pub const logger = std.log.scoped(.doorstop);

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime @tagName(message_level);
    const scope_txt = comptime @tagName(scope);
    var buf: [4096]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buf);

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.interface.print(
            level_txt ++ " " ++ scope_txt ++ " " ++ format ++ "\n",
            args,
        ) catch return;
        writer.interface.flush() catch return;
    }
}
