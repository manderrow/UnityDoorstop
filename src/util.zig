const builtin = @import("builtin");
const std = @import("std");

pub const file_identity = @import("util/file_identity.zig");
pub const paths = @import("util/paths.zig");

/// The allocator used by any C-export APIs, and any APIs marked as such.
// TODO: replace with @import("root.zig").alloc
//       This will require widespread changes in the C codebase.
pub const alloc = std.heap.raw_c_allocator;

pub const os_char = if (builtin.os.tag == .windows) std.os.windows.WCHAR else u8;

pub const c_bool = enum(c_int) {
    false = 0,
    true = 1,
    _,
};

pub fn osStrLiteral(comptime string: []const u8) [:0]const os_char {
    return comptime switch (builtin.os.tag) {
        .windows => std.unicode.utf8ToUtf16LeStringLiteral(string),
        else => string ++ "",
    };
}

pub fn empty(comptime T: type) *[0:0]T {
    return @constCast(&[_:0]T{});
}

export const IS_TEST = builtin.is_test;

export fn malloc_custom(size: usize) ?[*]align(@alignOf(std.c.max_align_t)) u8 {
    return (alloc.alignedAlloc(u8, @alignOf(std.c.max_align_t), size) catch return null).ptr;
}

export fn calloc_custom(num: usize, size: usize) ?[*]align(@alignOf(std.c.max_align_t)) u8 {
    const buf = alloc.alignedAlloc(u8, @alignOf(std.c.max_align_t), size * num) catch return null;
    @memset(buf, 0);
    return buf.ptr;
}

export fn free_custom(ptr: [*]u8) void {
    std.c.free(ptr);
}

export fn narrow(str: [*:0]const os_char) [*:0]u8 {
    if (builtin.os.tag == .windows) {
        return std.unicode.wtf16LeToWtf8AllocZ(alloc, std.mem.span(str)) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        };
    } else {
        return alloc.dupeZ(u8, std.mem.span(str)) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        };
    }
}

export fn widen(str: [*:0]const u8) [*:0]os_char {
    if (builtin.os.tag == .windows) {
        return std.unicode.wtf8ToWtf16LeAllocZ(alloc, std.mem.span(str)) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
            error.InvalidWtf8 => @panic("Invalid WTF-8"),
        };
    } else {
        return alloc.dupeZ(u8, std.mem.span(str)) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        };
    }
}
