// SPDX-License-Identifier: BSL-1.0

//! The same frame on three devices: a desktop OpenGL 3.3 driver, an OpenGL ES
//! 3.0 one, and an ES 2.0 one that has neither vertex arrays nor instancing.
//! Run it with `zig build example-portable`.
//!
//! A table does not have to be a whole API. It is a struct, so it can be one
//! feature - and then loading it is the feature test, with all of the feature
//! present or none of it:
//!
//!   `Common`         what both APIs spell the same way, which is most of it
//!   `DesktopDepth`   `glClearDepth`, which takes a double
//!   `EmbeddedDepth`  `glClearDepthf`, which takes a float and is the only
//!                    one ES has
//!   `VertexArrays`   two commands that are core in 3.0 and in ES 3.0, an
//!                    extension in ES 2.0, and absent on the oldest devices
//!
//! Which of the middle two to load is a question the version string answers,
//! and the answer is not a guess: `version.api` is `.gl` or `.gles` because
//! the driver said so.

const std = @import("std");
const Io = std.Io;

const opengl = @import("fluxion_gl");
const driver = @import("driver");
const matrix = @import("matrix");
const c = opengl.enums;
const types = opengl.types;

/// Every command in here is in OpenGL 3.3 and in OpenGL ES 2.0, under the
/// same name and with the same signature. It is most of what a frame does.
const Common = struct {
    getString: *const fn (name: types.Enum) callconv(.c) ?[*:0]const types.Char,
    getError: *const fn () callconv(.c) types.Enum,
    viewport: *const fn (x: types.Int, y: types.Int, w: types.Sizei, h: types.Sizei) callconv(.c) void,
    enable: *const fn (capability: types.Enum) callconv(.c) void,
    clearColor: *const fn (r: types.Float, g: types.Float, b: types.Float, a: types.Float) callconv(.c) void,
    clear: *const fn (mask: types.Bitfield) callconv(.c) void,

    genBuffers: *const fn (n: types.Sizei, buffers: [*]types.Uint) callconv(.c) void,
    bindBuffer: *const fn (target: types.Enum, buffer: types.Uint) callconv(.c) void,
    bufferData: *const fn (target: types.Enum, size: types.Sizeiptr, data: ?*const anyopaque, usage: types.Enum) callconv(.c) void,
    vertexAttribPointer: *const fn (
        index: types.Uint,
        size: types.Int,
        kind: types.Enum,
        normalized: types.Boolean,
        stride: types.Sizei,
        pointer: ?*const anyopaque,
    ) callconv(.c) void,
    enableVertexAttribArray: *const fn (index: types.Uint) callconv(.c) void,

    createProgram: *const fn () callconv(.c) types.Uint,
    useProgram: *const fn (program: types.Uint) callconv(.c) void,
    getUniformLocation: *const fn (program: types.Uint, name: [*:0]const types.Char) callconv(.c) types.Int,
    uniformMatrix4fv: *const fn (
        location: types.Int,
        count: types.Sizei,
        transpose: types.Boolean,
        value: [*]const types.Float,
    ) callconv(.c) void,
    uniform4f: *const fn (location: types.Int, v0: types.Float, v1: types.Float, v2: types.Float, v3: types.Float) callconv(.c) void,

    drawArrays: *const fn (mode: types.Enum, first: types.Int, count: types.Sizei) callconv(.c) void,
    readPixels: *const fn (
        x: types.Int,
        y: types.Int,
        width: types.Sizei,
        height: types.Sizei,
        format: types.Enum,
        kind: types.Enum,
        pixels: ?*anyopaque,
    ) callconv(.c) void,
};

/// The desktop clears the depth buffer with a double, because it was written
/// when that seemed like the general choice.
const DesktopDepth = struct {
    clearDepth: *const fn (depth: types.Double) callconv(.c) void,
};

/// ES clears it with a float, because a phone in 2007 had no double to spare.
/// The two commands do the same thing and neither exists on the other API.
const EmbeddedDepth = struct {
    clearDepthf: *const fn (depth: types.Clampf) callconv(.c) void,
};

/// A feature, as a table. Either both commands are there or the feature is
/// not, and `tryLoad` says which without failing the frame.
const VertexArrays = struct {
    genVertexArrays: *const fn (n: types.Sizei, arrays: [*]types.Uint) callconv(.c) void,
    bindVertexArray: *const fn (array: types.Uint) callconv(.c) void,
};

const width = 62;
const height = 24;
const aspect: f32 = @as(f32, width) / (2 * @as(f32, height));

/// One triangle: three positions of three floats, three colours of four.
const triangle = [_]f32{
    -0.9, -0.7, 0, 1.00, 0.78, 0.35, 1,
    0.9,  -0.7, 0, 0.40, 0.52, 0.30, 1,
    0.0,  0.9,  0, 0.12, 0.16, 0.42, 1,
};

const Device = struct {
    label: []const u8,
    version: [:0]const u8,
    /// What this device has never heard of.
    absent: []const []const u8,
};

const devices = [_]Device{
    .{
        .label = "desktop OpenGL 3.3",
        .version = "3.3.0 Fluxion Software Rasteriser 1.0",
        .absent = &.{"glClearDepthf"},
    },
    .{
        .label = "OpenGL ES 3.0",
        .version = "OpenGL ES 3.0 Fluxion",
        .absent = &.{"glClearDepth"},
    },
    .{
        .label = "OpenGL ES 2.0",
        .version = "OpenGL ES 2.0 Fluxion",
        .absent = &.{ "glClearDepth", "glGenVertexArrays", "glBindVertexArray", "glGetStringi", "glDrawArraysInstanced" },
    },
};

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const out = &stdout.interface;

    var pixels: [width * height * 4]u8 = undefined;
    var reference: [width * height * 4]u8 = undefined;
    var identical = true;

    try out.writeAll("--- the same frame, three times ---\n");
    for (devices, 0..) |device, index| {
        try frame(out, device, &pixels);
        if (index == 0) {
            reference = pixels;
        } else if (!std.mem.eql(u8, &reference, &pixels)) {
            identical = false;
        }
    }

    try out.print(
        \\
        \\The three frames are {s}. The last of them, which is the
        \\one with the least under it:
        \\
    , .{if (identical) "byte for byte identical" else "NOT the same"});
    try driver.writeImage(out, &pixels, width, height);
    try out.writeAll(
        \\
        \\What differed was two commands out of eighteen and one feature that
        \\the oldest device has not got, and each of them was decided by
        \\loading a table and looking at the answer - not by an `#ifdef`, and
        \\not by a string comparison on the renderer name.
        \\
    );

    try out.flush();

    // Not a formality: the whole claim of this example is that the picture
    // does not depend on which of the three drew it.
    if (!identical) return error.FramesDiffer;
}

fn frame(out: *Io.Writer, device: Device, pixels: []u8) !void {
    // Standing in for three different machines.
    driver.makeContext(width, height);
    driver.reported_version = device.version;
    driver.absent = device.absent;

    var gl: Common = undefined;
    try opengl.load(&gl, driver.getProcAddress);

    const version = try opengl.Version.parse(std.mem.span(gl.getString(c.version).?));

    // The depth clear, through whichever command this API has. Loading the
    // wrong one would fail here rather than at the call, which is the point
    // of asking the version first.
    var desktop: DesktopDepth = undefined;
    var embedded: EmbeddedDepth = undefined;
    const cleared_with = switch (version.api) {
        .gl => name: {
            try opengl.load(&desktop, driver.getProcAddress);
            desktop.clearDepth(1);
            break :name "glClearDepth";
        },
        .gles => name: {
            try opengl.load(&embedded, driver.getProcAddress);
            embedded.clearDepthf(1);
            break :name "glClearDepthf";
        },
    };

    // Vertex arrays, if this device has them. On the one that has not, the
    // attribute state is global and set again before every draw - which is
    // all a vertex array object is: a recording of exactly these calls.
    var arrays: VertexArrays = undefined;
    const has_arrays = opengl.loader.tryLoad(&arrays, driver.getProcAddress, .{}).ok();
    if (has_arrays) {
        var vao: [1]types.Uint = .{0};
        arrays.genVertexArrays(1, &vao);
        arrays.bindVertexArray(vao[0]);
    }

    var buffer: [1]types.Uint = .{0};
    gl.genBuffers(1, &buffer);
    gl.bindBuffer(c.array_buffer, buffer[0]);
    gl.bufferData(c.array_buffer, @sizeOf(@TypeOf(triangle)), &triangle, c.static_draw);
    gl.vertexAttribPointer(0, 3, c.float, types.gl_false, 7 * @sizeOf(f32), opengl.offset(0));
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(1, 4, c.float, types.gl_false, 7 * @sizeOf(f32), opengl.offset(3 * @sizeOf(f32)));
    gl.enableVertexAttribArray(1);

    const program = gl.createProgram();
    gl.useProgram(program);
    const model = matrix.chain(&.{
        matrix.perspective(std.math.degreesToRadians(50), aspect, 0.1, 100),
        matrix.translate(0, 0, -2.6),
    });
    gl.uniformMatrix4fv(gl.getUniformLocation(program, "mvp"), 1, types.gl_false, &model);
    gl.uniform4f(gl.getUniformLocation(program, "tint"), 1, 1, 1, 1);

    gl.viewport(0, 0, width, height);
    gl.enable(c.depth_test);
    gl.clearColor(0.02, 0.02, 0.06, 1);
    gl.clear(c.color_buffer_bit | c.depth_buffer_bit);
    gl.drawArrays(c.triangles, 0, 3);
    gl.readPixels(0, 0, width, height, c.rgba, c.unsigned_byte, pixels.ptr);

    // A `format` method decides its own width, so pad the string it makes
    // rather than asking the formatter to do it.
    var shown: [24]u8 = undefined;
    try out.print("{s:<21} {s:<16} depth cleared with {s:<15} vertex arrays: {s}\n", .{
        device.label,
        try std.fmt.bufPrint(&shown, "{f}", .{version}),
        cleared_with,
        if (has_arrays) "yes" else "no, so the attributes are set again every draw",
    });

    if (gl.getError() != c.no_error) try out.print("  and {s} reported an error\n", .{device.label});
}
