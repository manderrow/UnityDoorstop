const logger = @import("../logging.zig").logger;

export fn log_err(msg: [*:0]const u8) void {
    logger.err("{s}", .{msg});
}

export fn log_warn(msg: [*:0]const u8) void {
    logger.warn("{s}", .{msg});
}

export fn log_info(msg: [*:0]const u8) void {
    logger.info("{s}", .{msg});
}

export fn log_debug(msg: [*:0]const u8) void {
    logger.debug("{s}", .{msg});
}
