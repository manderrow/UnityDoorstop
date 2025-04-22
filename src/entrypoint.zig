const builtin = @import("builtin");
const std = @import("std");

const root = @import("root.zig");
const alloc = root.alloc;
const config = root.config;
const logger = root.logger;
const util = root.util;

comptime {
    // export entrypoints
    switch (builtin.os.tag) {
        .windows => {},
        else => {
            @export(&[_]*const fn () callconv(.c) void{entrypoint_c}, .{
                .section = if (builtin.os.tag == .macos) "__DATA,__mod_init_func" else ".init_array",
                .name = "init_array",
            });
        },
    }
}

fn entrypoint_c() callconv(.c) void {
    entrypoint({});
}

pub fn entrypoint(module: if (builtin.os.tag == .windows) std.os.windows.HMODULE else void) void {
    if (builtin.is_test)
        return;

    if (!config.load()) {
        logger.info("Doorstop not enabled! Skipping!", .{});
        return;
    }

    logger.debug("Doorstop started!", .{});

    const debug_env = @import("debug/env.zig");
    debug_env.dumpProgramPath();
    debug_env.dumpWorkingDir();
    debug_env.dumpDoorstopPath(module);

    switch (builtin.os.tag) {
        // windows
        .windows => {
            root.hooks.windows.stdout_handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch null;
            root.hooks.windows.stderr_handle = std.os.windows.GetStdHandle(std.os.windows.STD_ERROR_HANDLE) catch null;

            logger.debug("Standard output handle at {}", .{util.fmtAddress(root.hooks.windows.stdout_handle)});
            logger.debug("Standard error handle at {}", .{util.fmtAddress(root.hooks.windows.stderr_handle)});
            // char_t handle_path[MAX_PATH] = L"";
            // GetFinalPathNameByHandle(stdout_handle, handle_path, MAX_PATH, 0);
            // LOG("Standard output handle path: %" Ts, handle_path);

            const target_module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("UnityPlayer")) orelse blk: {
                logger.debug("No UnityPlayer module found! Using executable as the hook target.", .{});
                break :blk std.os.windows.kernel32.GetModuleHandleW(null).?;
            };

            root.hooks.installHooksWindows(target_module);
        },
        else => root.hooks.installHooksNix(),
    }

    if (builtin.os.tag == .windows) {
        // I'm not sure why they only do this on Windows.
        // The presence is what matters, not the value.
        util.setEnv("DOORSTOP_DISABLE", util.osStrLiteral("1"));
    }

    logger.info("Injected hooks", .{});
}

pub const windows = struct {
    pub var doorstop_module: ?std.os.windows.HMODULE = null;

    const FdwReason = enum(std.os.windows.DWORD) {
        PROCESS_DETACH = 0,
        PROCESS_ATTACH = 1,
        THREAD_ATTACH = 2,
        THREAD_DETACH = 3,
    };

    pub noinline fn DllMain(
        hInstDll: std.os.windows.HINSTANCE,
        fdwReasonRaw: u32,
        _: std.os.windows.LPVOID,
    ) std.os.windows.BOOL {
        const fdwReason: FdwReason = @enumFromInt(fdwReasonRaw);

        if (fdwReason == .PROCESS_DETACH) {
            // similarly to above, I'm not sure why they only do this on Windows.
            util.setEnv("DOORSTOP_DISABLE", null);
        }

        if (fdwReason != .PROCESS_ATTACH) {
            return std.os.windows.TRUE;
        }

        entrypoint(@ptrCast(hInstDll));

        return std.os.windows.TRUE;
    }
};
