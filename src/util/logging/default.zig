const std = @import("std");

const logger = @import("../logging.zig").logger;

const CFmtFormatter = struct {
    fmt: [*:0]const u8,
    args: std.builtin.VaList,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (fmt.len != 0) @compileError("Unrecognized format specifier: " ++ fmt);
        // FIXME: this constCast is bad
        var args = @cVaCopy(@constCast(&self.args));
        var iter = std.mem.splitScalar(u8, std.mem.span(self.fmt), '%');
        try writer.writeAll(iter.first());
        while (iter.next()) |chunkIn| {
            var chunk = chunkIn;
            if (chunk.len == 0) {
                chunk = iter.next() orelse return error.InvalidCFormatString;
                try writer.writeByte('%');
            } else {
                switch (chunk[0]) {
                    's' => {
                        const s = @cVaArg(&args, [*:0]const u8);
                        try writer.writeAll(std.mem.span(s));
                    },
                    'l' => {
                        if (chunk.len < 2) {
                            return error.InvalidCFormatString;
                        }
                        switch (chunk[1]) {
                            's' => {
                                const s = @cVaArg(&args, [*:0]const u16);
                                try writer.print("{}", .{std.unicode.fmtUtf16Le(std.mem.span(s))});
                            },
                            else => return error.UnrecognizedCFormatSpecifier,
                        }
                    },
                    'd' => {
                        const value = @cVaArg(&args, i32);
                        try writer.print("{}", .{value});
                    },
                    'p' => {
                        const value = @cVaArg(&args, *anyopaque);
                        try writer.print(std.fmt.comptimePrint("{{:0>{}}}", .{@sizeOf(*anyopaque) * 2}), .{@intFromPtr(value)});
                    },
                    else => return error.UnrecognizedCFormatSpecifier,
                }
            }
            chunk = chunk[1..];
            try writer.writeAll(chunk);
        }
    }
};

export fn log_err(fmt: [*:0]const u8, ...) void {
    logger.err("{}", .{CFmtFormatter{
        .fmt = fmt,
        .args = @cVaStart(),
    }});
}

export fn log_warn(fmt: [*:0]const u8, ...) void {
    logger.warn("{}", .{CFmtFormatter{
        .fmt = fmt,
        .args = @cVaStart(),
    }});
}

export fn log_info(fmt: [*:0]const u8, ...) void {
    logger.info("{}", .{CFmtFormatter{
        .fmt = fmt,
        .args = @cVaStart(),
    }});
}

export fn log_debug(fmt: [*:0]const u8, ...) void {
    logger.debug("{}", .{CFmtFormatter{
        .fmt = fmt,
        .args = @cVaStart(),
    }});
}
