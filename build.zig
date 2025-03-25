const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    var c_source_files = std.ArrayListUnmanaged([]const u8){};
    try c_source_files.appendSlice(b.allocator, &.{
        "bootstrap.c",
        "config/common.c",
        "util/paths.c",
        "runtimes/globals.c",
    });

    switch (target.result.os.tag) {
        .linux, .macos => |os| {
            try c_source_files.appendSlice(b.allocator, &.{ "nix/config.c", "nix/util.c" });
            if (os == .macos) {
                try c_source_files.appendSlice(b.allocator, &.{
                    "nix/plthook/plthook_osx.c",
                    "nix/plthook/plthook_osx_ext.c",
                });
            } else {
                try c_source_files.appendSlice(b.allocator, &.{
                    "nix/plthook/plthook_elf.c",
                    "nix/plthook/plthook_elf_ext.c",
                });
            }
            try c_source_files.appendSlice(b.allocator, &.{"nix/entrypoint.c"});
        },
        .windows => {
            try c_source_files.appendSlice(b.allocator, &.{
                "windows/config.c",
                "windows/entrypoint.c",
                "windows/util.c",
                "windows/wincrt.c",
            });

            try lib_mod.c_macros.append(b.allocator, "-DUNICODE");
        },
        else => {},
    }

    lib_mod.addCSourceFiles(.{
        .root = b.path("src"),
        .files = c_source_files.items,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "UnityDoorstop",
        .root_module = lib_mod,
    });

    if (target.result.os.tag == .windows) {
        lib.linkSystemLibrary("shell32");
        lib.linkSystemLibrary("kernel32");
        lib.linkSystemLibrary("user32");
    }

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
