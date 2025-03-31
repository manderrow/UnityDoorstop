const std = @import("std");

const alloc = @import("../root.zig").alloc;
const util = @import("../util.zig");
const logger = @import("../util/logging.zig").logger;

const c = @cImport(@cInclude("windows/paths.h"));

const DoorstopPaths = extern struct {
    app_path: [*:0]util.os_char,
    app_dir: [*:0]util.os_char,
    working_dir: [*:0]util.os_char,
    doorstop_path: [*:0]util.os_char,
    doorstop_filename: [*:0]util.os_char,
};

export fn paths_init(doorstop_module: ?std.os.windows.HMODULE, fixed_cwd: util.c_bool) *c.DoorstopPaths {
    const app_path = util.program_path();
    const app_dir = util.getFolderName(app_path);
    const working_dir = util.getWorkingDir();
    const doorstop_path_raw = util.getModulePath(doorstop_module, 0).?;
    const doorstop_path = doorstop_path_raw.result[0..doorstop_path_raw.len :0];

    const doorstop_filename = util.getFileName(doorstop_path, false);

    logger.debug("Doorstop started!", .{});
    logger.debug("Executable path: {}", .{std.unicode.fmtUtf16Le(app_path)});
    logger.debug("Application dir: {}", .{std.unicode.fmtUtf16Le(app_dir)});
    logger.debug("Working dir: {}", .{std.unicode.fmtUtf16Le(working_dir)});
    logger.debug("Doorstop library path: {}", .{std.unicode.fmtUtf16Le(doorstop_path)});
    logger.debug("Doorstop library name: {}", .{std.unicode.fmtUtf16Le(doorstop_filename)});

    if (fixed_cwd != .false) {
        logger.warn("Working directory was not the same as app directory, fixed it automatically.", .{});
    }

    var paths = alloc.create(DoorstopPaths) catch @panic("Out of memory");
    paths.app_path = app_path;
    paths.app_dir = app_dir;
    paths.working_dir = working_dir;
    paths.doorstop_path = doorstop_path;
    paths.doorstop_filename = doorstop_filename;
    return @ptrCast(paths);
}

export fn paths_free(c_paths: *c.DoorstopPaths) void {
    const paths: *DoorstopPaths = @ptrCast(c_paths);
    alloc.free(std.mem.span(paths.app_path));
    alloc.free(std.mem.span(paths.app_dir));
    alloc.free(std.mem.span(paths.working_dir));
    alloc.free(std.mem.span(paths.doorstop_path));
    alloc.free(std.mem.span(paths.doorstop_filename));
    alloc.destroy(paths);
}
