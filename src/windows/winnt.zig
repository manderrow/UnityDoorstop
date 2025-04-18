//! # References
//!
//! - https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
//! - https://0xrick.github.io/win-internals/pe1/
//! - https://learn.microsoft.com/en-us/archive/msdn-magazine/2002/february/inside-windows-win32-portable-executable-file-format-in-detail
//! - https://www.sunshine2k.de/reversing/tuts/tut_rvait.htm

const std = @import("std");

pub fn ResolveRvaBase(comptime T: type) type {
    return comptime if (@typeInfo(T).pointer.is_const) *const anyopaque else *anyopaque;
}

/// Resolves an RVA (Relative Virtual Address) relative to the given base.
///
/// See https://en.wikibooks.org/wiki/X86_Disassembly/Windows_Executable_Files#Relative_Virtual_Addressing_(RVA)
/// for more information on Relative Virtual Addresssing.
pub fn resolveRva(comptime T: type, base: *const IMAGE_DOS_HEADER, rva: usize) T {
    return @ptrCast(@alignCast(@as([*]const u8, @ptrCast(base)) + rva));
}

pub fn getDosHeader(module: std.os.windows.HMODULE) *IMAGE_DOS_HEADER {
    return @alignCast(@ptrCast(module));
}

pub const IMAGE_DOS_HEADER = extern struct {
    e_magic: u16,
    e_cblp: u16,
    e_cp: u16,
    e_crlc: u16,
    e_cparhdr: u16,
    e_minalloc: u16,
    e_maxalloc: u16,
    e_ss: u16,
    e_sp: u16,
    e_csum: u16,
    e_ip: u16,
    e_cs: u16,
    e_lfarlc: u16,
    e_ovno: u16,
    e_res: [4]u16,
    e_oemid: u16,
    e_oeminfo: u16,
    e_res2: [10]u16,
    /// This field is signed in Microsoft's headers. However, negative values would be invalid for
    /// an offset from the beginning of the image, and [some](https://www.aldeid.com/wiki/PE-Portable-executable)
    /// sources online suggest the value is interpreted as an unsigned integer.
    e_lfanew: u32,

    pub fn getNtHeaders(self: *const @This()) *const IMAGE_NT_HEADERS {
        return resolveRva(*const IMAGE_NT_HEADERS, self, self.e_lfanew);
    }
};

pub const IMAGE_NT_HEADERS = extern struct {
    signature: u32,
    file_header: std.coff.CoffHeader,
    optional_header: OptionalHeader,

    pub const OptionalHeader = extern union {
        base: std.coff.OptionalHeader,
        pe32: std.coff.OptionalHeaderPE32,
        pe64: std.coff.OptionalHeaderPE64,
    };

    pub fn getDataDirectories(self: *const @This()) []const std.coff.ImageDataDirectory {
        const number_of_rva_and_sizes_ptr: [*]const u32 = @ptrCast(switch (self.optional_header.base.magic) {
            std.coff.IMAGE_NT_OPTIONAL_HDR32_MAGIC => &self.optional_header.pe32.number_of_rva_and_sizes,
            std.coff.IMAGE_NT_OPTIONAL_HDR64_MAGIC => &self.optional_header.pe64.number_of_rva_and_sizes,
            else => unreachable, // We assume we get a valid header from Windows
        });
        return @as([*]const std.coff.ImageDataDirectory, @ptrCast(number_of_rva_and_sizes_ptr + 1))[0..number_of_rva_and_sizes_ptr[0]];
    }

    pub fn getDataDirectoryRaw(self: *const @This(), base: *const IMAGE_DOS_HEADER, id: std.coff.DirectoryEntry) []const u8 {
        const entry = self.getDataDirectories()[@intFromEnum(id)];
        const ptr = resolveRva([*]const u8, base, entry.virtual_address);
        return ptr[0..entry.size];
    }

    pub fn GetDataDirectory(comptime id: std.coff.DirectoryEntry) type {
        return switch (id) {
            .IMPORT => std.coff.ImportDirectoryEntry,
            else => @compileError("Unsupported name " ++ @tagName(id)),
        };
    }

    pub fn getDataDirectory(self: *const @This(), base: *const IMAGE_DOS_HEADER, comptime id: std.coff.DirectoryEntry) []const GetDataDirectory(id) {
        const T = GetDataDirectory(id);
        const raw = self.getDataDirectoryRaw(base, id);
        return @as([*]const T, @ptrCast(@alignCast(raw.ptr)))[0..@divExact(raw.len, @sizeOf(T))];
    }
};
