const builtin = @import("builtin");
const std = @import("std");

const alloc = @import("../root.zig").alloc;
const util = @import("../util.zig");

const c_bool = util.c_bool;
const os_char = util.os_char;

const panicWindowsError = @import("../windows/util.zig").panicWindowsError;

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

/// The result will have a null-terminator at index `len`. The result buffer is allocated
/// using `util.alloc`.
pub fn getModulePath(
    module: if (builtin.os.tag == .windows) ?std.os.windows.HMODULE else ?*const anyopaque,
    free_space: usize,
) ?struct {
    /// There will be a null-terminator at the end of the module path as well as at the
    /// end of the allocation.
    result: [:0]os_char,
    len: usize,
} {
    if (builtin.os.tag == .windows) {
        var buf_size: usize = std.os.windows.MAX_PATH;
        while (true) {
            const buf = util.alloc.allocSentinel(os_char, @intCast(buf_size), 0) catch return null;
            const len = (std.os.windows.GetModuleFileNameW(module, buf.ptr, @truncate(buf_size)) catch |e| switch (e) {
                // this intFromEnum cuts the binary size by more than 50%
                error.Unexpected => panicWindowsError("GetModuleFileNameW", false),
            }).len;
            if (std.os.windows.GetLastError() != .INSUFFICIENT_BUFFER) {
                const available = buf_size - len;
                if (available >= free_space) {
                    return .{
                        // cast the pointer to account for the null-terminator added by GetModuleFileNameW
                        .result = @ptrCast(buf),
                        .len = len,
                    };
                } else {
                    // allocate exactly enough extra
                    buf_size += free_space - available;
                }
            } else {
                buf_size += std.os.windows.MAX_PATH;
            }
            util.alloc.free(buf);
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
        const buf = util.alloc.allocSentinel(u8, name.len + free_space, 0) catch @panic("Out of memory");
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        return .{
            .result = buf,
            .len = name.len,
        };
    }
}

fn getModulePathC(
    module: if (builtin.os.tag == .windows) ?std.os.windows.HMODULE else ?*const anyopaque,
    result: *?[*:0]os_char,
    len_ptr: ?*usize,
    free_space: usize,
) callconv(.c) usize {
    const r = getModulePath(module, free_space) orelse return 0;
    result.* = r.result;
    if (len_ptr) |ptr| {
        ptr.* = r.result.len;
    }
    return r.len;
}

comptime {
    @export(&getModulePathC, .{ .name = "get_module_path" });
}

export fn get_full_path(path: [*:0]const os_char) [*:0]os_char {
    if (builtin.os.tag == .windows) {
        var dangling_buf = [_]u16{};
        // According to official docs, in this case, `needed` includes the null-terminator...
        const needed = std.os.windows.kernel32.GetFullPathNameW(
            path,
            0,
            // this should be safe because nBufferLength is 0
            @ptrCast((&dangling_buf).ptr),
            null,
        );
        if (needed == 0) {
            panicWindowsError("GetFullPathNameW", true);
        }
        const res = util.alloc.alloc(os_char, @intCast(needed)) catch @panic("Out of memory");
        // but in this case `len` does not include the null-terminator.
        const len = std.os.windows.kernel32.GetFullPathNameW(
            path,
            needed,
            // this should be safe because the buffer is only written to
            @ptrCast(res.ptr),
            null,
        );
        if (len == 0) {
            panicWindowsError("GetFullPathNameW", true);
        }
        // see comments above for why this is `>=` instead of `>`
        if (len != needed - 1) {
            @panic("Path changed under us");
        }
        return res[0..len :0];
    } else {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const slice = std.fs.realpath(std.mem.span(path), &buf) catch |e| std.debug.panic("Failed to resolve a real path: {}", .{e});
        return toOsString(slice);
    }
}

pub fn getWorkingDir() [:0]os_char {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const slice = std.fs.cwd().realpath(".", &buf) catch |e| std.debug.panic("Failed to determine current working directory path: {}", .{e});
    return toOsString(slice);
}

fn getWorkingDirC() callconv(.c) [*:0]os_char {
    return getWorkingDir();
}

comptime {
    @export(&getWorkingDirC, .{ .name = "get_working_dir" });
}

pub fn programPath() [:0]os_char {
    if (builtin.os.tag == .windows) {
        return getModulePath(null, 0).?.result;
    } else {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        return toOsString(std.fs.selfExePath(&buf) catch |e| std.debug.panic("Failed to determine program path: {}", .{e}));
    }
}

fn programPathC() callconv(.c) [*:0]os_char {
    return programPath();
}

comptime {
    @export(&programPathC, .{ .name = "program_path" });
}

fn splitPath(path: []const os_char) struct {
    ext: usize,
    parent: usize,
} {
    if (path.len == 0) {
        @panic("Empty path provided to splitPath");
    }
    var ext = path.len;
    var i = path.len;
    while (true) {
        i -= 1;
        const c = path[i];
        if (c == '.' and ext == path.len) {
            ext = i;
        } else if (c == '/' or (builtin.os.tag == .windows and c == '\\')) {
            return .{ .ext = ext, .parent = i + 1 };
        }
        if (i == 0) {
            return .{ .ext = ext, .parent = 0 };
        }
    }
}

pub fn getFolderNameRef(path: []const os_char) []const os_char {
    const parts = splitPath(path);
    return path[0 .. @max(parts.parent, 1) - 1];
}

pub fn getFolderName(path: []const os_char) [:0]os_char {
    return util.alloc.dupeZ(os_char, getFolderNameRef(path)) catch @panic("Out of memory");
}

fn getFolderNameC(path: [*:0]const os_char) callconv(.c) [*:0]os_char {
    return getFolderName(std.mem.span(path));
}

comptime {
    @export(&getFolderNameC, .{ .name = "get_folder_name" });
}

pub fn getFileNameRef(path: []const os_char, with_ext: bool) []const os_char {
    const parts = splitPath(path);
    const end = if (with_ext) path.len else parts.ext;
    return path[parts.parent..end];
}

pub fn getFileName(path: []const os_char, with_ext: bool) [:0]os_char {
    return util.alloc.dupeZ(os_char, getFileNameRef(path, with_ext)) catch @panic("Out of memory");
}

fn getFileNameC(path: [*:0]const os_char, with_ext: c_bool) callconv(.c) [*:0]os_char {
    return getFileName(std.mem.span(path), with_ext != .false);
}

comptime {
    @export(&getFileNameC, .{ .name = "get_file_name" });
}

fn toOsString(buf: []const u8) [:0]os_char {
    if (builtin.os.tag == .windows) {
        return std.unicode.wtf8ToWtf16LeAllocZ(util.alloc, buf) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
            // selfExePath and realpath guarantee returning valid WTF-8 on Windows
            error.InvalidWtf8 => unreachable,
        };
    } else {
        return util.alloc.dupeZ(u8, buf) catch @panic("Out of memory");
    }
}

test "get_folder_name" {
    try std.testing.expectEqualSlices(os_char, "/foo/bar", getFolderName("/foo/bar/baz"));
    try std.testing.expectEqualSlices(os_char, "/foo/bar", getFolderName("/foo/bar/baz.txt"));
    try std.testing.expectEqualSlices(os_char, "", getFolderName("baz"));
    try std.testing.expectEqualSlices(os_char, "", getFolderName("baz.txt"));
}

test "get_file_name" {
    try std.testing.expectEqualSlices(os_char, "baz", getFileName("/foo/bar/baz", true));
    try std.testing.expectEqualSlices(os_char, "baz.txt", getFileName("/foo/bar/baz.txt", true));
    try std.testing.expectEqualSlices(os_char, "baz", getFileName("/foo/bar/baz", false));
    try std.testing.expectEqualSlices(os_char, "baz", getFileName("/foo/bar/baz.txt", false));
    try std.testing.expectEqualSlices(os_char, "baz.txt", getFileName("baz.txt", true));
}
