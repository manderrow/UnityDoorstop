const std = @import("std");

pub fn panicWindowsError(func: []const u8) noreturn {
    @branchHint(.cold);
    const e = std.os.windows.GetLastError();
    std.os.windows.unexpectedError(e) catch {};
    // this intFromEnum cuts the binary size by more than 50% compared with the implicit
    // @tagName that would otherwise be used.
    std.debug.panic("{s} returned error code {}", .{ func, @intFromEnum(e) });
}

pub fn SetEnvironmentVariable(comptime key: []const u8, value: ?[*:0]const u16) void {
    if (std.os.windows.kernel32.SetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral(key), value) == 0) {
        panicWindowsError("SetEnvironmentVariableW");
    }
}
