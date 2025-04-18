const builtin = @import("builtin");
const std = @import("std");

const crash = @import("../crash.zig");
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

const windows = struct {
    pub fn OpenFile(sub_path_w: []const u16, options: std.os.windows.OpenFileOptions) std.os.windows.OpenError!std.os.windows.HANDLE {
        if (std.mem.eql(u16, sub_path_w, &[_]u16{'.'}) and options.filter == .file_only) {
            return error.IsDir;
        }
        if (std.mem.eql(u16, sub_path_w, &[_]u16{ '.', '.' }) and options.filter == .file_only) {
            return error.IsDir;
        }

        var result: std.os.windows.HANDLE = undefined;

        const path_len_bytes = std.math.cast(u16, sub_path_w.len * 2) orelse return error.NameTooLong;
        var nt_name = std.os.windows.UNICODE_STRING{
            .Length = path_len_bytes,
            .MaximumLength = path_len_bytes,
            .Buffer = @constCast(sub_path_w.ptr),
        };
        var attr = std.os.windows.OBJECT_ATTRIBUTES{
            .Length = @sizeOf(std.os.windows.OBJECT_ATTRIBUTES),
            .RootDirectory = if (std.fs.path.isAbsoluteWindowsWTF16(sub_path_w)) null else options.dir,
            .Attributes = if (options.sa) |ptr| blk: { // Note we do not use OBJ_CASE_INSENSITIVE here.
                const inherit: std.os.windows.ULONG = if (ptr.bInheritHandle == std.os.windows.TRUE) std.os.windows.OBJ_INHERIT else 0;
                break :blk inherit;
            } else 0,
            .ObjectName = &nt_name,
            .SecurityDescriptor = if (options.sa) |ptr| ptr.lpSecurityDescriptor else null,
            .SecurityQualityOfService = null,
        };
        var io: std.os.windows.IO_STATUS_BLOCK = undefined;
        const blocking_flag: std.os.windows.ULONG = std.os.windows.FILE_SYNCHRONOUS_IO_NONALERT;
        const file_or_dir_flag: std.os.windows.ULONG = switch (options.filter) {
            .file_only => std.os.windows.FILE_NON_DIRECTORY_FILE,
            .dir_only => std.os.windows.FILE_DIRECTORY_FILE,
            .any => 0,
        };
        // If we're not following symlinks, we need to ensure we don't pass in any synchronization flags such as FILE_SYNCHRONOUS_IO_NONALERT.
        const flags: std.os.windows.ULONG = if (options.follow_symlinks) file_or_dir_flag | blocking_flag else file_or_dir_flag | std.os.windows.FILE_OPEN_REPARSE_POINT;

        while (true) {
            const rc = std.os.windows.ntdll.NtCreateFile(
                &result,
                options.access_mask,
                &attr,
                &io,
                null,
                std.os.windows.FILE_ATTRIBUTE_NORMAL,
                options.share_access,
                options.creation,
                flags,
                null,
                0,
            );
            switch (rc) {
                .SUCCESS => return result,
                .OBJECT_NAME_INVALID => return error.BadPathName,
                .OBJECT_NAME_NOT_FOUND => return error.FileNotFound,
                .OBJECT_PATH_NOT_FOUND => return error.FileNotFound,
                .BAD_NETWORK_PATH => return error.NetworkNotFound, // \\server was not found
                .BAD_NETWORK_NAME => return error.NetworkNotFound, // \\server was found but \\server\share wasn't
                .NO_MEDIA_IN_DEVICE => return error.NoDevice,
                .INVALID_PARAMETER => crash.crashUnreachable(@src()),
                .SHARING_VIOLATION => return error.AccessDenied,
                .ACCESS_DENIED => return error.AccessDenied,
                .PIPE_BUSY => return error.PipeBusy,
                .PIPE_NOT_AVAILABLE => return error.NoDevice,
                .OBJECT_PATH_SYNTAX_BAD => crash.crashUnreachable(@src()),
                .OBJECT_NAME_COLLISION => return error.PathAlreadyExists,
                .FILE_IS_A_DIRECTORY => return error.IsDir,
                .NOT_A_DIRECTORY => return error.NotDir,
                .USER_MAPPED_FILE => return error.AccessDenied,
                .INVALID_HANDLE => crash.crashUnreachable(@src()),
                .DELETE_PENDING => {
                    // This error means that there *was* a file in this location on
                    // the file system, but it was deleted. However, the OS is not
                    // finished with the deletion operation, and so this CreateFile
                    // call has failed. There is not really a sane way to handle
                    // this other than retrying the creation after the OS finishes
                    // the deletion.
                    std.time.sleep(std.time.ns_per_ms);
                    continue;
                },
                .VIRUS_INFECTED, .VIRUS_DELETED => return error.AntivirusInterference,
                else => return std.os.windows.unexpectedStatus(rc),
            }
        }
    }

    pub fn LockFile(
        FileHandle: std.os.windows.HANDLE,
        Event: ?std.os.windows.HANDLE,
        ApcRoutine: ?*std.os.windows.IO_APC_ROUTINE,
        ApcContext: ?*anyopaque,
        IoStatusBlock: *std.os.windows.IO_STATUS_BLOCK,
        ByteOffset: *const std.os.windows.LARGE_INTEGER,
        Length: *const std.os.windows.LARGE_INTEGER,
        Key: ?*std.os.windows.ULONG,
        FailImmediately: std.os.windows.BOOLEAN,
        ExclusiveLock: std.os.windows.BOOLEAN,
    ) !void {
        const rc = std.os.windows.ntdll.NtLockFile(
            FileHandle,
            Event,
            ApcRoutine,
            ApcContext,
            IoStatusBlock,
            ByteOffset,
            Length,
            Key,
            FailImmediately,
            ExclusiveLock,
        );
        switch (rc) {
            .SUCCESS => return,
            .INSUFFICIENT_RESOURCES => return error.SystemResources,
            .LOCK_NOT_GRANTED => return error.WouldBlock,
            .ACCESS_VIOLATION => crash.crashUnreachable(@src()), // bad io_status_block pointer
            else => return std.os.windows.unexpectedStatus(rc),
        }
    }

    pub fn openFileW(self: std.fs.Dir, sub_path_w: []const u16, flags: std.fs.File.OpenFlags) std.fs.File.OpenError!std.fs.File {
        const w = std.os.windows;
        const file: std.fs.File = .{
            .handle = try OpenFile(sub_path_w, .{
                .dir = self.fd,
                .access_mask = w.SYNCHRONIZE |
                    (if (flags.isRead()) @as(u32, w.GENERIC_READ) else 0) |
                    (if (flags.isWrite()) @as(u32, w.GENERIC_WRITE) else 0),
                .creation = w.FILE_OPEN,
            }),
        };
        errdefer file.close();
        var io: w.IO_STATUS_BLOCK = undefined;
        const range_off: w.LARGE_INTEGER = 0;
        const range_len: w.LARGE_INTEGER = 1;
        const exclusive = switch (flags.lock) {
            .none => return file,
            .shared => false,
            .exclusive => true,
        };
        try LockFile(
            file.handle,
            null,
            null,
            null,
            &io,
            &range_off,
            &range_len,
            null,
            @intFromBool(flags.lock_nonblocking),
            @intFromBool(exclusive),
        );
        return file;
    }
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
                logger.debug("opening {}", .{std.unicode.fmtUtf16Le(path)});
                break :blk1 windows.openFileW(cwd, path, .{});
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
            @alignOf(std.c.max_align_t),
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
