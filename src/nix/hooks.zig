const builtin = @import("builtin");
const std = @import("std");

const root = @import("../root.zig");

extern "c" fn fileno(stream: *std.c.FILE) c_int;

export fn fclose_hook(stream: *std.c.FILE) c_int {
    // Some versions of Unity wrongly close stdout, which prevents writing
    // to console
    const fd = fileno(stream);
    if (fd == std.posix.STDOUT_FILENO or fd == std.posix.STDERR_FILENO)
        return std.posix.F_OK;
    return std.posix.system.fclose(stream);
}

fn export_fopen_hook(comptime real_fn: @TypeOf(std.c.fopen), comptime name: []const u8) void {
    comptime {
        const f = struct {
            fn fopen_hook(noalias filename: [*:0]const u8, noalias mode: [*:0]const u8) callconv(.c) ?*std.c.FILE {
                var open_filename = filename;

                if (std.mem.eql(u8, std.mem.span(filename), root.hooks.defaultBootConfigPath)) {
                    open_filename = root.config.boot_config_override;
                    root.logger.debug("Overriding boot.config to {s}", .{open_filename});
                }

                return real_fn(open_filename, mode);
            }
        }.fopen_hook;
        @export(&f, .{ .name = name });
    }
}

comptime {
    export_fopen_hook(std.c.fopen, "fopen_hook");
    if (builtin.os.tag == .linux) {
        export_fopen_hook(std.c.fopen64, "fopen64_hook");
    }
}

export fn dup2_hook(od: c_int, nd: c_int) c_int {
    // Newer versions of Unity redirect stdout to player.log, we don't want
    // that
    if (nd == std.posix.STDOUT_FILENO or nd == std.posix.STDERR_FILENO)
        return std.posix.F_OK;
    return std.posix.system.dup2(od, nd);
}
