const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = true,
        .link_libc = true,
    });

    const plthook_dep = b.dependency("plthook", .{
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag != .windows) {
        lib_mod.addImport("plthook", plthook_dep.module("plthook"));
    }

    var c_source_files = std.ArrayListUnmanaged([]const u8){};
    try c_source_files.append(b.allocator, "bootstrap.c");

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "UnityDoorstop",
        .root_module = lib_mod,
    });

    switch (target.result.os.tag) {
        .linux, .macos => {
            try c_source_files.append(b.allocator, "nix/entrypoint.c");
        },
        .windows => {
            try c_source_files.appendSlice(b.allocator, &.{
                "windows/entrypoint.c",
                "windows/wincrt.c",
                "util/logging/windows.c",
            });

            try lib_mod.c_macros.append(b.allocator, "-DUNICODE");

            lib.entry = .{ .symbol_name = "DllEntry" };
        },
        else => {},
    }

    lib_mod.addCSourceFiles(.{
        .root = b.path("src"),
        .files = c_source_files.items,
        .flags = &.{ "-Wall", "-Werror" },
    });

    lib_mod.addIncludePath(b.path("src"));

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
