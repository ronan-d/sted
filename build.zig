const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const srcprg = b.createModule(.{
        .root_source_file = b.path("srcprg.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    srcprg.addIncludePath(b.path("."));

    const lib = b.addLibrary(.{ .name = "srcprg", .root_module = srcprg });

    const exe = b.addExecutable(.{
        .name = "sted",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    for ([_][]const u8{ "main.c", "stedapp.c" }) |f| {
        const cfile = std.Build.Module.CSourceFile{
            .file = b.path(f),
        };
        exe.root_module.addCSourceFile(cfile);
    }

    exe.root_module.linkLibrary(lib);

    exe.root_module.linkSystemLibrary("gtk4", .{});
    exe.root_module.linkSystemLibrary("gtksourceview-5", .{});

    b.installArtifact(exe);

    const run_step = b.step("run", "run Sted");
    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
}
