const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{});

    const use_llvm = b.option(bool, "use-llvm", "Use the llvm backend");

    const main = b.addExecutable(.{
        .name = "sted",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "glib", .module = gobject.module("glib2") },
                .{ .name = "gobject", .module = gobject.module("gobject2") },
                .{ .name = "gio", .module = gobject.module("gio2") },
                .{ .name = "cairo", .module = gobject.module("cairo1") },
                .{ .name = "pango", .module = gobject.module("pango1") },
                .{ .name = "pangocairo", .module = gobject.module("pangocairo1") },
                .{ .name = "gdk", .module = gobject.module("gdk4") },
                .{ .name = "gtk", .module = gobject.module("gtk4") },
                .{ .name = "adw", .module = gobject.module("adw1") },
            },
        }),
        .use_llvm = use_llvm,
    });

    b.installArtifact(main);

    const run_step = b.step("run", "run Sted");
    const run_cmd = b.addRunArtifact(main);

    run_step.dependOn(&run_cmd.step);
}
