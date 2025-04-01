const builtin = @import("builtin");
const std = @import("std");

const root = @import("root.zig");
const alloc = root.alloc;
const util = root.util;

const os_char = util.os_char;

const panicWindowsError = @import("windows/util.zig").panicWindowsError;

comptime {
    _ = switch (builtin.os.tag) {
        .windows => @import("windows/hooks.zig"),
        else => @import("nix/hooks.zig"),
    };
}

pub var defaultBootConfig: util.file_identity.FileIdentity = undefined;

/// The returned buffer is **not** allocated using `util.alloc`.
export fn initDefaultBootConfigPath() void {
    const path = switch (builtin.os.tag) {
        .macos => blk: {
            const program_path = util.paths.programPath();
            defer util.alloc.free(program_path);
            const app_folder = util.paths.getFolderNameRef(util.paths.getFolderNameRef(program_path));

            break :blk std.fmt.allocPrintZ(
                alloc,
                "{s}/Resources/Data/boot.config",
                .{app_folder},
            ) catch @panic("Out of memory");
        },
        .windows => blk: {
            const working_dir = util.paths.getWorkingDir();
            defer util.alloc.free(working_dir);
            const program_path = util.paths.programPath();
            defer util.alloc.free(program_path);
            const file_name = util.paths.getFileNameRef(program_path, false);

            const suffix_str = "_Data" ++ std.fs.path.sep_str ++ "boot.config";
            const suffix = switch (builtin.os.tag) {
                .windows => std.unicode.utf8ToUtf16LeStringLiteral(suffix_str),
                else => suffix_str,
            };

            var buf = std.ArrayListUnmanaged(os_char){};

            buf.ensureTotalCapacityPrecise(
                alloc,
                working_dir.len + 1 + file_name.len + suffix.len + 1,
            ) catch @panic("Out of memory");
            errdefer buf.deinit(alloc);

            buf.appendSliceAssumeCapacity(working_dir);
            buf.appendAssumeCapacity(std.fs.path.sep);
            buf.appendSliceAssumeCapacity(file_name);
            buf.appendSliceAssumeCapacity(suffix);
            buf.appendAssumeCapacity(0);

            break :blk buf.items[0 .. buf.items.len - 1 :0];
        },
        else => blk: {
            const working_dir = util.paths.getWorkingDir();
            defer util.alloc.free(working_dir);
            const program_path = util.paths.programPath();
            defer util.alloc.free(program_path);
            const file_name = util.paths.getFileNameRef(program_path, false);

            break :blk std.fmt.allocPrintZ(
                alloc,
                "{s}" ++ std.fs.path.sep_str ++ "{s}_Data" ++ std.fs.path.sep_str ++ "boot.config",
                .{ working_dir, file_name },
            ) catch @panic("Out of memory");
        },
    };

    defer alloc.free(path);

    defaultBootConfig = util.file_identity.getFileIdentity(null, path) catch |e| {
        std.debug.panic("Failed to get identity of default boot.config file at \"{s}\": {}", .{
            if (builtin.os.tag == .windows) std.unicode.fmtUtf16Le(path) else path,
            e,
        });
    };
}

fn capture_mono_path(handle: ?*anyopaque) void {
    const result = root.util.paths.getModulePath(@ptrCast(handle), 0).?;
    defer root.util.alloc.free(result.result);
    const name = "DOORSTOP_MONO_LIB_PATH";
    switch (builtin.os.tag) {
        .windows => {
            if (std.os.windows.kernel32.SetEnvironmentVariableW(comptime std.unicode.utf8ToUtf16LeStringLiteral(name), result.result) == 0) {
                panicWindowsError("SetEnvironmentVariableW", true);
            }
        },
        else => {
            const c = struct {
                extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
            };

            const rc = c.setenv(name, result.result, 1);
            switch (std.posix.errno(rc)) {
                .SUCCESS => {},
                .NOMEM => @panic("Out of memory"),
                else => |err| {
                    // INVAL is technically a possible error code from setenv, but we
                    // know the key is valid
                    std.debug.panic("unexpected errno: {d}\n", .{@intFromEnum(err)});
                },
            }
        },
    }
}

var initialized = false;

const Module = if (builtin.os.tag == .windows) std.os.windows.HMODULE else ?*anyopaque;

fn redirect_init(
    handle: Module,
    name: [:0]const u8,
    comptime init_name: []const u8,
    comptime init_func: anytype,
    comptime target: anytype,
    comptime should_capture_mono_path: bool,
) ?*anyopaque {
    if (std.mem.eql(u8, name, init_name)) {
        if (!initialized) {
            initialized = true;
            root.logger.debug("Intercepted {s} from {*}", .{ init_name, handle });
            // the old code had the next two bits swapped on nix. Test and see if it matters.
            if (should_capture_mono_path) {
                // Resolve dlsym so that it can be passed to capture_mono_path.
                // On Unix, we use dladdr which allows to use arbitrary symbols for
                // resolving their location.
                // However, using handle seems to cause issues on some distros, so we pass
                // the resolved symbol instead.
                capture_mono_path(std.c.dlsym(handle, name));
            }
            init_func(handle);
            root.logger.debug("Loaded all runtime functions", .{});
        }
        return @constCast(target);
    }
    return null;
}

const bootstrap = @cImport(@cInclude("bootstrap.h"));

export fn dlsym_hook(handle: Module, name_ptr: [*:0]const u8) ?*anyopaque {
    const name = std.mem.span(name_ptr);

    if (builtin.mode == .Debug) {
        root.logger.debug(std.fmt.comptimePrint("dlsym(0x{{?x:0>{}}}, \"{{s}}\")", .{@sizeOf(*anyopaque) * 2}), .{ handle, name });
    }

    inline for (.{
        .{ "il2cpp_init", bootstrap.load_il2cpp_funcs, &bootstrap.init_il2cpp, false },
        .{ "mono_jit_init_version", bootstrap.load_mono_funcs, &bootstrap.init_mono, true },
        .{ "mono_image_open_from_data_with_name", bootstrap.load_mono_funcs, &bootstrap.hook_mono_image_open_from_data_with_name, true },
        .{ "mono_jit_parse_options", bootstrap.load_mono_funcs, &bootstrap.hook_mono_jit_parse_options, true },
        .{ "mono_debug_init", bootstrap.load_mono_funcs, &bootstrap.hook_mono_debug_init, true },
    }) |args| {
        if (redirect_init(handle, name, args[0], args[1], args[2], args[3])) |ptr| {
            return ptr;
        }
    }

    return switch (builtin.os.tag) {
        .windows => std.os.windows.kernel32.GetProcAddress(handle, name),
        else => std.c.dlsym(handle, name),
    };
}
