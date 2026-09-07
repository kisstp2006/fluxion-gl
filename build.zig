// SPDX-License-Identifier: CC0-1.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The importable module. Consumers do:
    //   const opengl = @import("fluxion_gl");
    const mod = b.addModule("fluxion_gl", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // zig build test
    const tests = b.addTest(.{
        .name = "fluxion-gl-tests",
        .root_module = mod,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the library test suite");
    test_step.dependOn(&run_tests.step);

    // The library runs anywhere; a window does not. Everything that opens one
    // is Win32, so on another system those examples are left out of the build
    // rather than failing in it - and a program there gets its context from
    // GLFW or SDL and hands their `getProcAddress` to `load` just the same.
    const windows = target.result.os.tag == .windows;

    // What the examples share. None of it is part of the library: a window
    // with a context in it, the shader boilerplate every frame needs, the
    // matrices a program brings with it, a PNG writer so a frame can be
    // looked at without a display, and a driver that is not there.
    const window_mod = b.createModule(.{
        .root_source_file = b.path("examples/window.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fluxion_gl", .module = mod }},
    });
    const render_mod = b.createModule(.{
        .root_source_file = b.path("examples/render.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fluxion_gl", .module = mod },
            .{ .name = "window", .module = window_mod },
        },
    });
    const matrix_mod = b.createModule(.{
        .root_source_file = b.path("examples/matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    const capture_mod = b.createModule(.{
        .root_source_file = b.path("examples/capture.zig"),
        .target = target,
        .optimize = optimize,
    });
    const driver_mod = b.createModule(.{
        .root_source_file = b.path("examples/driver.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fluxion_gl", .module = mod }},
    });

    // They carry their own tests, and they run with the library's: an entry
    // point nothing has called is a guess, and the way to stop guessing is to
    // draw a triangle into a framebuffer object and look at the pixels.
    const suites = [_]struct {
        name: []const u8,
        module: *std.Build.Module,
        needs_window: bool = false,
    }{
        .{ .name = "fluxion-gl-window-tests", .module = window_mod, .needs_window = true },
        .{ .name = "fluxion-gl-render-tests", .module = render_mod, .needs_window = true },
        .{ .name = "fluxion-gl-matrix-tests", .module = matrix_mod },
        .{ .name = "fluxion-gl-capture-tests", .module = capture_mod },
        .{ .name = "fluxion-gl-driver-tests", .module = driver_mod },
    };
    for (suites) |suite| {
        if (suite.needs_window and !windows) continue;
        const suite_tests = b.addTest(.{ .name = suite.name, .root_module = suite.module });
        test_step.dependOn(&b.addRunArtifact(suite_tests).step);
    }

    // zig build example runs the tour; zig build example-<name> runs one of
    // the others; zig build examples runs all of them, in this order.
    //
    // The two with windows in them write a frame to a file for the aggregate
    // run rather than opening anything. `zig build examples` has to finish on
    // its own, and a window that appears for three seconds and vanishes is a
    // worse way to end than a picture that stays on disk. Run on their own -
    // `zig build example-cube3d` - they open a window and keep it.
    const examples = [_]struct {
        name: []const u8,
        step: []const u8,
        about: []const u8,
        needs_window: bool = false,
        chained_args: []const []const u8 = &.{},
    }{
        .{ .name = "demo", .step = "example", .about = "Build and run the demo tour" },
        .{
            .name = "capabilities",
            .step = "example-capabilities",
            .about = "What this machine's OpenGL is, out of a real context",
            .needs_window = true,
        },
        .{ .name = "portable", .step = "example-portable", .about = "One frame over both APIs" },
        .{
            .name = "scene2d",
            .step = "example-scene2d",
            .about = "2D: instanced quads bouncing in a window",
            .needs_window = true,
            .chained_args = &.{ "--capture", "zig-out/scene2d.png" },
        },
        .{
            .name = "cube3d",
            .step = "example-cube3d",
            .about = "3D: a lit, spinning cube with a depth buffer",
            .needs_window = true,
            .chained_args = &.{ "--capture", "zig-out/cube3d.png" },
        },
    };

    const all_examples = b.step("examples", "Build and run every example in turn");
    var previous: ?*std.Build.Step = null;

    for (examples) |example| {
        if (example.needs_window and !windows) continue;

        const example_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fluxion_gl", .module = mod },
                .{ .name = "window", .module = window_mod },
                .{ .name = "render", .module = render_mod },
                .{ .name = "matrix", .module = matrix_mod },
                .{ .name = "capture", .module = capture_mod },
                .{ .name = "driver", .module = driver_mod },
            },
        });
        const exe = b.addExecutable(.{
            .name = b.fmt("fluxion-gl-{s}", .{example.name}),
            .root_module = example_mod,
        });
        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        run.step.dependOn(b.getInstallStep());
        // Anything after `--` goes through: `zig build example-cube3d -- --frames 60`.
        if (b.args) |args| run.addArgs(args);
        b.step(example.step, example.about).dependOn(&run.step);

        // A second run for the aggregate step, chained one after another so
        // that `zig build examples` reads as a page rather than as five
        // programs shouting at once - and so that asking for one of them does
        // not drag the rest along with it.
        const in_order = b.addRunArtifact(exe);
        in_order.step.dependOn(b.getInstallStep());
        in_order.addArgs(example.chained_args);
        if (previous) |earlier| in_order.step.dependOn(earlier);
        previous = &in_order.step;
        all_examples.dependOn(&in_order.step);

        // The examples with something to check carry tests of their own - the
        // cube renders a frame offscreen and looks at it.
        const example_tests = b.addTest(.{
            .name = b.fmt("fluxion-gl-{s}-tests", .{example.name}),
            .root_module = example_mod,
        });
        test_step.dependOn(&b.addRunArtifact(example_tests).step);
    }

    // zig build docs -> zig-out/docs
    const docs_lib = b.addLibrary(.{
        .name = "fluxion-gl",
        .root_module = mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate API documentation into zig-out/docs");
    docs_step.dependOn(&install_docs.step);
}
