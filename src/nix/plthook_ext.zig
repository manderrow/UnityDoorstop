const builtin = @import("builtin");
const std = @import("std");

const plthook = @import("plthook");
const logger = @import("../util/logging.zig").logger;

comptime {
    switch (builtin.os.tag) {
        .windows => {},
        .macos => _ = struct {
            fn get_image_by_filename(name_ptr: [*:0]const u8) ?struct { idx: u32, name: [:0]const u8 } {
                const name = std.mem.span(name_ptr);
                for (1..std.c._dyld_image_count()) |idx| {
                    const image_name = std.mem.span(std.c._dyld_get_image_name(@intCast(idx)));
                    if (std.mem.indexOf(u8, image_name, name) != null) {
                        logger.debug("found image \"{s}\" matching \"{s}\"", .{ image_name, name });
                        return .{ .idx = @intCast(idx), .name = image_name };
                    }
                }
                return null;
            }

            export fn plthook_handle_by_filename(name_ptr: [*:0]const u8) ?*anyopaque {
                const info = get_image_by_filename(name_ptr) orelse return null;
                return std.c.dlopen(info.name, .{ .LAZY = true, .NOLOAD = true });
            }

            export fn plthook_open_by_filename(name_ptr: [*:0]const u8) ?*plthook.c.plthook {
                const info = get_image_by_filename(name_ptr) orelse return null;
                return plthook.macos.open(info.idx, null, null) catch null;
            }
        },
        else => _ = struct {
            const HandleByNameHelper = struct {
                find_name: []const u8,
                result: usize = undefined,
            };

            fn proc_handles(info: *std.posix.dl_phdr_info, size: usize, ctx: *HandleByNameHelper) error{Done}!void {
                _ = size;

                if (info.name) |name| {
                    if (std.mem.indexOf(u8, std.mem.span(name), ctx.find_name) != null) {
                        logger.debug("found image \"{s}\" matching \"{s}\"", .{ name, ctx.find_name });
                        ctx.result = info.addr;
                        return error.Done;
                    }
                }
            }

            export fn plthook_open_by_filename(name: [*:0]const u8) ?*plthook.c.plthook {
                var ctx = HandleByNameHelper{ .find_name = std.mem.span(name) };
                std.posix.dl_iterate_phdr(&ctx, error{Done}, proc_handles) catch |e| {
                    switch (e) {
                        error.Done => return plthook.open_by_address(ctx.result) catch null,
                    }
                };
                return null;
            }
        },
    }
}
