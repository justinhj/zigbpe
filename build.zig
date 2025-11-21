const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ipq_dep = b.dependency("indexed_priority_queue", .{
        .target = target,
        .optimize = optimize,
    });
    const ipq_module = ipq_dep.module("indexed_priority_queue");

    // --- 'basic' executable ---
    const basic_module = b.createModule(.{
        .root_source_file = b.path("code/basic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const basic_exe = b.addExecutable(.{
        .name = "basic",
        .root_module = basic_module,
    });
    basic_exe.root_module.addImport("indexed_priority_queue", ipq_module);
    basic_exe.root_module.addImport("indexed_heap_queue", ipq_module); // Assuming this is intentional
    b.installArtifact(basic_exe);

    const run_basic_cmd = b.addRunArtifact(basic_exe);
    run_basic_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_basic_cmd.addArgs(args);
    }
    // The default `zig build run` will execute 'basic'
    const run_step = b.step("run", "Run the basic app");
    run_step.dependOn(&run_basic_cmd.step);

    // --- 'regex' executable ---
    const regex_module = b.createModule(.{
        .root_source_file = b.path("src/regex.zig"),
        .target = target,
        .optimize = optimize,
    });

    const regex_exe = b.addExecutable(.{
        .name = "regex",
        .root_module = regex_module,
    });
    regex_exe.linkSystemLibrary("pcre2-8");

    regex_exe.root_module.addImport("indexed_priority_queue", ipq_module);
    regex_exe.root_module.addImport("indexed_heap_queue", ipq_module); // Assuming this is intentional
    b.installArtifact(regex_exe);

    const run_regex_cmd = b.addRunArtifact(regex_exe);
    run_regex_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_regex_cmd.addArgs(args);
    }
    const run_regex_step = b.step("run-regex", "Run the regex app");
    run_regex_step.dependOn(&run_regex_cmd.step);
}
