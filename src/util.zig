const builtin = @import("builtin");
const std = @import("std");

pub const file_identity = @import("util/file_identity.zig");
pub const paths = @import("util/paths.zig");

const alloc = @import("root.zig").alloc;

pub const os_char = if (builtin.os.tag == .windows) std.os.windows.WCHAR else u8;

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

    pub fn format(self: @This(), writer: *std.io.Writer) !void {
        return writer.print(std.fmt.comptimePrint("0x{{x:0>{}}}", .{@sizeOf(*anyopaque) * 2}), .{self.addr});
    }
};

pub fn fmtAddress(ptr: anytype) FmtAddress {
    return .{ .addr = @intFromPtr(ptr) };
}

pub fn FmtString(comptime char: type) type {
    return struct {
        str: []const char,

        pub fn format(self: @This(), writer: *std.io.Writer) !void {
            if (char == u16) {
                return std.unicode.fmtUtf16Le(self.str).format(writer);
            } else {
                return writer.writeAll(self.str);
            }
        }
    };
}

pub fn fmtString(str: []const os_char) FmtString(os_char) {
    return .{ .str = str };
}

pub fn narrow(comptime nt_in: bool, comptime nt_out: bool, str: if (nt_in) [:0]const os_char else []const os_char) struct {
    str: if (nt_out) [:0]const u8 else []const u8,

    pub fn deinit(self: @This()) void {
        if (builtin.os.tag == .windows or (nt_out and !nt_in)) {
            alloc.free(@constCast(self.str));
        }
    }
} {
    if (builtin.os.tag == .windows) {
        return .{ .str = std.unicode.wtf16LeToWtf8AllocZ(alloc, str) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        } };
    } else {
        return .{ .str = if (nt_out and !nt_in) alloc.dupeZ(u8, str) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        } else str };
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

pub fn setEnv(comptime key: [:0]const u8, value: ?[:0]const os_char) void {
    switch (builtin.os.tag) {
        .windows => {
            @import("windows/util.zig").SetEnvironmentVariable(key, value orelse null);
        },
        else => {
            if (value) |v| {
                @import("nix/util.zig").setenv(key, v, true);
            } else {
                @import("nix/util.zig").unsetenv(key);
            }
        },
    }
}
