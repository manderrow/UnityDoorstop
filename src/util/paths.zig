const builtin = @import("builtin");
const std = @import("std");

const root = @import("../root.zig");
const alloc = root.alloc;
const util = root.util;

const os_char = util.os_char;

const panicWindowsError = @import("../windows/util.zig").panicWindowsError;

pub fn file_exists(file: [*:0]const os_char) bool {
    if (builtin.os.tag == .windows) {
        const attrs = std.os.windows.GetFileAttributesW(file) catch return false;
        return attrs & std.os.windows.FILE_ATTRIBUTE_DIRECTORY == 0;
    } else {
        std.fs.cwd().accessZ(std.mem.span(file), .{}) catch return false;
        return true;
    }
}

pub fn folder_exists(file: [*:0]const os_char) bool {
    if (builtin.os.tag == .windows) {
        const attrs = std.os.windows.GetFileAttributesW(file) catch return false;
        return attrs & std.os.windows.FILE_ATTRIBUTE_DIRECTORY != 0;
    } else {
        const stat = std.fs.cwd().statFile(std.mem.span(file)) catch return false;
        return stat.kind == .directory;
    }
}

pub const ModulePathBuf = struct {
    buf: if (builtin.os.tag == .windows) [std.os.windows.PATH_MAX_WIDE]u16 else void = undefined,

    pub fn get(self: *@This(), module: ?util.Module(true)) ?[:0]const os_char {
        self.* = undefined;
        if (builtin.os.tag == .windows) {
            // see https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-getmodulefilenamew
            const rc = std.os.windows.kernel32.GetModuleFileNameW(module, &self.buf, self.buf.len);
            if (rc == 0) {
                panicWindowsError("GetModuleFileNameW");
            }
            if (std.os.windows.GetLastError() == .INSUFFICIENT_BUFFER) {
                // should not be able to exceed PATH_MAX_WIDE
                unreachable;
            }
            return self.buf[0..rc :0];
        } else {
            const dlfcn = @cImport({
                @cDefine("_GNU_SOURCE", {});
                @cInclude("dlfcn.h");
            });

            var info: dlfcn.Dl_info = undefined;

            if (dlfcn.dladdr(module, &info) == 0) {
                return null;
            }
            self.* = .{ .buf = {} };
            return std.mem.span(@as(?[*:0]const u8, info.dli_fname).?);
        }
    }
};

fn get_full_path(path: [*:0]const os_char) [*:0]os_char {
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
        const res = alloc.alloc(os_char, @intCast(needed)) catch @panic("Out of memory");
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

pub const ProgramPathBuf = struct {
    buf: if (builtin.os.tag == .windows) ModulePathBuf else [std.fs.max_path_bytes:0]u8 = undefined,

    pub fn get(self: *@This()) [:0]const os_char {
        if (builtin.os.tag == .windows) {
            return self.buf.get(null) orelse @panic("Failed to determine program path");
        } else {
            self.* = undefined;
            const slice = std.fs.selfExePath(&self.buf) catch |e| std.debug.panic("Failed to determine program path: {}", .{e});
            self.buf[slice.len] = 0;
            return self.buf[0..slice.len :0];
        }
    }
};

fn splitPath(comptime Char: type, path: []const Char) struct {
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

pub fn getFolderNameRef(comptime Char: type, path: []const Char) []const Char {
    const parts = splitPath(Char, path);
    return path[0 .. @max(parts.parent, 1) - 1];
}

pub fn getFolderName(comptime Char: type, path: []const Char) [:0]Char {
    return alloc.dupeZ(Char, getFolderNameRef(Char, path)) catch @panic("Out of memory");
}

pub fn getFileNameRef(comptime Char: type, path: []const Char, with_ext: bool) []const Char {
    const parts = splitPath(Char, path);
    const end = if (with_ext) path.len else parts.ext;
    return path[parts.parent..end];
}

pub fn getFileName(comptime Char: type, path: []const Char, with_ext: bool) [:0]Char {
    return alloc.dupeZ(Char, getFileNameRef(Char, path, with_ext)) catch @panic("Out of memory");
}

fn toOsString(buf: []const u8) [:0]os_char {
    if (builtin.os.tag == .windows) {
        return std.unicode.wtf8ToWtf16LeAllocZ(alloc, buf) catch |e| switch (e) {
            error.OutOfMemory => @panic("Out of memory"),
            // selfExePath and realpath guarantee returning valid WTF-8 on Windows
            error.InvalidWtf8 => unreachable,
        };
    } else {
        return alloc.dupeZ(u8, buf) catch @panic("Out of memory");
    }
}

test "get_folder_name" {
    try std.testing.expectEqualStrings("/foo/bar", getFolderName(u8, "/foo/bar/baz"));
    try std.testing.expectEqualStrings("/foo/bar", getFolderName(u8, "/foo/bar/baz.txt"));
    try std.testing.expectEqualStrings("", getFolderName(u8, "baz"));
    try std.testing.expectEqualStrings("", getFolderName(u8, "baz.txt"));
}

test "get_file_name" {
    try std.testing.expectEqualStrings("baz", getFileName(u8, "/foo/bar/baz", true));
    try std.testing.expectEqualStrings("baz.txt", getFileName(u8, "/foo/bar/baz.txt", true));
    try std.testing.expectEqualStrings("baz", getFileName(u8, "/foo/bar/baz", false));
    try std.testing.expectEqualStrings("baz", getFileName(u8, "/foo/bar/baz.txt", false));
    try std.testing.expectEqualStrings("baz.txt", getFileName(u8, "baz.txt", true));
}
