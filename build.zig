const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("code/basic.zig"),
        .target = target,
        .optimize = optimize,
    });

    const basic_exe = b.addExecutable(.{
        .name = "basic",
        .root_module = module,
    });

    const ipq_dep = b.dependency("indexed_priority_queue", .{
        .target = target,
        .optimize = optimize,
    });
    const ipq_module = ipq_dep.module("indexed_priority_queue");
    basic_exe.root_module.addImport("indexed_priority_queue", ipq_module);

    const run_cmd = b.addRunArtifact(basic_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    basic_exe.root_module.addImport("indexed_heap_queue", ipq_module);

    b.installArtifact(basic_exe);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
