const builtin = @import("builtin");
const std = @import("std");

const crash = @import("../crash.zig");
const alloc = @import("../root.zig").alloc;
const logger = @import("../util/logging.zig").logger;
const runtimes = @import("../runtimes.zig");
const os_char = @import("../util.zig").os_char;

pub const Array = opaque {};
pub const Assembly = opaque {};
pub const Class = opaque {};
pub const Domain = opaque {};
pub const Image = opaque {};
pub const MethodDesc = opaque {};
pub const Method = opaque {};
pub const MethodSignature = opaque {};
pub const Object = opaque {};
pub const String = opaque {};
pub const Thread = opaque {};

const cc: std.builtin.CallingConvention = .c;

const table = @import("func_import.zig").defineFuncImportTable("mono_", struct {
    thread_current: fn () callconv(cc) *Thread,
    thread_set_main: fn (thread: *Thread) callconv(cc) void,

    jit_init_version: fn (
        root_domain_name: [*:0]const u8,
        runtime_version: [*:0]const u8,
    ) callconv(cc) *Domain,
    domain_assembly_open: fn (
        domain: *anyopaque,
        name: [*:0]const u8,
    ) callconv(cc) *Assembly,
    assembly_get_image: fn (assembly: *Assembly) callconv(cc) *Image,
    runtime_invoke: fn (
        method: *Method,
        obj: ?*Object,
        // TODO: find docs and confirm this is nullable
        params: ?*?*anyopaque,
        exc: *?*Object,
    ) callconv(cc) ?*Object,

    method_desc_new: fn (
        name: [*:0]const u8,
        include_namespace: i32,
    ) callconv(cc) *MethodDesc,
    method_desc_search_in_image: fn (
        desc: *MethodDesc,
        image: *Image,
    ) callconv(cc) ?*Method,
    method_desc_free: fn (desc: *MethodDesc) callconv(cc) void,
    method_signature: fn (method: *Method) callconv(cc) *MethodSignature,
    signature_get_param_count: fn (sig: *MethodSignature) callconv(cc) u32,

    domain_set_config: fn (
        domain: *Domain,
        base_dir: [*:0]const u8,
        config_file_name: [*:0]const u8,
    ) callconv(cc) void,
    array_new: fn (
        domain: *Domain,
        eclass: *anyopaque,
        n: u32,
    ) callconv(cc) *Array,
    get_string_class: fn () callconv(cc) *Class,

    assembly_getrootdir: fn () callconv(cc) [*:0]const u8,

    set_dirs: fn (
        assembly_dir: [*:0]const u8,
        config_dir: [*:0]const u8,
    ) callconv(cc) void,
    config_parse: fn (
        filename: ?[*:0]const u8,
    ) callconv(cc) void,
    set_assemblies_path: fn (
        path: [*:0]const u8,
    ) callconv(cc) void,
    object_to_string: fn (
        obj: *Object,
        exc: ?*?*Object,
    ) callconv(cc) *String,
    string_to_utf8: fn (
        str: *String,
    ) callconv(cc) [*:0]const u8,
    free: fn (
        ptr: *anyopaque,
    ) callconv(cc) void,
    image_open_from_data_with_name: fn (
        data: [*]const u8,
        data_len: u32,
        need_copy: i32,
        status: *ImageOpenStatus,
        refonly: i32,
        name: [*:0]const u8,
    ) callconv(cc) *Image,
    assembly_load_from_full: fn (
        image: *anyopaque,
        fname: [*:0]const u8,
        status: *ImageOpenStatus,
        refonly: i32,
    ) callconv(cc) *Assembly,

    jit_parse_options: fn (
        argc: i32,
        argv: [*]const [*:0]const u8,
    ) callconv(cc) void,
    debug_init: fn (
        domain: DebugFormat,
    ) callconv(cc) void,
    debug_domain_create: fn (
        domain: *Domain,
    ) callconv(cc) void,
    debug_enabled: fn () callconv(cc) i32,
});

pub const addrs = &table.addrs;
pub const load = table.load;

pub const ImageOpenStatus = enum(c_int) {
    ok = 0,
    error_errno = 1,
    missing_assemblyref = 2,
    image_invalid = 3,
    _,
};

pub const ImageOpenFileStatus = enum(c_int) {
    ok = @intFromEnum(ImageOpenStatus.ok),
    error_errno = @intFromEnum(ImageOpenStatus.error_errno),
    missing_assemblyref = @intFromEnum(ImageOpenStatus.missing_assemblyref),
    image_invalid = @intFromEnum(ImageOpenStatus.image_invalid),
    file_not_found = -1,
    file_error = -2,
    _,
};

pub const DebugFormat = enum(c_int) {
    none,
    mono,
    /// Deprecated, the mdb debugger is not longer supported.
    debugger,
};

/// If the file exists, it will be loaded, and `true` will be returned. If loading fails,
/// the function panics. If the file does not exist, `false` will be returned.
pub fn image_open_from_file_with_name(
    path: [:0]const os_char,
    status: *ImageOpenFileStatus,
    refonly: i32,
    name: [:0]const u8,
) ?*Image {
    const buf = blk: {
        var file = switch (builtin.os.tag) {
            .windows => blk1: {
                const cwd = std.fs.cwd();
                logger.debug("got cwd", .{});
                logger.debug("opening {f}", .{std.unicode.fmtUtf16Le(path)});
                const prefixed_path = std.os.windows.wToPrefixedFileW(cwd.fd, path) catch |e| break :blk1 e;
                break :blk1 cwd.openFileW(prefixed_path.span(), .{});
            },
            else => std.fs.cwd().openFileZ(path, .{}),
        } catch |e| {
            logger.err("Failed to open Mono image file: {}", .{e});
            status.* = .file_error;
            return null;
        };
        defer file.close();
        logger.debug("opened file", .{});

        // If the file size doesn't fit a usize it'll be certainly greater than
        // `max_bytes`
        const stat_size = std.math.cast(u32, file.getEndPos() catch |e| {
            logger.err("Failed to read Mono image file: {}", .{e});
            status.* = .file_error;
            return null;
        }) orelse {
            logger.err("Failed to read Mono image file: File too big", .{});
            status.* = .file_error;
            return null;
        };
        logger.debug("got end pos", .{});

        break :blk file.readToEndAllocOptions(
            alloc,
            std.math.maxInt(usize),
            @intCast(stat_size),
            .of(std.c.max_align_t),
            0,
        ) catch |e| {
            logger.err("Failed to read Mono image file: {}", .{e});
            status.* = .file_error;
            return null;
        };
    };
    defer alloc.free(buf);
    logger.debug("read to end", .{});

    // need_copy must be forced to true so that Mono copies the data out of our temporary buffer.
    return (addrs.image_open_from_data_with_name orelse {
        @panic("image_open_from_data_with_name is null");
    })(
        buf.ptr,
        @intCast(buf.len),
        1,
        @ptrCast(status),
        refonly,
        name,
    );
}
