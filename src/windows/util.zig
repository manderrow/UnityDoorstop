const std = @import("std");

pub fn panicWindowsError(func: []const u8, trace: bool) noreturn {
    @branchHint(.cold);
    const e = std.os.windows.GetLastError();
    if (trace) {
        std.os.windows.unexpectedError(e) catch {};
    }
    std.debug.panic("{s} returned error code {}", .{ func, @intFromEnum(e) });
}
