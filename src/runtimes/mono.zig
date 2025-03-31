const builtin = @import("builtin");
const std = @import("std");

const alloc = @import("../root.zig").alloc;
const logger = @import("../util/logging.zig").logger;
const runtimes = @import("../runtimes.zig");
const os_char = @import("../util.zig").os_char;

pub const c = @cImport(@cInclude("runtimes/mono.h"));

pub var addrs: c.mono_struct = .{};

comptime {
    @export(&addrs, .{ .name = "mono" });
}

const MonoImageOpenFileStatus = enum(c_int) {
    ok = c.MONO_IMAGE_OK,
    error_errno = c.MONO_IMAGE_ERROR_ERRNO,
    missing_assemblyref = c.MONO_IMAGE_MISSING_ASSEMBLYREF,
    image_invalid = c.MONO_IMAGE_IMAGE_INVALID,
    file_not_found = -1,
    file_error = -2,
};

/// If the file exists, it will be loaded, and `true` will be returned. If loading fails,
/// the function panics. If the file does not exist, `false` will be returned.
export fn mono_image_open_from_file_with_name(
    path: [*:0]const os_char,
    status: *MonoImageOpenFileStatus,
    refonly: i32,
    name: [*:0]const u8,
) ?*anyopaque {
    const buf = blk: {
        var file = switch (builtin.os.tag) {
            .windows => std.fs.cwd().openFileW(std.mem.span(path), .{}),
            else => std.fs.cwd().openFileZ(path, .{}),
        } catch |e| switch (e) {
            error.FileNotFound => {
                std.c._errno().* = @intFromEnum(std.c.E.NOENT);
                status.* = .error_errno;
                return null;
            },
            else => {
                logger.err("Failed to open Mono image file: {}", .{e});
                status.* = .file_error;
                return null;
            },
        };
        defer file.close();

        // If the file size doesn't fit a usize it'll be certainly greater than
        // `max_bytes`
        const stat_size = std.math.cast(u32, file.getEndPos() catch |e| {
            logger.err("Failed to read Mono image file: {}", .{e});
            status.* = .file_error;
            return null;
        }) orelse {
            std.c._errno().* = @intFromEnum(std.c.E.FBIG);
            status.* = .error_errno;
            return null;
        };

        break :blk file.readToEndAllocOptions(
            alloc,
            std.math.maxInt(usize),
            @intCast(stat_size),
            @alignOf(std.c.max_align_t),
            0,
        ) catch |e| {
            logger.err("Failed to read Mono image file: {}", .{e});
            status.* = .file_error;
            return null;
        };
    };
    defer alloc.free(buf);

    // need must be forced to true so that Mono copies the data out of our temporary buffer.
    return addrs.image_open_from_data_with_name.?(
        buf.ptr,
        @intCast(buf.len),
        c.TRUE,
        @ptrCast(status),
        refonly,
        name,
    );
}
