const std = @import("std");

const alloc = @import("../root.zig").alloc;
const logger = @import("../util/logging.zig").logger;
const path_util = @import("../util/paths.zig");
const util = @import("../util.zig");

const os_char = util.os_char;
const c_bool = util.c_bool;

const c = @cImport(@cInclude("windows/paths.h"));

const DoorstopPaths = extern struct {
    app_path: [*:0]os_char,
    app_dir: [*:0]os_char,
    working_dir: [*:0]os_char,
    doorstop_path: [*:0]os_char,
};

export fn paths_init(doorstop_module: ?std.os.windows.HMODULE) *c.DoorstopPaths {
    const app_path = path_util.programPath();
    const app_dir = path_util.getFolderName(app_path);
    const working_dir = path_util.getWorkingDir();
    const doorstop_path_buf = path_util.getModulePath(doorstop_module).?;
    defer doorstop_path_buf.deinit();
    const doorstop_path = util.alloc.dupeZ(os_char, doorstop_path_buf.result) catch @panic("Out of memory");

    logger.debug("Doorstop started!", .{});
    logger.debug("Executable path: {}", .{std.unicode.fmtUtf16Le(app_path)});
    logger.debug("Application dir: {}", .{std.unicode.fmtUtf16Le(app_dir)});
    logger.debug("Working dir: {}", .{std.unicode.fmtUtf16Le(working_dir)});
    logger.debug("Doorstop library path: {}", .{std.unicode.fmtUtf16Le(doorstop_path)});

    var paths = alloc.create(DoorstopPaths) catch @panic("Out of memory");
    paths.app_path = app_path;
    paths.app_dir = app_dir;
    paths.working_dir = working_dir;
    paths.doorstop_path = doorstop_path;
    return @ptrCast(paths);
}

export fn paths_free(c_paths: *c.DoorstopPaths) void {
    const paths: *DoorstopPaths = @ptrCast(c_paths);
    util.alloc.free(std.mem.span(paths.app_path));
    util.alloc.free(std.mem.span(paths.app_dir));
    util.alloc.free(std.mem.span(paths.working_dir));
    util.alloc.free(std.mem.span(paths.doorstop_path));
    alloc.destroy(paths);
}
