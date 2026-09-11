const std = @import("std");

// ffi file build helper
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "web_guard",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/guard.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    lib.root_module.link_libc = true;

    b.installArtifact(lib);
}