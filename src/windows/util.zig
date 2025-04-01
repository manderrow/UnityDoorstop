const std = @import("std");

pub fn panicWindowsError(func: []const u8) noreturn {
    @branchHint(.cold);
    const e = std.os.windows.GetLastError();
    std.os.windows.unexpectedError(e) catch {};
    // this intFromEnum cuts the binary size by more than 50% compared with the implicit
    // @tagName that would otherwise be used.
    std.debug.panic("{s} returned error code {}", .{ func, @intFromEnum(e) });
}
