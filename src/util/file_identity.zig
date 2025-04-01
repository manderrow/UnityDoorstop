const builtin = @import("builtin");
const std = @import("std");

const root = @import("../root.zig");

const os_char = root.util.os_char;

pub const FileIdentity = switch (builtin.os.tag) {
    .linux => struct {
        dev_major: u32,
        dev_minor: u32,
        ino: u64,
    },
    .macos => struct {
        dev: i32,
        ino: u64,
    },
    .windows => FILE_ID_INFO,
    else => @compileError("Unsupported OS"),
};

pub fn are_same(a: FileIdentity, b: FileIdentity) bool {
    return switch (builtin.os.tag) {
        .linux => a.dev_major == b.dev_major and a.dev_minor == b.dev_minor and a.ino == b.ino,
        .macos => a.dev == b.dev and a.ino == b.ino,
        .windows => a.volume_serial_number == b.volume_serial_number and std.mem.eql(u8, &a.file_id.identifier, &b.file_id.identifier),
        else => @compileError("Unsupported OS"),
    };
}

const Handle = if (builtin.os.tag == .windows) std.os.windows.HANDLE else i32;

/// If path is empty, `dir` itself will be inspected and can be any kind of file handle.
pub fn getFileIdentity(dir: ?Handle, path: [:0]const os_char) !FileIdentity {
    switch (builtin.os.tag) {
        .linux => {
            var buf: std.os.linux.Statx = undefined;
            if (std.os.linux.statx(
                dir orelse std.os.linux.AT.FDCWD,
                path,
                if (path.len == 0) std.os.linux.AT.EMPTY_PATH else 0,
                std.os.linux.STATX_INO,
                &buf,
            ) != 0) {
                return switch (std.posix.errno(std.c._errno().*)) {
                    .ACCES => error.AccessDenied,
                    .BADF => unreachable,
                    .FAULT => unreachable,
                    .INVAL => unreachable,
                    .LOOP => error.SymLinkLoop,
                    .NAMETOOLONG => error.NameTooLong,
                    .NOENT => error.FileNotFound,
                    .NOMEM => error.SystemResources,
                    .NOTDIR => error.NotDir,
                    else => |err| std.posix.unexpectedErrno(err),
                };
            }
            return .{ .dev_major = buf.dev_major, .dev_minor = buf.dev_minor, .ino = buf.ino };
        },
        .macos => {
            if (dir != null and path.len != 0) {
                return error.Unsupported;
            }
            var buf: std.c.Stat = undefined;
            if ((if (dir) |fd| std.c.fstat(fd, &buf) else std.c.stat(path, &buf)) != 0) {
                return switch (std.posix.errno(std.c._errno().*)) {
                    .ACCES => error.AccessDenied,
                    .IO => error.FileSystem,
                    .BADF => unreachable,
                    .FAULT => unreachable,
                    .LOOP => error.SymLinkLoop,
                    .NAMETOOLONG => error.NameTooLong,
                    .NOENT => error.FileNotFound,
                    .NOTDIR => error.NotDir,
                    .OVERFLOW => error.FileTooBig,
                    else => |err| std.posix.unexpectedErrno(err),
                };
            }
            return .{ .dev = buf.dev, .ino = buf.ino };
        },
        .windows => {
            if (dir != null and path.len != 0) {
                return error.Unsupported;
            }

            const handle = try std.os.windows.OpenFile(path, .{
                // Not sure if this is sufficient. Might need GENERIC_READ.
                .access_mask = 0,
                .creation = std.os.windows.OPEN_EXISTING,
            });
            defer std.os.windows.CloseHandle(handle);

            return getFileInfo(handle, .FileIdInfo);
        },
        else => @compileError("Unsupported OS"),
    }
}

extern "kernel32" fn GetFileInformationByHandleEx(
    in_hFile: std.os.windows.HANDLE,
    in_FileInformationClass: std.os.windows.FILE_INFO_BY_HANDLE_CLASS,
    out_lpFileInformation: *anyopaque,
    in_dwBufferSize: std.os.windows.DWORD,
) callconv(.winapi) std.os.windows.BOOL;

const FILE_ID_INFO = extern struct {
    volume_serial_number: u64,
    file_id: extern struct {
        identifier: [16]u8,
    },
};

fn GetFileInfo(comptime class: std.os.windows.FILE_INFO_BY_HANDLE_CLASS) type {
    return switch (class) {
        .FileBasicInfo => std.os.windows.FILE_BASIC_INFORMATION,
        .FileStandardInfo => std.os.windows.FILE_STANDARD_INFORMATION,
        .FileNameInfo => std.os.windows.FILE_NAME_INFO,
        .FileRenameInfo => std.os.windows.FILE_RENAME_INFORMATION_EX,
        .FileDispositionInfo => std.os.windows.FILE_DISPOSITION_INFORMATION_EX,
        .FileEndOfFileInfo => std.os.windows.FILE_END_OF_FILE_INFORMATION,
        .FileAttributeTagInfo => std.os.windows.FILE_ATTRIBUTE_TAG_INFO,
        .FileAlignmentInfo => std.os.windows.FILE_ALIGNMENT_INFORMATION,
        .FileIdInfo => FILE_ID_INFO,
        else => @compileError("Type of class " ++ @tagName(class) ++ " is unknown"),
    };
}

fn getFileInfo(file: std.os.windows.HANDLE, comptime class: std.os.windows.FILE_INFO_BY_HANDLE_CLASS) error{Unexpected}!GetFileInfo(class) {
    return switch (class) {
        inline else => |c| {
            var buf: GetFileInfo(c) = undefined;
            if (GetFileInformationByHandleEx(file, class, &buf, @sizeOf(@TypeOf(buf))) == 0) {
                return std.os.windows.unexpectedError(std.os.windows.GetLastError());
            }
            return buf;
        },
    };
}
