const builtin = @import("builtin");
const std = @import("std");

const alloc = @import("../root.zig").alloc;
const logger = @import("../util/logging.zig").logger;
const runtimes = @import("../runtimes.zig");
const os_char = @import("../util.zig").os_char;

//DEF_CALL\(([^,)]*), ((?:[^,)]+))((?:,(?:\n\s*)? [^,)]*)*)\)
//.{ .name = "${2}", .ret = ${1}, .params = &.{${3}} },

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

const table = @import("func_import.zig").defineFuncImportTable("mono_", &.{
    .{ .name = "thread_current", .ret = *Thread, .params = &.{} },
    .{ .name = "thread_set_main", .ret = void, .params = &.{
        .{ .name = "thread", .type = *Thread },
    } },

    .{ .name = "jit_init_version", .ret = *Domain, .params = &.{
        .{ .name = "root_domain_name", .type = [*:0]const u8 },
        .{ .name = "runtime_version", .type = [*:0]const u8 },
    } },
    .{ .name = "domain_assembly_open", .ret = *Assembly, .params = &.{
        .{ .name = "domain", .type = *anyopaque },
        .{ .name = "name", .type = [*:0]const u8 },
    } },
    .{ .name = "assembly_get_image", .ret = *Image, .params = &.{
        .{ .name = "assembly", .type = *Assembly },
    } },
    .{
        .name = "runtime_invoke",
        .ret = ?*Object,
        .params = &.{
            .{ .name = "method", .type = *Method },
            .{ .name = "obj", .type = ?*Object },
            // TODO: find docs and confirm this is nullable
            .{ .name = "params", .type = ?*?*anyopaque },
            .{ .name = "exc", .type = *?*Object },
        },
    },

    .{ .name = "method_desc_new", .ret = *MethodDesc, .params = &.{
        .{ .name = "name", .type = [*:0]const u8 },
        .{ .name = "include_namespace", .type = i32 },
    } },
    .{ .name = "method_desc_search_in_image", .ret = ?*Method, .params = &.{
        .{ .name = "desc", .type = *MethodDesc },
        .{ .name = "image", .type = *Image },
    } },
    .{ .name = "method_desc_free", .ret = void, .params = &.{
        .{ .name = "desc", .type = *MethodDesc },
    } },
    .{ .name = "method_signature", .ret = *MethodSignature, .params = &.{
        .{ .name = "method", .type = *Method },
    } },
    .{ .name = "signature_get_param_count", .ret = u32, .params = &.{
        .{ .name = "sig", .type = *MethodSignature },
    } },

    .{ .name = "domain_set_config", .ret = void, .params = &.{
        .{ .name = "domain", .type = *Domain },
        .{ .name = "base_dir", .type = [*:0]const u8 },
        .{ .name = "config_file_name", .type = [*:0]const u8 },
    } },
    .{ .name = "array_new", .ret = *Array, .params = &.{
        .{ .name = "domain", .type = *Domain },
        .{ .name = "eclass", .type = *anyopaque },
        .{ .name = "n", .type = u32 },
    } },
    .{ .name = "get_string_class", .ret = *Class, .params = &.{} },

    .{ .name = "assembly_getrootdir", .ret = [*:0]const u8, .params = &.{} },

    .{ .name = "set_dirs", .ret = void, .params = &.{
        .{ .name = "assembly_dir", .type = [*:0]const u8 },
        .{ .name = "config_dir", .type = [*:0]const u8 },
    } },
    .{ .name = "config_parse", .ret = void, .params = &.{
        .{ .name = "filename", .type = ?[*:0]const u8 },
    } },
    .{ .name = "set_assemblies_path", .ret = void, .params = &.{
        .{ .name = "path", .type = [*:0]const u8 },
    } },
    .{ .name = "object_to_string", .ret = *String, .params = &.{
        .{ .name = "obj", .type = *Object },
        .{ .name = "exc", .type = ?*?*Object },
    } },
    .{ .name = "string_to_utf8", .ret = [*:0]const u8, .params = &.{
        .{ .name = "str", .type = *String },
    } },
    .{ .name = "free", .ret = void, .params = &.{
        .{ .name = "ptr", .type = *anyopaque },
    } },
    .{ .name = "image_open_from_data_with_name", .ret = *Image, .params = &.{
        .{ .name = "data", .type = [*]const u8 },
        .{ .name = "data_len", .type = u32 },
        .{ .name = "need_copy", .type = i32 },
        .{ .name = "status", .type = *ImageOpenStatus },
        .{ .name = "refonly", .type = i32 },
        .{ .name = "name", .type = [*:0]const u8 },
    } },
    .{ .name = "assembly_load_from_full", .ret = *Assembly, .params = &.{
        .{ .name = "image", .type = *anyopaque },
        .{ .name = "fname", .type = [*:0]const u8 },
        .{ .name = "status", .type = *ImageOpenStatus },
        .{ .name = "refonly", .type = i32 },
    } },

    .{ .name = "jit_parse_options", .ret = void, .params = &.{
        .{ .name = "argc", .type = i32 },
        .{ .name = "argv", .type = [*]const [*:0]const u8 },
    } },
    .{ .name = "debug_init", .ret = void, .params = &.{
        .{ .name = "domain", .type = DebugFormat },
    } },
    .{ .name = "debug_domain_create", .ret = void, .params = &.{
        .{ .name = "domain", .type = *Domain },
    } },
    .{ .name = "debug_enabled", .ret = i32, .params = &.{} },
}, .c);

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
            .windows => std.fs.cwd().openFileW(path, .{}),
            else => std.fs.cwd().openFileZ(path, .{}),
        } catch |e| {
            logger.err("Failed to open Mono image file: {}", .{e});
            status.* = .file_error;
            return null;
        };
        defer file.close();

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

        break :blk file.readToEndAllocOptions(
            alloc,
            std.math.maxInt(usize),
            @intCast(stat_size),
            @alignOf(std.c.max_align_t),
            0,
        ) catch |e| {
            logger.err("Failed to read Mono image file: {}", .{e});
            status.* = .file_error;
            return null;
        };
    };
    defer alloc.free(buf);

    // need_copy must be forced to true so that Mono copies the data out of our temporary buffer.
    return addrs.image_open_from_data_with_name.?(
        buf.ptr,
        @intCast(buf.len),
        1,
        @ptrCast(status),
        refonly,
        name,
    );
}
