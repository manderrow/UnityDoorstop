const std = @import("std");

const root = @import("../root.zig");
const alloc = root.alloc;
const logger = root.logger;
const util = root.util;

const os_char = util.os_char;
const c_bool = util.c_bool;

app_path: [:0]os_char,
app_dir: [:0]os_char,
working_dir: [:0]os_char,
doorstop_path: [:0]os_char,

pub fn init() @This() {
    const app_path = util.paths.programPath();
    const app_dir = util.paths.getFolderName(app_path);
    const working_dir = util.paths.getWorkingDir();
    const doorstop_path_buf = util.paths.getModulePath(root.entrypoint.windows.doorstop_module).?;
    defer doorstop_path_buf.deinit();
    const doorstop_path = alloc.dupeZ(os_char, doorstop_path_buf.result) catch @panic("Out of memory");

    logger.debug("Doorstop started!", .{});
    logger.debug("Executable path: {}", .{std.unicode.fmtUtf16Le(app_path)});
    logger.debug("Application dir: {}", .{std.unicode.fmtUtf16Le(app_dir)});
    logger.debug("Working dir: {}", .{std.unicode.fmtUtf16Le(working_dir)});
    logger.debug("Doorstop library path: {}", .{std.unicode.fmtUtf16Le(doorstop_path)});

    return .{
        .app_path = app_path,
        .app_dir = app_dir,
        .working_dir = working_dir,
        .doorstop_path = doorstop_path,
    };
}

pub fn deinit(self: *@This()) void {
    alloc.free(std.mem.span(self.app_path));
    alloc.free(std.mem.span(self.app_dir));
    alloc.free(std.mem.span(self.working_dir));
    alloc.free(std.mem.span(self.doorstop_path));
}
