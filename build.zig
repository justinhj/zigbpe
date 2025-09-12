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

    // const ipq_dep = b.dependency("justinhj/indexed_priority_queue", .{});
    // const ipq_module = ipq_dep.module("indexed_priority_queue");
    // exe.root_module.addImport("indexed_priority_queue", ipq_module);

    // b.installArtifact(exe);
    const ipq_dep = b.dependency("indexed_priority_queue", .{
        .target = target,
        .optimize = optimize,
    });
    const ipq_module = ipq_dep.module("indexed_priority_queue");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    exe.root_module.addImport("indexed_heap_queue", ipq_module);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
