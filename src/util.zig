const builtin = @import("builtin");
const std = @import("std");

pub const file_identity = @import("util/file_identity.zig");
pub const paths = @import("util/paths.zig");

const alloc = @import("root.zig").alloc;

pub const os_char = if (builtin.os.tag == .windows) std.os.windows.WCHAR else u8;

pub const c_bool = enum(c_int) {
    false = 0,
    true = 1,
    _,
};

pub fn Module(comptime @"const": bool) type {
    return if (builtin.os.tag == .windows) std.os.windows.HMODULE else if (@"const") *const anyopaque else *anyopaque;
}

pub fn osStrLiteral(comptime string: []const u8) [:0]const os_char {
    return comptime switch (builtin.os.tag) {
        .windows => std.unicode.utf8ToUtf16LeStringLiteral(string),
        else => string ++ "",
    };
}

pub fn empty(comptime T: type) *[0:0]T {
    return @constCast(&[_:0]T{});
}

pub const FmtAddress = struct {
    addr: usize,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (fmt.len == 0) {
            return writer.print(std.fmt.comptimePrint("0x{{?x:0>{}}}", .{@sizeOf(*anyopaque) * 2}), .{self.addr});
        } else {
            @compileError("unknown format string: '" ++ fmt ++ "'");
        }
    }
};

pub fn fmtAddress(ptr: anytype) FmtAddress {
    return .{ .addr = @intFromPtr(ptr) };
}

pub const FmtString = struct {
    str: [:0]const os_char,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (builtin.os.tag == .windows) {
            return std.unicode.fmtUtf16Le(self.str).format(fmt, options, writer);
        } else {
            if (comptime fmt.len == 0 or std.mem.eql(u8, fmt, "s")) {
                return writer.writeAll(self.str);
            } else {
                @compileError("unknown format string: '" ++ fmt ++ "'");
            }
        }
    }
};

pub fn fmtString(str: [:0]const os_char) FmtString {
    return .{ .str = str };
}

pub fn narrow(str: [:0]const os_char) struct {
    str: [:0]const u8,

    pub fn deinit(self: @This()) void {
        if (builtin.os.tag == .windows) {
            alloc.free(@constCast(self.str));
        }
    }
} {
    if (builtin.os.tag == .windows) {
        return .{ .str = std.unicode.wtf16LeToWtf8AllocZ(alloc, str) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        } };
    } else {
        return .{ .str = str };
    }
}

pub fn widen(str: [:0]const u8) struct {
    str: [:0]const os_char,

    pub fn deinit(self: @This()) void {
        if (builtin.os.tag == .windows) {
            alloc.free(@constCast(self.str));
        }
    }
} {
    if (builtin.os.tag == .windows) {
        return .{ .str = std.unicode.wtf8ToWtf16LeAllocZ(alloc, str) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
            error.InvalidWtf8 => @panic("Invalid WTF-8"),
        } };
    } else {
        return .{ .str = str };
    }
}
