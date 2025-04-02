const builtin = @import("builtin");
const std = @import("std");

const root = @import("root.zig");
const alloc = root.alloc;
const logger = root.logger;
const os_char = root.util.os_char;

/// Whether Doorstop is enabled.
enabled: bool = false,

/// Path to a managed assembly to invoke.
target_assembly: ?[:0]const os_char = null,

/// Path to use as the main DLL search path. If enabled, this folder
/// takes precedence over the default Managed folder.
mono_dll_search_path_override: ?[:0]const os_char = null,

/// Whether to enable the mono debugger.
mono_debug_enabled: bool = false,

/// Whether to enable the debugger in suspended state.
///
/// If enabled, the runtime will force the game to wait until a debugger is
/// connected.
mono_debug_suspend: bool = false,

/// Debug address to use for the mono debugger.
mono_debug_address: ?[:0]const os_char = null,

/// Path to the CoreCLR runtime library.
clr_runtime_coreclr_path: ?[:0]const os_char = null,

/// Path to the CoreCLR core libraries folder.
clr_corlib_dir: ?[:0]const os_char = null,

/// Path to a custom boot.config file to use. If specified, this file takes
/// precedence over the default one in the game's Data folder.
boot_config_override: ?[:0]const os_char = null,

pub var instance = @This(){};

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

pub fn load(self: *@This()) void {
    var enabled = getEnvBool("DOORSTOP_ENABLED");
    const ignore_disabled_env = getEnvBool("DOORSTOP_IGNORE_DISABLED_ENV");
    if (enabled and !ignore_disabled_env and getEnvBool("DOORSTOP_DISABLE")) {
        // This is sometimes useful with Steam games that break env var isolation.
        logger.debug("DOORSTOP_DISABLE is set! Disabling Doorstop!", .{});
        enabled = false;
    }
    self.* = .{
        .enabled = enabled,
        .mono_debug_enabled = getEnvBool("DOORSTOP_MONO_DEBUG_ENABLED"),
        .mono_debug_suspend = getEnvBool("DOORSTOP_MONO_DEBUG_SUSPEND"),
        .mono_debug_address = getEnvStr("DOORSTOP_MONO_DEBUG_ADDRESS"),
        .mono_dll_search_path_override = getEnvStr("DOORSTOP_MONO_DLL_SEARCH_PATH_OVERRIDE"),
        .target_assembly = getEnvPath("DOORSTOP_TARGET_ASSEMBLY") orelse @panic("DOORSTOP_TARGET_ASSEMBLY environment variable must be set"),
        .boot_config_override = getEnvPath("DOORSTOP_BOOT_CONFIG_OVERRIDE"),
        .clr_runtime_coreclr_path = getEnvPath("DOORSTOP_CLR_RUNTIME_CORECLR_PATH"),
        .clr_corlib_dir = getEnvPath("DOORSTOP_CLR_CORLIB_DIR"),
    };

    c.target_assembly = self.target_assembly orelse null;
    c.mono_dll_search_path_override = self.mono_dll_search_path_override orelse null;
    c.mono_debug_enabled = self.mono_debug_enabled;
    c.mono_debug_suspend = self.mono_debug_suspend;
    c.mono_debug_address = self.mono_debug_address orelse null;
    c.clr_runtime_coreclr_path = self.clr_runtime_coreclr_path orelse null;
    c.clr_corlib_dir = self.clr_corlib_dir orelse null;
}

// not used right now. Export if we want to use it in the future.
fn deinit(self: *@This()) void {
    freeNonNull(self.mono_debug_address);
    freeNonNull(self.mono_dll_search_path_override);
    alloc.free(std.mem.span(self.target_assembly.?));
    if (self.boot_config_override) |ptr| alloc.free(ptr);
    freeNonNull(self.clr_runtime_coreclr_path);
    freeNonNull(self.clr_corlib_dir);

    self.* = undefined;
}

const c = struct {
    export var target_assembly: ?[*:0]const os_char = null;
    export var mono_dll_search_path_override: ?[*:0]const os_char = null;
    export var mono_debug_enabled: bool = false;
    export var mono_debug_suspend: bool = false;
    export var mono_debug_address: ?[*:0]const os_char = null;
    export var clr_runtime_coreclr_path: ?[*:0]const os_char = null;
    export var clr_corlib_dir: ?[*:0]const os_char = null;
};

comptime {
    _ = c;
}
