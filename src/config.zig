const builtin = @import("builtin");
const std = @import("std");

const root = @import("root.zig");
const alloc = root.alloc;
const logger = root.logger;
const os_char = root.util.os_char;

const header = @cImport({
    @cInclude("config/config.h");
});

/// Path to a custom boot.config file to use. If specified, this file takes
/// precedence over the default one in the game's Data folder.
boot_config_override: ?[:0]const os_char = null,

comptime c: *header.Config = &c_instance,

pub var instance = @This(){};

var c_instance = header.Config{
    .enabled = false,
    .mono_debug_enabled = false,
    .mono_debug_suspend = false,
    .mono_debug_address = null,
    .target_assembly = null,
    .mono_dll_search_path_override = null,
    .clr_corlib_dir = null,
    .clr_runtime_coreclr_path = null,
};

comptime {
    @export(&c_instance, .{ .name = "config" });
}

fn freeNonNull(ptr: anytype) void {
    if (ptr) |ptr_non_null| {
        alloc.free(std.mem.span(ptr_non_null));
    }
}

const EnvKey = switch (builtin.os.tag) {
    .windows => struct { utf8: []const u8, os: [*:0]const u16 },
    else => []const u8,
};

fn getEnvKeyLiteral(comptime key: []const u8) EnvKey {
    return switch (builtin.os.tag) {
        .windows => .{ .utf8 = key, .os = comptime std.unicode.utf8ToUtf16LeStringLiteral(key) },
        else => key,
    };
}

inline fn getEnvBool(comptime key: []const u8) bool {
    return getEnvBoolOs(getEnvKeyLiteral(key));
}

fn invalidEnvValue(key: []const u8, value: [:0]const os_char) noreturn {
    @branchHint(.cold);
    std.debug.panic("Invalid value for environment variable {s}: {s}", .{ key, switch (builtin.os.tag) {
        .windows => std.unicode.fmtUtf16Le(value),
        else => value,
    } });
}

fn getEnvBoolOs(key: EnvKey) bool {
    const text = switch (builtin.os.tag) {
        .windows => std.process.getenvW(key.os),
        else => std.posix.getenv(key),
    } orelse return false;
    if (text[0] != 0 and text[1] == 0) {
        switch (text[0]) {
            '0' => return false,
            '1' => return true,
            else => {},
        }
    }
    invalidEnvValue(switch (builtin.os.tag) {
        .windows => key.utf8,
        else => key,
    }, text);
}

inline fn getEnvStrRef(comptime key: []const u8) ?[:0]const os_char {
    switch (builtin.os.tag) {
        .windows => {
            const key_w = comptime std.unicode.utf8ToUtf16LeStringLiteral(key);
            return std.process.getenvW(key_w);
        },
        else => {
            return std.posix.getenv(key);
        },
    }
}

fn getEnvStr(comptime key: []const u8) ?[:0]const os_char {
    switch (builtin.os.tag) {
        .windows => {
            return alloc.dupeZ(u16, getEnvStrRef(key) orelse return null) catch @panic("Out of memory");
        },
        else => {
            return alloc.dupeZ(u8, getEnvStrRef(key) orelse return null) catch @panic("Out of memory");
        },
    }
}

fn getEnvPath(comptime key: []const u8) ?[:0]const os_char {
    const path = getEnvStr(key) orelse return null;
    checkEnvPath(key, path);
    return path;
}

fn checkEnvPath(key: []const u8, path: [:0]const os_char) void {
    switch (builtin.os.tag) {
        .windows => {
            // TODO: sanity check that path is absolute
        },
        else => {
            if (path[0] != '/') {
                invalidEnvValue(key, path);
            }
        },
    }
}

export fn load_config() void {
    c_instance.enabled = getEnvBool("DOORSTOP_ENABLED");
    const ignore_disabled_env = getEnvBool("DOORSTOP_IGNORE_DISABLED_ENV");
    if (c_instance.enabled and !ignore_disabled_env and getEnvBool("DOORSTOP_DISABLE")) {
        // This is sometimes useful with Steam games that break env var isolation.
        logger.debug("DOORSTOP_DISABLE is set! Disabling Doorstop!", .{});
        c_instance.enabled = false;
    }
    c_instance.mono_debug_enabled = getEnvBool("DOORSTOP_MONO_DEBUG_ENABLED");
    c_instance.mono_debug_suspend = getEnvBool("DOORSTOP_MONO_DEBUG_SUSPEND");
    c_instance.mono_debug_address = getEnvStr("DOORSTOP_MONO_DEBUG_ADDRESS") orelse null;
    c_instance.mono_dll_search_path_override = getEnvStr("DOORSTOP_MONO_DLL_SEARCH_PATH_OVERRIDE") orelse null;
    c_instance.target_assembly = getEnvPath("DOORSTOP_TARGET_ASSEMBLY") orelse null;
    if (c_instance.target_assembly == null) {
        @panic("DOORSTOP_TARGET_ASSEMBLY environment variable must be set");
    }
    instance.boot_config_override = getEnvPath("DOORSTOP_BOOT_CONFIG_OVERRIDE");
    c_instance.clr_runtime_coreclr_path = getEnvPath("DOORSTOP_CLR_RUNTIME_CORECLR_PATH") orelse null;
    c_instance.clr_corlib_dir = getEnvPath("DOORSTOP_CLR_CORLIB_DIR") orelse null;
}

// not used right now. Export if we want to use it in the future.
fn cleanup_config() void {
    freeNonNull(c_instance.mono_debug_address);
    freeNonNull(c_instance.mono_dll_search_path_override);
    alloc.free(std.mem.span(c_instance.target_assembly.?));
    if (instance.boot_config_override) |ptr| alloc.free(ptr);
    freeNonNull(c_instance.clr_runtime_coreclr_path);
    freeNonNull(c_instance.clr_corlib_dir);
}
