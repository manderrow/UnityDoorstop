const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const strip = b.option(bool, "strip", "Forces stripping on all optimization modes") orelse switch (optimize) {
        .Debug, .ReleaseSafe => false,
        .ReleaseFast, .ReleaseSmall => true,
    };

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .link_libc = target.result.os.tag != .windows,
    });

    const plthook_dep = b.dependency("plthook", .{
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "UnityDoorstop",
        .root_module = lib_mod,
    });

    switch (target.result.os.tag) {
        .windows => {
            try lib_mod.c_macros.append(b.allocator, "-DUNICODE");

            lib.entry = .{ .symbol_name = "DllEntry" };
        },
        else => {
            lib_mod.addImport("plthook", plthook_dep.module("plthook"));
        },
    }

    lib_mod.addIncludePath(b.path("src"));

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
