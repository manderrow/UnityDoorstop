const builtin = @import("builtin");
const std = @import("std");

const root = @import("root.zig");
const alloc = root.alloc;
const util = root.util;

const plthook = @import("plthook");
const iatHook = if (builtin.os.tag == .windows) @import("windows/iat_hook.zig").iatHook;

const nix = if (builtin.os.tag != .windows) @import("nix/hooks.zig");
pub const windows = if (builtin.os.tag == .windows) @import("windows/hooks.zig");

const os_char = util.os_char;

pub var defaultBootConfig: util.file_identity.FileIdentity = undefined;

fn hookBootConfigCommon() ?[*:0]const os_char {
    const boot_config_override = root.config.boot_config_override orelse return null;

    const path = switch (builtin.os.tag) {
        .macos => blk: {
            var program_path_buf = util.paths.ProgramPathBuf{};
            const program_path = program_path_buf.get();
            const app_folder = util.paths.getFolderNameRef(u8, util.paths.getFolderNameRef(u8, program_path));

            break :blk std.fmt.allocPrintZ(
                alloc,
                "{s}/Resources/Data/boot.config",
                .{app_folder},
            ) catch @panic("Out of memory");
        },
        else => blk: {
            const working_dir = util.paths.getWorkingDir();
            defer alloc.free(working_dir);
            var program_path_buf = util.paths.ProgramPathBuf{};
            const program_path = program_path_buf.get();
            const file_name = util.paths.getFileNameRef(os_char, program_path, false);

            break :blk std.mem.concatWithSentinel(alloc, os_char, &.{
                working_dir,
                util.osStrLiteral(std.fs.path.sep_str),
                file_name,
                util.osStrLiteral("_Data" ++ std.fs.path.sep_str ++ "boot.config"),
            }, 0) catch @panic("Out of memory");
        },
    };
    defer alloc.free(path);

    defaultBootConfig = util.file_identity.getFileIdentity(null, path) catch |e| {
        std.debug.panic("Failed to get identity of default boot.config file at \"{s}\": {}", .{
            if (builtin.os.tag == .windows) std.unicode.fmtUtf16Le(path) else path,
            e,
        });
    };

    const access = switch (builtin.os.tag) {
        .windows => std.fs.Dir.accessW,
        else => std.fs.Dir.accessZ,
    };
    access(std.fs.cwd(), boot_config_override, .{}) catch |e| {
        std.debug.panic("Boot config override is inaccessible: {}", .{e});
    };

    return boot_config_override;
}

fn tryIatHook(
    dll: std.os.windows.HMODULE,
    target_dll: [:0]const u8,
    target_function: anytype,
    detour_function: @TypeOf(target_function),
    msg: []const u8,
) void {
    tryIatHookUntyped(dll, target_dll, target_function, detour_function, msg);
}

fn tryIatHookUntyped(
    dll: std.os.windows.HMODULE,
    target_dll: [:0]const u8,
    target_function: anytype,
    detour_function: @TypeOf(target_function),
    msg: []const u8,
) void {
    iatHook(dll, target_dll, target_function, detour_function) catch |e| {
        root.logger.err("Failed to hook {s}. Error: {}", .{ msg, e });
    };
}

pub fn installHooksWindows(module: std.os.windows.HMODULE) callconv(.c) void {
    tryIatHook(module, "kernel32.dll", @constCast(&std.os.windows.kernel32.GetProcAddress), @constCast(&dlsym_hook), "GetProcAddress");
    tryIatHook(module, "kernel32.dll", @constCast(&windows.CloseHandle), @constCast(&windows.close_handle_hook), "CloseHandle");

    if (hookBootConfigCommon()) |_| {
        tryIatHook(module, "kernel32.dll", @constCast(&std.os.windows.kernel32.CreateFileW), @constCast(&windows.createFileWHook), "CreateFileW. Might be unable to override boot config");
        tryIatHook(module, "kernel32.dll", @constCast(&windows.CreateFileA), @constCast(&windows.createFileAHook), "CreateFileA. Might be unable to override boot config");
    }
}

fn tryPltHook(hook: *plthook.c.plthook_t, funcname: [:0]const u8, funcaddr: *anyopaque, err_note: []const u8) void {
    if (plthook.c.plthook_replace(hook, funcname, funcaddr, null) != 0) {
        root.logger.err("Failed to hook {s}.{s} Error: {s}", .{ funcname, err_note, plthook.c.plthook_error() });
    } else {
        root.logger.debug("Hooked {s}", .{funcname});
    }
}

pub fn installHooksNix() callconv(.c) void {
    const hook = plthook.openByFilename(comptime "UnityPlayer" ++ builtin.os.tag.dynamicLibSuffix()) catch |e| {
        const s: [*:0]const u8 = switch (e) {
            error.FileNotFound => "FileNotFound",
            else => plthook.c.plthook_error(),
        };
        std.debug.panic("Failed to open PLT on UnityPlayer: {s}", .{s});
    };
    defer plthook.c.plthook_close(hook);

    root.logger.debug("Found UnityPlayer, hooking into it", .{});

    tryPltHook(hook, "dlsym", @constCast(&dlsym_hook), " Initialization might be impossible.");

    if (hookBootConfigCommon()) |_| {
        if (builtin.os.tag == .linux) {
            tryPltHook(hook, "fopen64", @constCast(&nix.fopen64Hook), " Might be unable to override boot config.");
        }
        tryPltHook(hook, "fopen", @constCast(&nix.fopenHook), " Might be unable to override boot config.");
    }

    tryPltHook(hook, "fclose", @constCast(&nix.fcloseHook), "");

    tryPltHook(hook, "dup2", @constCast(&nix.dup2Hook), "");

    if (builtin.os.tag == .macos) {
        // On older Unity versions, Mono methods are resolved by the OS's
        // loader directly. Because of this, there is no dlsym, in which case we
        // need to apply a PLT hook.
        if (plthook.c.plthook_replace(hook, "mono_jit_init_version", @constCast(&bootstrap.init_mono), null) != 0) {
            root.logger.err("Failed to hook mono_jit_init_version. Error: {s}", .{plthook.c.plthook_error()});
        } else {
            root.logger.debug("Hooked mono_jit_init_version", .{});
            const mono_handle = plthook.system.handleByFilename(comptime "libmono" ++ builtin.os.tag.dynamicLibSuffix());
            if (mono_handle) |handle| {
                runtimes.mono.load(handle);
            }
        }
    }
}

var initialized = false;

fn redirect_init(
    handle: util.Module(false),
    name: [:0]const u8,
    comptime init_name: []const u8,
    comptime init_func: anytype,
    comptime target: anytype,
    comptime should_capture_mono_path: bool,
) ?*anyopaque {
    if (std.mem.eql(u8, name, init_name)) {
        if (!initialized) {
            initialized = true;
            root.logger.debug("Intercepted {s} from {}", .{ init_name, util.fmtAddress(handle) });
            // the old code had the next two bits swapped on nix. Test and see if it matters.
            if (should_capture_mono_path) {
                // Resolve dlsym so that it can be passed to capture_mono_path.
                // On Unix, we use dladdr which allows to use arbitrary symbols for
                // resolving their location.
                // However, using handle seems to cause issues on some distros, so we pass
                // the resolved symbol instead.
                // TODO: document specific cases
                var buf = util.paths.ModulePathBuf{};
                const path = buf.get(switch (builtin.os.tag) {
                    .windows => handle,
                    else => std.c.dlsym(handle, name),
                }) orelse std.debug.panic("Failed to resolve path to module {}", .{util.fmtAddress(handle)});
                util.setEnv("DOORSTOP_MONO_LIB_PATH", path);
            }
            init_func(handle);
            root.logger.debug("Loaded all runtime functions", .{});
        }
        return @constCast(target);
    }
    return null;
}

const bootstrap = @import("bootstrap.zig");
const runtimes = @import("runtimes.zig");

fn dlsym_hook(handle: util.Module(false), name_ptr: [*:0]const u8) callconv(if (builtin.os.tag == .windows) .winapi else .c) ?*anyopaque {
    const name = std.mem.span(name_ptr);

    if (builtin.mode == .Debug) {
        root.logger.debug("dlsym({}, \"{s}\")", .{ util.fmtAddress(handle), name });
    }

    inline for (.{
        .{ "il2cpp_init", runtimes.il2cpp.load, &bootstrap.init_il2cpp, false },
        .{ "mono_jit_init_version", runtimes.mono.load, &bootstrap.init_mono, true },
        .{ "mono_image_open_from_data_with_name", runtimes.mono.load, &bootstrap.hook_mono_image_open_from_data_with_name, true },
        .{ "mono_jit_parse_options", runtimes.mono.load, &bootstrap.hook_mono_jit_parse_options, true },
        .{ "mono_debug_init", runtimes.mono.load, &bootstrap.hook_mono_debug_init, true },
    }) |args| {
        if (redirect_init(handle, name, args[0], args[1], args[2], args[3])) |ptr| {
            return ptr;
        }
    }

    switch (builtin.os.tag) {
        .windows => {
            if (std.os.windows.kernel32.GetProcAddress(handle, name)) |ptr| return ptr;

            return @import("windows/proxy.zig").proxyGetProcAddress(handle, name);
        },
        else => return std.c.dlsym(handle, name),
    }
}
