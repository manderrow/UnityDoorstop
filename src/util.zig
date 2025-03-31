const builtin = @import("builtin");
const std = @import("std");

// TODO: replace with @import("root.zig").alloc
//       This will require widespread changes in the C codebase.
const alloc = std.heap.raw_c_allocator;

pub const os_char = if (builtin.os.tag == .windows) std.os.windows.WCHAR else u8;

pub const c_bool = enum(c_int) {
    false = 0,
    true = 1,
    _,
};

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
        return (std.unicode.wtf16LeToWtf8AllocZ(alloc, std.mem.span(str)) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        }).ptr;
    } else {
        return (alloc.dupeZ(u8, std.mem.span(str)) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        }).ptr;
    }
}

export fn widen(str: [*:0]const u8) [*:0]os_char {
    if (builtin.os.tag == .windows) {
        return (std.unicode.wtf8ToWtf16LeAllocZ(alloc, std.mem.span(str)) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
            error.InvalidWtf8 => @panic("Invalid WTF-8"),
        }).ptr;
    } else {
        return (alloc.dupeZ(u8, std.mem.span(str)) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        }).ptr;
    }
}

export fn file_exists(file: [*:0]const os_char) bool {
    if (builtin.os.tag == .windows) {
        const attrs = std.os.windows.GetFileAttributesW(file) catch return false;
        return attrs & std.os.windows.FILE_ATTRIBUTE_DIRECTORY == 0;
    } else {
        std.fs.cwd().accessZ(std.mem.span(file), .{}) catch return false;
        return true;
    }
}

export fn folder_exists(file: [*:0]const os_char) bool {
    if (builtin.os.tag == .windows) {
        const attrs = std.os.windows.GetFileAttributesW(file) catch return false;
        return attrs & std.os.windows.FILE_ATTRIBUTE_DIRECTORY != 0;
    } else {
        const stat = std.fs.cwd().statFile(std.mem.span(file)) catch return false;
        return stat.kind == .directory;
    }
}

/// The result will have a null-terminator at index `len`.
pub fn get_module_path(
    module: if (builtin.os.tag == .windows) ?std.os.windows.HMODULE else ?*const anyopaque,
    free_space: usize,
) ?struct {
    result: []os_char,
    len: usize,
} {
    if (builtin.os.tag == .windows) {
        var buf_size: usize = std.os.windows.MAX_PATH;
        while (true) {
            const buf = alloc.alloc(os_char, @intCast(buf_size)) catch return null;
            const len = (std.os.windows.GetModuleFileNameW(module, buf.ptr, @truncate(buf_size)) catch |e| switch (e) {
                // this intFromEnum cuts the binary size by more than 50%
                error.Unexpected => std.debug.panic("{}", .{@intFromEnum(std.os.windows.GetLastError())}),
            }).len;
            if (std.os.windows.GetLastError() != .INSUFFICIENT_BUFFER) {
                const available = buf_size - len;
                if (available >= free_space) {
                    return .{
                        .result = buf,
                        .len = len,
                    };
                } else {
                    // allocate exactly enough extra
                    buf_size += free_space - available;
                }
            } else {
                buf_size += std.os.windows.MAX_PATH;
            }
            alloc.free(buf);
        }
    } else {
        const dlfcn = @cImport({
            @cDefine("_GNU_SOURCE", {});
            @cInclude("dlfcn.h");
        });

        var info: dlfcn.Dl_info = undefined;

        if (dlfcn.dladdr(module, &info) == 0) {
            @panic("Could not locate module");
        }
        const name = std.mem.span(@as([*:0]const u8, info.dli_fname));
        const total_size = name.len + free_space + 1;
        const buf = alloc.alloc(u8, total_size) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        };
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        return .{
            .result = buf,
            .len = name.len,
        };
    }
}

fn get_module_path_c(
    module: if (builtin.os.tag == .windows) ?std.os.windows.HMODULE else ?*const anyopaque,
    result: *?[*:0]os_char,
    len_ptr: ?*usize,
    free_space: usize,
) callconv(.c) usize {
    const r = get_module_path(module, free_space) orelse return 0;
    result.* = @ptrCast(r.result.ptr);
    if (len_ptr) |ptr| {
        ptr.* = r.result.len;
    }
    return r.len;
}

comptime {
    @export(&get_module_path_c, .{ .name = "get_module_path" });
}

export fn get_full_path(path: [*:0]const os_char) [*:0]os_char {
    if (builtin.os.tag == .windows) {
        var dangling_buf = [_]u16{};
        const needed = std.os.windows.kernel32.GetFullPathNameW(
            path,
            0,
            @ptrCast((&dangling_buf).ptr),
            null,
        );
        const res = alloc.alloc(os_char, @intCast(needed)) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        };
        const len = std.os.windows.kernel32.GetFullPathNameW(
            path,
            needed,
            @ptrCast(res.ptr),
            null,
        );
        if (len > needed) {
            @panic("Path changed under us");
        }
        return res[0..len :0].ptr;
    } else {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const slice = std.fs.realpath(std.mem.span(path), &buf) catch |e| std.debug.panic("{}", .{e});
        return toOsString(slice);
    }
}

pub export fn get_working_dir() [*:0]os_char {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const slice = std.fs.cwd().realpath(".", &buf) catch |e| std.debug.panic("Could not determine current working directory path: {}", .{e});
    return toOsString(slice);
}

pub export fn program_path() [*:0]os_char {
    if (builtin.os.tag == .windows) {
        const r = get_module_path(null, 0).?;
        return @ptrCast(r.result.ptr);
    } else {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const slice = std.fs.selfExePath(&buf) catch |e| std.debug.panic("Could not determine program path: {}", .{e});
        return toOsString(slice);
    }
}

fn split_path(path: [*:0]const os_char) struct {
    ext: usize,
    parent: usize,
    len: usize,
} {
    const len = std.mem.len(path);
    if (len == 0) {
        return .{ .ext = 0, .parent = 0, .len = 0 };
    }
    var ext = len;
    var i = len;
    while (true) {
        i -= 1;
        const c = path[i];
        if (c == '.' and ext == len) {
            ext = i;
        } else if (c == '/' or (builtin.os.tag == .windows and c == '\\')) {
            return .{ .ext = ext, .parent = i + 1, .len = len };
        }
        if (i == 0) {
            return .{ .ext = ext, .parent = 0, .len = len };
        }
    }
}

pub export fn get_folder_name(path: [*:0]const os_char) [*:0]os_char {
    const parts = split_path(path);
    return (alloc.dupeZ(os_char, path[0 .. @max(parts.parent, 1) - 1]) catch @panic("Out of memory")).ptr;
}

pub export fn get_file_name(path: [*:0]const os_char, with_ext: c_bool) [*:0]os_char {
    const parts = split_path(path);
    const end = if (with_ext != .false) parts.len else parts.ext;
    return (alloc.dupeZ(os_char, path[parts.parent..end]) catch @panic("Out of memory")).ptr;
}

fn toOsString(buf: []const u8) [*:0]os_char {
    if (builtin.os.tag == .windows) {
        return std.unicode.wtf8ToWtf16LeAllocZ(alloc, buf) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
            // selfExePath guarantees returning valid WTF-8 on Windows
            error.InvalidWtf8 => unreachable,
        };
    } else {
        return (alloc.dupeZ(u8, buf) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
        }).ptr;
    }
}

test "get_folder_name" {
    try std.testing.expectEqualSentinel(os_char, 0, "/foo/bar", std.mem.span(get_folder_name("/foo/bar/baz")));
    try std.testing.expectEqualSentinel(os_char, 0, "/foo/bar", std.mem.span(get_folder_name("/foo/bar/baz.txt")));
    try std.testing.expectEqualSentinel(os_char, 0, "", std.mem.span(get_folder_name("baz")));
    try std.testing.expectEqualSentinel(os_char, 0, "", std.mem.span(get_folder_name("baz.txt")));
}

test "get_file_name" {
    try std.testing.expectEqualSentinel(os_char, 0, "baz", std.mem.span(get_file_name("/foo/bar/baz", .true)));
    try std.testing.expectEqualSentinel(os_char, 0, "baz.txt", std.mem.span(get_file_name("/foo/bar/baz.txt", .true)));
    try std.testing.expectEqualSentinel(os_char, 0, "baz", std.mem.span(get_file_name("/foo/bar/baz", .false)));
    try std.testing.expectEqualSentinel(os_char, 0, "baz", std.mem.span(get_file_name("/foo/bar/baz.txt", .false)));
    try std.testing.expectEqualSentinel(os_char, 0, "baz.txt", std.mem.span(get_file_name("baz.txt", .true)));
}
