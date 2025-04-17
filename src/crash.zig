const builtin = @import("builtin");
const std = @import("std");

const runtimeSafety = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub fn crashUnreachable(src: std.builtin.SourceLocation) noreturn {
    @branchHint(.cold);
    if (runtimeSafety) {
        std.debug.panic(
            "reached unreachable code in {s} at {s}:{s}:{}:{}",
            .{ src.fn_name, src.module, src.file, src.line, src.column },
        );
    } else {
        unreachable;
    }
}
