const std = @import("std");
const deps = @import("./deps.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.option(std.builtin.Mode, "mode", "") orelse .Debug;
    const disable_llvm = b.option(bool, "disable_llvm", "use the non-llvm zig codegen") orelse false;

    {
        const exe = b.addExecutable(.{
            .name = "bench",
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = mode,
        });
        deps.addAllTo(exe);
        exe.use_llvm = !disable_llvm;
        exe.use_lld = !disable_llvm;
        exe.linkLibC();

        const run_exe = b.addRunArtifact(exe);
        if (b.args) |args| {
            run_exe.addArgs(args);
        }

        const run_step = b.step("run", "Run benchmark");
        run_step.dependOn(&run_exe.step);
    }

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = mode,
    });
    deps.addAllTo(unit_tests);
    unit_tests.use_llvm = !disable_llvm;
    unit_tests.use_lld = !disable_llvm;

    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.setCwd(b.path("."));
    run_unit_tests.has_side_effects = true;

    const test_step = b.step("test", "Run all library tests");
    test_step.dependOn(&run_unit_tests.step);

    //

    const fuzz_exe = addFuzzer(b, target, "xml", &.{});

    const fuzz_run = b.addSystemCommand(&.{"afl-fuzz"});
    fuzz_run.step.dependOn(&fuzz_exe.step);
    fuzz_run.addArgs(&.{ "-i", "fuzz/input" });
    fuzz_run.addArgs(&.{ "-o", "fuzz/output" });
    fuzz_run.addArgs(&.{ "-x", "fuzz/xml.dict" });
    fuzz_run.addArg("--");
    fuzz_run.addFileArg(fuzz_exe.source);

    const fuzz_step = b.step("fuzz", "Run AFL++");
    fuzz_step.dependOn(&fuzz_run.step);
}

fn addFuzzer(b: *std.Build, target: std.Build.ResolvedTarget, comptime name: []const u8, afl_clang_args: []const []const u8) *std.Build.Step.InstallFile {
    const fuzz_lib = b.addStaticLibrary(.{
        .name = "fuzz-" ++ name ++ "-lib",
        .root_source_file = b.path("fuzz/main.zig"),
        .target = target,
        .optimize = .Debug,
    });
    fuzz_lib.want_lto = true;
    fuzz_lib.bundle_compiler_rt = true;
    fuzz_lib.use_llvm = true;
    fuzz_lib.use_lld = true;
    fuzz_lib.root_module.pic = true;

    deps.addAllTo(fuzz_lib);

    const fuzz_executable_name = "fuzz-" ++ name;

    const fuzz_compile = b.addSystemCommand(&.{ "afl-clang-lto", "-v", "-o" });
    const output_path = fuzz_compile.addOutputFileArg(fuzz_executable_name);
    fuzz_compile.addArtifactArg(fuzz_lib);
    fuzz_compile.addArgs(afl_clang_args);

    const fuzz_install = b.addInstallBinFile(output_path, fuzz_executable_name);
    fuzz_install.step.dependOn(&fuzz_compile.step);

    return fuzz_install;
}
