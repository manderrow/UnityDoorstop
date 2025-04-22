const builtin = @import("builtin");
const std = @import("std");

const root = @import("root.zig");
const alloc = root.alloc;
const logger = root.logger;
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
            var program_path_buf: util.paths.ProgramPathBuf = undefined;
            const program_path = program_path_buf.get();
            const app_folder = util.paths.getFolderName(u8, util.paths.getFolderName(u8, program_path));

            break :blk std.fmt.allocPrintZ(
                alloc,
                "{s}/Resources/Data/boot.config",
                .{app_folder},
            ) catch @panic("Out of memory");
        },
        else => blk: {
            var program_path_buf: util.paths.ProgramPathBuf = undefined;
            const program_path = program_path_buf.get();
            const file_name = util.paths.getFileName(os_char, program_path, false);

            break :blk std.mem.concatWithSentinel(alloc, os_char, &.{
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
    target_function_name: [:0]const u8,
    target_function: anytype,
    detour_function: @TypeOf(target_function),
    msg: []const u8,
) void {
    tryIatHookUntyped(dll, target_dll, target_function_name, detour_function, msg);
}

fn tryIatHookUntyped(
    dll: std.os.windows.HMODULE,
    target_dll: [:0]const u8,
    target_function_name: [:0]const u8,
    detour_function: *const anyopaque,
    msg: []const u8,
) void {
    const target_dll_wide = std.unicode.utf8ToUtf16LeAllocZ(alloc, target_dll) catch |e| {
        logger.err("Failed to hook {s}. Error: {}", .{ msg, e });
        return;
    };
    defer alloc.free(target_dll_wide);
    const target_module = std.os.windows.kernel32.GetModuleHandleW(target_dll_wide) orelse {
        const e = std.os.windows.unexpectedError(std.os.windows.GetLastError()) catch {};
        logger.err("Failed to hook {s}. Error: {}", .{ msg, e });
        return;
    };
    // Need to GetProcAddress instead of simply using the target_function address, because the target_function may be a
    // "stub" function embedded in our DLL that invokes the real function.
    const result: *const anyopaque = std.os.windows.kernel32.GetProcAddress(target_module, target_function_name) orelse {
        const e = std.os.windows.unexpectedError(std.os.windows.GetLastError()) catch {};
        logger.err("Failed to hook {s}. Error: {}", .{ msg, e });
        return;
    };
    iatHook(dll, target_dll, result, detour_function) catch |e| {
        logger.err("Failed to hook {s}. Error: {}", .{ msg, e });
    };
}

pub fn installHooksWindows() void {
    const module = std.os.windows.kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("UnityPlayer")) orelse blk: {
        logger.debug("No UnityPlayer module found! Using executable as the hook target.", .{});
        break :blk std.os.windows.kernel32.GetModuleHandleW(null).?;
    };

    tryIatHook(module, "kernel32.dll", "GetProcAddress", &std.os.windows.kernel32.GetProcAddress, @ptrCast(&dlsym_hook), "GetProcAddress");
    tryIatHook(module, "kernel32.dll", "CloseHandle", &windows.CloseHandle, &windows.close_handle_hook, "CloseHandle");

    if (hookBootConfigCommon()) |_| {
        tryIatHook(module, "kernel32.dll", "CreateFileW", &std.os.windows.kernel32.CreateFileW, &windows.createFileWHook, "CreateFileW. Might be unable to override boot config");
        tryIatHook(module, "kernel32.dll", "CreateFileA", &windows.CreateFileA, &windows.createFileAHook, "CreateFileA. Might be unable to override boot config");
    }
}

fn tryPltHook(hook: *plthook.c.plthook_t, funcname: [:0]const u8, funcaddr: *anyopaque, err_note: []const u8) void {
    if (plthook.c.plthook_replace(hook, funcname, funcaddr, null) != 0) {
        logger.err("Failed to hook {s}.{s} Error: {s}", .{ funcname, err_note, plthook.c.plthook_error() });
    } else {
        logger.debug("Hooked {s}", .{funcname});
    }
}

pub fn installHooksNix() void {
    const hook = plthook.openByFilename(comptime "UnityPlayer" ++ builtin.os.tag.dynamicLibSuffix()) catch |e| {
        const s: [*:0]const u8 = switch (e) {
            error.FileNotFound => "FileNotFound",
            else => plthook.c.plthook_error(),
        };
        std.debug.panic("Failed to open PLT on UnityPlayer: {s}", .{s});
    };
    defer plthook.c.plthook_close(hook);

    logger.debug("Found UnityPlayer, hooking into it", .{});

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
            logger.err("Failed to hook mono_jit_init_version. Error: {s}", .{plthook.c.plthook_error()});
        } else {
            logger.debug("Hooked mono_jit_init_version", .{});
            const mono_handle = plthook.system.handleByFilename(comptime "libmono" ++ builtin.os.tag.dynamicLibSuffix());
            if (mono_handle) |handle| {
                runtimes.mono.load(handle);
            }
        }
    }
}

var initialized = false;

const RedirectInitArgs = struct {
    name: []const u8,
    init_func: *const fn (handle: util.Module(false)) void,
    target: *const anyopaque,
    should_capture_mono_path: bool,
};

fn redirectInit(
    handle: util.Module(false),
    name: [:0]const u8,
    args: RedirectInitArgs,
) ?*anyopaque {
    if (std.mem.eql(u8, name, args.name)) {
        if (!initialized) {
            initialized = true;
            logger.debug("Intercepted {s} from {}", .{ args.name, util.fmtAddress(handle) });
            // the old code had the next two bits swapped on nix. Test and see if it matters.
            if (args.should_capture_mono_path) {
                // Resolve dlsym so that it can be passed to capture_mono_path.
                // On Unix, we use dladdr which allows to use arbitrary symbols for
                // resolving their location.
                // However, using handle seems to cause issues on some distros, so we pass
                // the resolved symbol instead.
                // TODO: document specific cases
                var buf: util.paths.ModulePathBuf = undefined;
                const path = buf.get(switch (builtin.os.tag) {
                    .windows => handle,
                    else => std.c.dlsym(handle, name),
                }) orelse std.debug.panic("Failed to resolve path to module {}", .{util.fmtAddress(handle)});
                util.setEnv("DOORSTOP_MONO_LIB_PATH", path);
            }
            args.init_func(handle);
            logger.debug("Loaded all runtime functions", .{});
        }
        return @constCast(args.target);
    }
    return null;
}

const bootstrap = @import("bootstrap.zig");
const runtimes = @import("runtimes.zig");

fn dlsym_hook(handle: util.Module(false), name_ptr: [*:0]const u8) callconv(if (builtin.os.tag == .windows) .winapi else .c) ?*anyopaque {
    if (builtin.os.tag == .windows and @intFromPtr(name_ptr) >> 16 == 0) {
        // documented that if the "HIWORD" is 0, the name_ptr actually specifies an ordinal.
        logger.debug("dlsym({}, {})", .{ util.fmtAddress(handle), @intFromPtr(name_ptr) });
        return std.os.windows.kernel32.GetProcAddress(handle, name_ptr);
    }

    const name = std.mem.span(name_ptr);

    logger.debug("dlsym({}, \"{s}\")", .{ util.fmtAddress(handle), name });

    for ([_]RedirectInitArgs{
        .{ .name = "il2cpp_init", .init_func = &runtimes.il2cpp.load, .target = &bootstrap.init_il2cpp, .should_capture_mono_path = false },
        .{ .name = "mono_jit_init_version", .init_func = &runtimes.mono.load, .target = &bootstrap.init_mono, .should_capture_mono_path = true },
        .{ .name = "mono_image_open_from_data_with_name", .init_func = &runtimes.mono.load, .target = &bootstrap.hook_mono_image_open_from_data_with_name, .should_capture_mono_path = true },
        .{ .name = "mono_jit_parse_options", .init_func = &runtimes.mono.load, .target = &bootstrap.hook_mono_jit_parse_options, .should_capture_mono_path = true },
        .{ .name = "mono_debug_init", .init_func = &runtimes.mono.load, .target = &bootstrap.hook_mono_debug_init, .should_capture_mono_path = true },
    }) |args| {
        if (redirectInit(handle, name, args)) |ptr| {
            return ptr;
        }
    }

    return switch (builtin.os.tag) {
        .windows => std.os.windows.kernel32.GetProcAddress(handle, name),
        else => std.c.dlsym(handle, name),
    };
}
