const logger = @import("../logging.zig").logger;

fn log(
    comptime f: fn (comptime format: []const u8, args: anytype) void,
    msg: [*:0]const u8,
) void {
    f("{s}", .{msg});
}

export fn log_err_msg(msg: [*:0]const u8) void {
    log(logger.err, msg);
}

export fn log_warn_msg(msg: [*:0]const u8) void {
    log(logger.warn, msg);
}

export fn log_info_msg(msg: [*:0]const u8) void {
    log(logger.info, msg);
}

export fn log_debug_msg(msg: [*:0]const u8) void {
    log(logger.debug, msg);
}
