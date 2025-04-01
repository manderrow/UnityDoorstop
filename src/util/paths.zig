const builtin = @import("builtin");
const std = @import("std");

const root = @import("../root.zig");
const alloc = root.alloc;
const util = root.util;

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

pub fn getModulePath(
    module: if (builtin.os.tag == .windows) ?std.os.windows.HMODULE else ?*const anyopaque,
) ?struct {
    result: [:0]const os_char,
    alloc_len: if (builtin.os.tag == .windows) usize else void,

    pub fn deinit(self: @This()) void {
        if (@TypeOf(self.alloc_len) != void) {
            alloc.free(@constCast(self.result.ptr)[0..self.alloc_len]);
        }
    }
} {
    if (builtin.os.tag == .windows) {
        var buf_size: usize = std.os.windows.MAX_PATH;
        while (true) {
            const buf = alloc.alloc(os_char, buf_size) catch return null;
            // see https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-getmodulefilenamew
            // pass `buf_size + 1` to include the null-terminator
            const rc = std.os.windows.kernel32.GetModuleFileNameW(module, buf.ptr, std.math.lossyCast(u32, buf_size));
            if (rc == 0) {
                panicWindowsError("GetModuleFileNameW");
            } else if (std.os.windows.GetLastError() == .INSUFFICIENT_BUFFER) {
                buf_size += buf_size / 2;
            } else {
                return .{
                    // cast the pointer to account for the null-terminator added by GetModuleFileNameW
                    .result = buf[0..rc :0],
                    .alloc_len = buf.len,
                };
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
        return .{
            .result = std.mem.span(@as([*:0]const u8, info.dli_fname)),
            .alloc_len = {},
        };
    }
}

export fn get_full_path(path: [*:0]const os_char) [*:0]os_char {
    if (builtin.os.tag == .windows) {
        // According to official docs, in this case, `needed` includes the null-terminator...
        const needed = std.os.windows.kernel32.GetFullPathNameW(
            path,
            0,
            util.empty(u16),
            null,
        );
        if (needed == 0) {
            panicWindowsError("GetFullPathNameW");
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
            panicWindowsError("GetFullPathNameW");
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
        const buf = getModulePath(null).?;
        defer buf.deinit();
        return util.alloc.dupeZ(os_char, buf.result) catch @panic("Out of memory");
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
