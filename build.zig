const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zigbpe",
        .root_source_file = b.path("code/zigbpe.zig"),
        .target = target,
        .optimize = optimize,
    });

    const skipping_list_module = b.addModule("skipping_list", .{
        .root_source_file = b.path("code/skipping_list.zig"),
    });
    exe.root_module.addImport("skipping_list", skipping_list_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
