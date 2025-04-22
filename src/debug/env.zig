const builtin = @import("builtin");
const std = @import("std");

const root = @import("../root.zig");
const alloc = root.alloc;
const logger = root.logger;
const util = root.util;

pub fn dumpProgramPath() void {
    var program_path_buf: util.paths.ProgramPathBuf = undefined;
    const app_path = program_path_buf.get();
    const app_dir = util.paths.getFolderName(util.os_char, app_path);
    logger.debug("Executable path: {}", .{util.fmtString(app_path)});
    logger.debug("Application dir: {}", .{util.fmtString(app_dir)});
}

pub fn dumpWorkingDir() void {
    const working_dir = util.paths.getWorkingDir() catch |e| std.debug.panic("Failed to determine current working directory path: {}", .{e});
    defer alloc.free(working_dir);
    logger.debug("Working dir: {}", .{util.fmtString(working_dir)});
}

pub fn dumpDoorstopPath(module: if (builtin.os.tag == .windows) std.os.windows.HMODULE else void) void {
    var doorstop_path_buf: util.paths.ModulePathBuf = undefined;
    const doorstop_path = doorstop_path_buf.get(switch (builtin.os.tag) {
        .windows => module,
        // on *nix we just need an address in the library
        else => &dumpDoorstopPath,
    }).?;

    logger.debug("Doorstop library path: {}", .{util.fmtString(doorstop_path)});
}

pub fn dumpStdHandle(name: []const u8, handle: ?std.os.windows.HANDLE) void {
    var buf: [std.os.windows.PATH_MAX_WIDE]u16 = undefined;
    if (handle) |h| {
        const path = std.os.windows.GetFinalPathNameByHandle(h, .{}, &buf) catch |e| {
            logger.debug("Standard {s} handle at {}, unable to determine path: {}", .{ name, util.fmtAddress(h), e });
            return;
        };
        logger.debug("Standard {s} handle at {}, {s}", .{ name, util.fmtAddress(handle), std.unicode.fmtUtf16Le(path) });
    } else {
        logger.debug("Standard {s} handle at null", .{name});
    }
}
