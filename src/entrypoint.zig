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
        .windows => {
            _ = windows;
        },
        else => {
            @export(&[1]*const fn () callconv(.C) void{entrypoint}, .{
                .section = if (builtin.os.tag == .macos) "__DATA,__mod_init_func" else ".init_array",
                .name = "init_array",
            });
        },
    }
}

pub fn entrypoint() callconv(.c) void {
    if (builtin.is_test)
        return;

    if (!config.load()) {
        logger.info("Doorstop not enabled! Skipping!", .{});
        return;
    }

    logger.debug("Doorstop started!", .{});

    var program_path_buf = util.paths.ProgramPathBuf{};
    const app_path = program_path_buf.get();
    const app_dir = util.paths.getFolderName(util.os_char, app_path);
    logger.debug("Executable path: {}", .{util.fmtString(app_path)});
    logger.debug("Application dir: {}", .{util.fmtString(app_dir)});

    const working_dir = util.paths.getWorkingDir();
    defer alloc.free(working_dir);
    logger.debug("Working dir: {}", .{util.fmtString(working_dir)});

    var doorstop_path_buf = util.paths.ModulePathBuf{};
    const doorstop_path = doorstop_path_buf.get(switch (builtin.os.tag) {
        .windows => windows.doorstop_module.?,
        // on *nix we just need an address in the library
        else => &entrypoint,
    }).?;

    logger.debug("Doorstop library path: {}", .{util.fmtString(doorstop_path)});

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

    const LoadReason = enum(std.os.windows.DWORD) {
        PROCESS_DETACH = 0,
        PROCESS_ATTACH = 1,
        THREAD_ATTACH = 2,
        THREAD_DETACH = 3,
    };

    export fn DllEntry(
        hInstDll: std.os.windows.HINSTANCE,
        reasonForDllLoad: LoadReason,
        _: std.os.windows.LPVOID,
    ) callconv(.winapi) std.os.windows.BOOL {
        doorstop_module = @ptrCast(hInstDll);

        if (reasonForDllLoad == LoadReason.PROCESS_DETACH) {
            // similarly to above, I'm not sure why they only do this on Windows.
            util.setEnv("DOORSTOP_DISABLE", null);
        }

        if (reasonForDllLoad != LoadReason.PROCESS_ATTACH) {
            return std.os.windows.TRUE;
        }

        entrypoint();

        return std.os.windows.TRUE;
    }
};
