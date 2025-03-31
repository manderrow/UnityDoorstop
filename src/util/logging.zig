const builtin = @import("builtin");
const std = @import("std");

const alloc = @import("../root.zig").alloc;

pub const logger = std.log.scoped(.doorstop);

export fn lockStdErr() void {
    std.debug.lockStdErr();
}

export fn unlockStdErr() void {
    std.debug.unlockStdErr();
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime @tagName(message_level);
    const scope_txt = comptime @tagName(scope);
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(
            level_txt ++ " " ++ scope_txt ++ " " ++ format ++ "\n",
            args,
        ) catch return;
        bw.flush() catch return;
    }
}
