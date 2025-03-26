const builtin = @import("builtin");
const std = @import("std");

const alloc = @import("../root.zig").alloc;

pub const logger = std.log.scoped(.doorstop);

export fn load_logger_config() callconv(.c) enum(u8) {
    ok = 1,
    err = 0,
} {
    const log_mode_str = std.process.getEnvVarOwned(alloc, "DOORSTOP_LOG_MODE") catch |e| switch (e) {
        error.EnvironmentVariableNotFound => return .ok,
        else => {
            logger.err("Error loading logger config: {}", .{e});
            return .err;
        },
    };
    log_mode = std.StaticStringMap(LogMode).initComptime(.{
        .{ "text", .text },
        // .{ "json", .json },
    }).get(log_mode_str) orelse {
        logger.err("Unrecognized logger mode: {s}", .{log_mode_str});
        return .err;
    };
    return .ok;
}

const LogMode = enum {
    text,
    // json,
};

pub var log_mode: LogMode = .text;

// fn JsonStringEscapingWriter(comptime Writer: type) type {
//     return struct {
//         delegate: Writer,

//         const WriteError = @typeInfo(@typeInfo(@TypeOf(write)).@"fn".return_type.?).error_union.error_set;

//         pub fn write(self: @This(), bytes: []const u8) !usize {
//             try std.json.encodeJsonStringChars(bytes, .{}, self.delegate);
//             return bytes.len;
//         }

//         pub fn writer(self: @This()) std.io.GenericWriter(@This(), WriteError, write) {
//             return .{ .context = self };
//         }
//     };
// }

// fn jsonStringEscapingWriter(writer: anytype) JsonStringEscapingWriter(@TypeOf(writer)) {
//     return .{ .delegate = writer };
// }

pub fn log(comptime message_level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
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
                writer.print(level_txt ++ " " ++ scope_txt ++ " " ++ format ++ "\n", args) catch return;
            },
            // .json => {
            //     var stream = std.json.writeStream(writer, .{});
            //     stream.beginObject() catch return;
            //     stream.objectFieldRaw("\"level\"") catch return;
            //     stream.write(message_level) catch return;
            //     stream.objectFieldRaw("\"scope\"") catch return;
            //     stream.write(scope) catch return;
            //     stream.objectFieldRaw("\"message\"") catch return;
            //     stream.beginWriteRaw() catch return;
            //     stream.stream.writeByte('"') catch return;
            //     std.fmt.format(jsonStringEscapingWriter(stream.stream).writer(), format, args) catch return;
            //     stream.stream.writeByte('"') catch return;
            //     stream.endWriteRaw();
            //     stream.endObject() catch return;
            // },
        }
        bw.flush() catch return;
    }
}

comptime {
    _ = switch (builtin.os.tag) {
        .windows => @import("logging/windows.zig"),
        else => @import("logging/default.zig"),
    };
}
