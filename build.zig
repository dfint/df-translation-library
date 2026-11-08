const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("df_translation_library", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "df_translation_library",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const coverage_test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const coverage_tests = b.addTest(.{
        .root_module = coverage_test_mod,
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });

    const kcov = b.findProgramLazy(.{ .names = &.{"kcov"} });
    const run_coverage = std.Build.Step.Run.create(b, "run tests with kcov");
    run_coverage.addFileArg(kcov);
    run_coverage.addArgs(&.{ "--clean", "--include-pattern=/src/", "zig-out/coverage" });
    run_coverage.addArtifactArg2(coverage_tests, .{ .make_absolute = true });
    run_coverage.has_side_effects = true;

    const coverage_step = b.step("test-coverage", "Run unit tests and write a kcov report to zig-out/coverage");
    coverage_step.dependOn(&run_coverage.step);
}
