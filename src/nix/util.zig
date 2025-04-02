const std = @import("std");

const c = struct {
    extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
};

pub fn setenv(key: [*:0]const u8, value: [*:0]const u8, overwrite: bool) void {
    const rc = c.setenv(key, value, @intFromBool(overwrite));
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        .NOMEM => @panic("Out of memory"),
        else => |err| {
            // INVAL is technically a possible error code from setenv, but we
            // know the key is valid
            std.debug.panic("unexpected errno: {d}\n", .{@intFromEnum(err)});
        },
    }
}
