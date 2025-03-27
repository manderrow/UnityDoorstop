const std = @import("std");

const logger = @import("../logging.zig").logger;

const CFmtFormatter = struct {
    fmt: [*:0]const u8,
    args: std.builtin.VaList,
    // FIXME: the constCasts on this are bad
    err: ?error{ InvalidCFormatString, UnrecognizedCFormatSpecifier } = null,

    pub fn format(
        self: *const @This(),
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (fmt.len != 0) @compileError("Unrecognized format specifier: " ++ fmt);
        // FIXME: this constCast is bad
        var args = @cVaCopy(@constCast(&self.args));
        defer @cVaEnd(&args);
        var iter = std.mem.splitScalar(u8, std.mem.span(self.fmt), '%');
        try writer.writeAll(iter.first());
        while (iter.next()) |chunkIn| {
            var chunk = chunkIn;
            if (chunk.len == 0) {
                chunk = iter.next() orelse {
                    @constCast(self).err = error.InvalidCFormatString;
                    return;
                };
                try writer.writeByte('%');
            } else {
                switch (chunk[0]) {
                    's' => {
                        const s = @cVaArg(&args, [*:0]const u8);
                        try writer.writeAll(std.mem.span(s));
                    },
                    'l' => {
                        if (chunk.len < 2) {
                            @constCast(self).err = error.InvalidCFormatString;
                            return;
                        }
                        switch (chunk[1]) {
                            's' => {
                                const s = @cVaArg(&args, [*:0]const u16);
                                try writer.print("{}", .{std.unicode.fmtUtf16Le(std.mem.span(s))});
                            },
                            else => {
                                @constCast(self).err = error.UnrecognizedCFormatSpecifier;
                                return;
                            },
                        }
                    },
                    'd' => {
                        const value = @cVaArg(&args, i32);
                        try writer.print("{}", .{value});
                    },
                    'p' => {
                        const value = @cVaArg(&args, *anyopaque);
                        try writer.print(std.fmt.comptimePrint("{{x:0>{}}}", .{@sizeOf(*anyopaque) * 2}), .{@intFromPtr(value)});
                    },
                    else => {
                        @constCast(self).err = error.UnrecognizedCFormatSpecifier;
                        return;
                    },
                }
            }
            chunk = chunk[1..];
            try writer.writeAll(chunk);
        }
    }
};

fn log(comptime f: fn (comptime format: []const u8, args: anytype) void, fmt: [*:0]const u8, args: std.builtin.VaList) void {
    var value = CFmtFormatter{
        .fmt = fmt,
        .args = args,
    };
    defer @cVaEnd(&value.args);
    f("{}", .{value});
    if (value.err) |err| {
        std.debug.panic("Failed to format extern log message: {}", .{err});
    }
}

export fn log_err(fmt: [*:0]const u8, ...) void {
    log(logger.err, fmt, @cVaStart());
}

export fn log_warn(fmt: [*:0]const u8, ...) void {
    log(logger.warn, fmt, @cVaStart());
}

export fn log_info(fmt: [*:0]const u8, ...) void {
    log(logger.info, fmt, @cVaStart());
}

export fn log_debug(fmt: [*:0]const u8, ...) void {
    log(logger.debug, fmt, @cVaStart());
}
