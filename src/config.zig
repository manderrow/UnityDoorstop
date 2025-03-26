const builtin = @import("builtin");
const std = @import("std");

const alloc = @import("root.zig").alloc;
const logger = @import("util/logging.zig").logger;

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

fn getEnvBool(comptime name: []const u8) bool {
    return (std.process.parseEnvVarInt(name, u1, 2) catch |e| switch (e) {
        error.EnvironmentVariableNotFound => 0,
        else => std.debug.panic("Invalid value for environment variable {s}", .{name}),
    }) != 0;
}

fn getEnvValue(name: []const u8) ?[]u8 {
    return std.process.getEnvVarOwned(alloc, name) catch |e| switch (e) {
        error.OutOfMemory => @panic("Out of memory"),
        error.EnvironmentVariableNotFound => null,
        error.InvalidWtf8 => std.debug.panic("Invalid value for environment variable {s}", .{name}),
    };
}

const char = switch (builtin.os.tag) {
    .windows => u16,
    else => u8,
};

fn toCStr(name: []const u8, str: []u8) [:0]const char {
    switch (builtin.os.tag) {
        .windows => {
            defer alloc.free(str);
            return std.unicode.utf8ToUtf16LeAllocZ(alloc, str) catch |e| switch (e) {
                error.OutOfMemory => @panic("Out of memory"),
                error.InvalidUtf8 => std.debug.panic("Environment variable {s} contains invalid UTF-8", .{name}),
            };
        },
        else => {
            var buf = std.ArrayListUnmanaged(u8){ .items = str };
            defer buf.deinit(alloc);
            return buf.toOwnedSliceSentinel(alloc, 0) catch |e| switch (e) {
                error.OutOfMemory => @panic("Out of memory"),
            };
        },
    }
}

fn getEnvStr(name: []const u8) ?[:0]const char {
    const str = getEnvValue(name) orelse return null;
    return toCStr(name, str);
}

fn getEnvPath(name: []const u8) ?[:0]const char {
    const unresolved_path = getEnvValue(name) orelse return null;
    defer alloc.free(unresolved_path);
    const path = std.fs.path.resolve(alloc, &.{unresolved_path}) catch |e| switch (e) {
        error.OutOfMemory => @panic("Out of memory"),
        // else => std.debug.panic("Failed to resolve path specified in environment variable {s}: {}", .{ name, e }),
    };
    return toCStr(name, path);
}

export fn load_config() void {
    config.enabled = getEnvBool("DOORSTOP_ENABLED");
    config.redirect_output_log = getEnvBool("DOORSTOP_REDIRECT_OUTPUT_LOG");
    config.ignore_disabled_env = getEnvBool("DOORSTOP_IGNORE_DISABLED_ENV");
    config.mono_debug_enabled = getEnvBool("DOORSTOP_MONO_DEBUG_ENABLED");
    config.mono_debug_suspend = getEnvBool("DOORSTOP_MONO_DEBUG_SUSPEND");
    config.mono_debug_address = @ptrCast(getEnvStr("DOORSTOP_MONO_DEBUG_ADDRESS"));
    config.target_assembly = @ptrCast(getEnvPath("DOORSTOP_TARGET_ASSEMBLY"));
    config.boot_config_override = @ptrCast(getEnvPath("DOORSTOP_BOOT_CONFIG_OVERRIDE"));
    config.mono_dll_search_path_override = @ptrCast(getEnvStr("DOORSTOP_MONO_DLL_SEARCH_PATH_OVERRIDE"));
    config.clr_runtime_coreclr_path = @ptrCast(getEnvPath("DOORSTOP_CLR_RUNTIME_CORECLR_PATH"));
    config.clr_corlib_dir = @ptrCast(getEnvPath("DOORSTOP_CLR_CORLIB_DIR"));
}

export fn cleanup_config() void {
    freeNonNull(config.target_assembly);
    freeNonNull(config.boot_config_override);
    freeNonNull(config.mono_dll_search_path_override);
    freeNonNull(config.clr_corlib_dir);
    freeNonNull(config.clr_runtime_coreclr_path);
    freeNonNull(config.mono_debug_address);
}
