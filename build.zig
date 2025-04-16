const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const strip = b.option(bool, "strip", "Forces stripping on all optimization modes") orelse switch (optimize) {
        .Debug, .ReleaseSafe => false,
        .ReleaseFast, .ReleaseSmall => true,
    };

    {
        const lib = try createLib(b, target, optimize, strip);

        b.getInstallStep().dependOn(&b.addInstallArtifact(lib.compile, .{
            .dest_dir = .{ .override = .lib },
        }).step);

        const lib_unit_tests = b.addTest(.{
            .root_module = lib.mod,
        });

        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_lib_unit_tests.step);
    }

    const build_all_step = b.step("build-all", "Builds for all supported targets");

    inline for ([_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu }),
        b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .macos }),
        b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .macos }),
        b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }),
        // b.resolveTargetQuery(.{ .cpu_arch = .x86, .os_tag = .linux, .abi = .gnu }),
        b.resolveTargetQuery(.{ .cpu_arch = .x86, .os_tag = .windows, .abi = .gnu }),
    }) |target_2| {
        const lib_2 = try createLib(b, target_2, optimize, strip);
        build_all_step.dependOn(&b.addInstallArtifact(lib_2.compile, .{
            .dest_dir = .{ .override = .lib },
        }).step);
    }
}

fn createLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
) !struct { mod: *std.Build.Module, compile: *std.Build.Step.Compile } {
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
        .name = b.fmt("UnityDoorstop_{s}", .{@tagName(target.result.cpu.arch)}),
        .root_module = lib_mod,
    });

    if (target.result.os.tag != .windows) {
        lib_mod.addImport("plthook", plthook_dep.module("plthook"));
    }

    lib_mod.addIncludePath(b.path("src"));

    return .{ .mod = lib_mod, .compile = lib };
}
