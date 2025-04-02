const builtin = @import("builtin");
const std = @import("std");

const root = @import("root.zig");

pub fn entrypoint() callconv(.c) void {
    if (builtin.is_test)
        return;

    root.logger.info("Injecting", .{});

    root.config.load();

    if (!root.config.enabled) {
        root.logger.info("Doorstop not enabled! Skipping!", .{});
        return;
    }

    switch (builtin.os.tag) {
        // windows
        .windows => {
            root.hooks.windows.stdout_handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch null;
            root.hooks.windows.stderr_handle = std.os.windows.GetStdHandle(std.os.windows.STD_ERROR_HANDLE) catch null;

            root.logger.debug("Standard output handle at {}", .{root.util.fmtAddress(root.hooks.windows.stdout_handle)});
            root.logger.debug("Standard error handle at {}", .{root.util.fmtAddress(root.hooks.windows.stderr_handle)});
            // char_t handle_path[MAX_PATH] = L"";
            // GetFinalPathNameByHandle(stdout_handle, handle_path, MAX_PATH, 0);
            // LOG("Standard output handle path: %" Ts, handle_path);

            const doorstop_path = root.util.paths.getModulePath(windows.doorstop_module.?).?;
            defer doorstop_path.deinit();
            @import("windows/proxy.zig").loadProxy(doorstop_path.result);

            const target_module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("UnityPlayer")) orelse blk: {
                root.logger.debug("No UnityPlayer module found! Using executable as the hook target.", .{});
                break :blk std.os.windows.kernel32.GetModuleHandleW(null).?;
            };

            root.hooks.installHooksWindows(target_module);
        },
        else => root.hooks.installHooksNix(),
    }

    root.logger.info("Injected hooks", .{});
    if (builtin.os.tag == .windows) {
        @import("windows/util.zig").SetEnvironmentVariable("DOORSTOP_DISABLE", std.unicode.utf8ToUtf16LeStringLiteral("1"));
    }
}

comptime {
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
            @import("windows/util.zig").SetEnvironmentVariable("DOORSTOP_DISABLE", null);
        }

        if (reasonForDllLoad != LoadReason.PROCESS_ATTACH) {
            return std.os.windows.TRUE;
        }

        root.entrypoint.entrypoint();

        return std.os.windows.TRUE;
    }
};
