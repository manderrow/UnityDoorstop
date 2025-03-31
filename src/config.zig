const builtin = @import("builtin");
const std = @import("std");

const alloc = @import("root.zig").alloc;
const logger = @import("util/logging.zig").logger;
const os_char = @import("util.zig").os_char;

const header = @cImport({
    @cInclude("config/config.h");
});

export var config: header.Config = .{
    .enabled = false,
    .ignore_disabled_env = false,
    .redirect_output_log = false,
    .mono_debug_enabled = false,
    .mono_debug_suspend = false,
    .mono_debug_address = null,
    .target_assembly = null,
    .boot_config_override = null,
    .mono_dll_search_path_override = null,
    .clr_corlib_dir = null,
    .clr_runtime_coreclr_path = null,
};

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

fn getEnvBoolOs(key: EnvKey) bool {
    switch (builtin.os.tag) {
        .windows => {
            const text = std.process.getenvW(key.os) orelse return false;
            if (text[0] != 0 and text[1] == 0) {
                switch (text[0]) {
                    '0' => return false,
                    '1' => return true,
                    else => {},
                }
            }
            std.debug.panic("Invalid value for environment variable {s}: {s}", .{ key.utf8, std.unicode.fmtUtf16Le(text) });
        },
        else => {
            const text = std.posix.getenv(key) orelse return false;
            if (text[0] != 0 and text[1] == 0) {
                switch (text[0]) {
                    '0' => return false,
                    '1' => return true,
                    else => {},
                }
            }
            std.debug.panic("Invalid value for environment variable {s}: {s}", .{ key, text });
        },
    }
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

fn getEnvStr(comptime key: []const u8) ?[*:0]const os_char {
    switch (builtin.os.tag) {
        .windows => {
            return alloc.dupeZ(u16, getEnvStrRef(key) orelse return null) catch @panic("Out of memory");
        },
        else => {
            return alloc.dupeZ(u8, getEnvStrRef(key) orelse return null) catch @panic("Out of memory");
        },
    }
}

fn getEnvPath(comptime key: []const u8) ?[*:0]const os_char {
    const path = getEnvStr(key) orelse return null;
    checkEnvPath(key, path);
    return path;
}

fn checkEnvPath(key: []const u8, path: [*:0]const os_char) void {
    switch (builtin.os.tag) {
        .windows => {
            // TODO: sanity check that path is absolute
        },
        else => {
            if (path[0] != '/') {
                std.debug.panic("Invalid value for environment variable {s}: {s}", .{ key, path });
            }
        },
    }
}

export fn load_config() void {
    config.enabled = getEnvBool("DOORSTOP_ENABLED");
    config.redirect_output_log = getEnvBool("DOORSTOP_REDIRECT_OUTPUT_LOG");
    config.ignore_disabled_env = getEnvBool("DOORSTOP_IGNORE_DISABLED_ENV");
    config.mono_debug_enabled = getEnvBool("DOORSTOP_MONO_DEBUG_ENABLED");
    config.mono_debug_suspend = getEnvBool("DOORSTOP_MONO_DEBUG_SUSPEND");
    config.mono_debug_address = getEnvStr("DOORSTOP_MONO_DEBUG_ADDRESS");
    config.mono_dll_search_path_override = getEnvStr("DOORSTOP_MONO_DLL_SEARCH_PATH_OVERRIDE");
    config.target_assembly = getEnvPath("DOORSTOP_TARGET_ASSEMBLY");
    if (config.target_assembly == null) {
        @panic("DOORSTOP_TARGET_ASSEMBLY environment variable must be set");
    }
    config.boot_config_override = getEnvPath("DOORSTOP_BOOT_CONFIG_OVERRIDE");
    config.clr_runtime_coreclr_path = getEnvPath("DOORSTOP_CLR_RUNTIME_CORECLR_PATH");
    config.clr_corlib_dir = getEnvPath("DOORSTOP_CLR_CORLIB_DIR");
}

// not used right now. Export if we want to use it in the future.
fn cleanup_config() void {
    freeNonNull(config.mono_debug_address);
    freeNonNull(config.mono_dll_search_path_override);
    alloc.free(std.mem.span(config.target_assembly.?));
    freeNonNull(config.boot_config_override);
    freeNonNull(config.clr_runtime_coreclr_path);
    freeNonNull(config.clr_corlib_dir);
}
