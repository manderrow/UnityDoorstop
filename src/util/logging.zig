const builtin = @import("builtin");
const std = @import("std");

const alloc = @import("../root.zig").alloc;

pub const logger = std.log.scoped(.doorstop);

export fn load_logger_config() enum(u8) {
    ok = 1,
    err = 0,
} {
    const log_mode_str = std.process.getEnvVarOwned(
        alloc,
        "DOORSTOP_LOG_MODE",
    ) catch |e| switch (e) {
        error.EnvironmentVariableNotFound => return .ok,
        else => {
            logger.err("Error loading logger config: {}", .{e});
            return .err;
        },
    };
    log_mode = std.StaticStringMap(LogMode).initComptime(.{
        .{ "text", .text },
    }).get(log_mode_str) orelse {
        logger.err("Unrecognized logger mode: {s}", .{log_mode_str});
        return .err;
    };
    return .ok;
}

const LogMode = enum {
    text,
};

pub var log_mode: LogMode = .text;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const scope_txt = comptime @tagName(scope);
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        switch (log_mode) {
            .text => {
                writer.print(
                    level_txt ++ " " ++ scope_txt ++ " " ++ format ++ "\n",
                    args,
                ) catch return;
            },
        }
        bw.flush() catch return;
    }
}

comptime {
    _ = switch (builtin.os.tag) {
        // Zig currently does not support defining variadic callconv(.c) functions, so
        // we use a fallback implementation that formats in C instead.
        .windows => @import("logging/windows.zig"),
        else => @import("logging/default.zig"),
    };
}
