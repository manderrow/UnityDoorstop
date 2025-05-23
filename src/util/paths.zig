const builtin = @import("builtin");
const std = @import("std");

const crash = @import("../crash.zig");
const root = @import("../root.zig");
const alloc = root.alloc;
const util = root.util;

const os_char = util.os_char;

const panicWindowsError = @import("../windows/util.zig").panicWindowsError;

pub fn exists(path: [*:0]const os_char, comptime filter: enum { file, directory }) bool {
    if (builtin.os.tag == .windows) {
        const attrs = std.os.windows.GetFileAttributesW(path) catch return false;
        return switch (filter) {
            .file => attrs & std.os.windows.FILE_ATTRIBUTE_DIRECTORY == 0,
            .directory => attrs & std.os.windows.FILE_ATTRIBUTE_DIRECTORY != 0,
        };
    } else {
        switch (filter) {
            .file => {
                std.fs.cwd().accessZ(std.mem.span(path), .{}) catch return false;
                return true;
            },
            .directory => {
                const stat = std.fs.cwd().statFile(std.mem.span(path)) catch return false;
                return stat.kind == .directory;
            },
        }
    }
}

pub const ModulePathBuf = struct {
    buf: if (builtin.os.tag == .windows) [std.os.windows.PATH_MAX_WIDE]u16 else void,

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
                crash.crashUnreachable(@src());
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

pub fn getWorkingDir() ![:0]os_char {
    switch (builtin.os.tag) {
        .windows => {
            var buf: [std.os.windows.PATH_MAX_WIDE:0]u16 = undefined;
            const result = std.os.windows.kernel32.GetCurrentDirectoryW(buf.len + 1, &buf);
            if (result == 0) {
                switch (std.os.windows.GetLastError()) {
                    else => |err| return std.os.windows.unexpectedError(err),
                }
            }
            std.debug.assert(result <= buf.len);
            return alloc.dupeZ(u16, buf[0..result]);
        },
        else => {
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const slice = try std.posix.getcwd(&buf);
            return alloc.dupeZ(u8, slice);
        },
    }
}

pub const ProgramPathBuf = struct {
    buf: if (builtin.os.tag == .windows) ModulePathBuf else [std.fs.max_path_bytes:0]u8,

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

/// The returned slice is a reference into `path`.
pub fn getFolderName(comptime Char: type, path: []const Char) []const Char {
    const parts = splitPath(Char, path);
    return path[0 .. @max(parts.parent, 1) - 1];
}

/// Caller must free the returned slice.
pub fn getFolderNameZ(comptime Char: type, path: []const Char) [:0]Char {
    return alloc.dupeZ(Char, getFolderName(Char, path)) catch @panic("Out of memory");
}

/// The returned slice is a reference into `path`.
pub fn getFileName(comptime Char: type, path: []const Char, with_ext: bool) []const Char {
    const parts = splitPath(Char, path);
    const end = if (with_ext) path.len else parts.ext;
    return path[parts.parent..end];
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
