// SPDX-License-Identifier: BSL-1.0

//! Three dimensions: a lit cube turning in a window.
//!
//! Run it with `zig build example-cube3d`. Passing `-- --frames 240` has it
//! close itself after a fixed number of frames. Escape quits.
//!
//! `-- --capture cube3d.png` skips the window entirely: it draws one frame
//! into a framebuffer object and writes it out, which is how this can be
//! looked at on a machine with no display. `--at SECONDS` picks the moment.
//!
//! Everything the 2D example left out is here, and it is not much: a depth
//! buffer, so a face at the back cannot paint over one at the front; backface
//! culling, so the half of the cube that points away is never rasterised at
//! all; a matrix that turns a position in the cube's own space into one on
//! the screen; and a normal per face, so the light has something to fall on.
//!
//! **Which way round a matrix goes.** GLSL reads a `mat4` column by column,
//! and `uniformMatrix4fv` uploads exactly what it is handed unless
//! `transpose` says otherwise - so a matrix written out column by column in
//! Zig arrives the right way up. `fluxion-math` stores them that way,
//! and passing `gl_true` for `transpose` to "fix" a picture that is wrong for
//! some other reason is how an afternoon goes missing.
//!
//! **Which way round a triangle goes.** With `cull_face` on, OpenGL throws
//! away the triangles that face away from the camera, and which way that is
//! depends on the order the three corners are listed in. Get it backwards and
//! the cube is inside out: every face that should be visible is discarded and
//! the far ones are drawn instead. The test at the bottom of this file renders
//! one frame into a framebuffer object and looks at the pixels, which is the
//! only way to be sure.

const std = @import("std");
const Io = std.Io;

const opengl = @import("fluxion_gl");
const capture = @import("capture");
const math = @import("fluxion_math");
const render = @import("render");
const Window = @import("window").Window;

const c = opengl.enums;
const types = opengl.types;

const background = [4]f32{ 0.06, 0.07, 0.10, 1 };

// -------------------------------------------------------------------------
// The cube
// -------------------------------------------------------------------------

/// Position, the direction the face points, and its colour. Nine floats a
/// vertex, in one buffer, which is what the strides and offsets below walk.
const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    colour: [3]f32,
};

/// One face: four corners wound counter-clockwise seen from outside, which is
/// what `frontFace(ccw)` and `cullFace(back)` between them rely on.
const Face = struct {
    corners: [4][3]f32,
    normal: [3]f32,
    colour: [3]f32,
};

const faces = [_]Face{
    .{
        .corners = .{ .{ -1, -1, 1 }, .{ 1, -1, 1 }, .{ 1, 1, 1 }, .{ -1, 1, 1 } },
        .normal = .{ 0, 0, 1 },
        .colour = .{ 0.90, 0.45, 0.25 },
    },
    .{
        .corners = .{ .{ 1, -1, -1 }, .{ -1, -1, -1 }, .{ -1, 1, -1 }, .{ 1, 1, -1 } },
        .normal = .{ 0, 0, -1 },
        .colour = .{ 0.30, 0.55, 0.85 },
    },
    .{
        .corners = .{ .{ 1, -1, 1 }, .{ 1, -1, -1 }, .{ 1, 1, -1 }, .{ 1, 1, 1 } },
        .normal = .{ 1, 0, 0 },
        .colour = .{ 0.55, 0.75, 0.30 },
    },
    .{
        .corners = .{ .{ -1, -1, -1 }, .{ -1, -1, 1 }, .{ -1, 1, 1 }, .{ -1, 1, -1 } },
        .normal = .{ -1, 0, 0 },
        .colour = .{ 0.75, 0.35, 0.60 },
    },
    .{
        .corners = .{ .{ -1, 1, 1 }, .{ 1, 1, 1 }, .{ 1, 1, -1 }, .{ -1, 1, -1 } },
        .normal = .{ 0, 1, 0 },
        .colour = .{ 0.90, 0.85, 0.55 },
    },
    .{
        .corners = .{ .{ -1, -1, -1 }, .{ 1, -1, -1 }, .{ 1, -1, 1 }, .{ -1, -1, 1 } },
        .normal = .{ 0, -1, 0 },
        .colour = .{ 0.35, 0.40, 0.50 },
    },
};

/// Twenty-four vertices rather than eight: a corner of a cube is shared by
/// three faces, and its normal and colour are not.
const cube_vertices: [faces.len * 4]Vertex = blk: {
    var out: [faces.len * 4]Vertex = undefined;
    var at = 0;
    for (faces) |face| {
        for (face.corners) |corner| {
            out[at] = .{ .position = corner, .normal = face.normal, .colour = face.colour };
            at += 1;
        }
    }
    break :blk out;
};

/// Two triangles a face, sharing the diagonal: 0,1,2 and 2,3,0.
const cube_indices: [faces.len * 6]u16 = blk: {
    var out: [faces.len * 6]u16 = undefined;
    for (0..faces.len) |face| {
        const corner = face * 4;
        out[face * 6 + 0] = corner + 0;
        out[face * 6 + 1] = corner + 1;
        out[face * 6 + 2] = corner + 2;
        out[face * 6 + 3] = corner + 2;
        out[face * 6 + 4] = corner + 3;
        out[face * 6 + 5] = corner + 0;
    }
    break :blk out;
};

const sources: render.Program.Sources = .{
    .vertex =
    \\#version 330 core
    \\
    \\// Explicit locations, which is what OpenGL 3.3 added and what lets one
    \\// vertex array feed more than one program without asking either of them
    \\// where its attributes ended up.
    \\layout(location = 0) in vec3 position;
    \\layout(location = 1) in vec3 normal;
    \\layout(location = 2) in vec3 colour;
    \\
    \\uniform mat4 mvp;
    \\uniform mat4 model;
    \\
    \\out vec3 shade;
    \\
    \\void main() {
    \\    // The cube is only ever rotated, so the upper 3x3 of the model
    \\    // matrix carries the normals correctly. Add a non-uniform scale and
    \\    // this line needs the inverse transpose instead.
    \\    vec3 world_normal = normalize(mat3(model) * normal);
    \\    vec3 to_light = normalize(vec3(0.35, 0.75, 0.55));
    \\
    \\    float lambert = max(dot(world_normal, to_light), 0.0);
    \\    shade = colour * (0.25 + 0.75 * lambert);
    \\
    \\    gl_Position = mvp * vec4(position, 1.0);
    \\}
    ,
    .fragment =
    \\#version 330 core
    \\
    \\in vec3 shade;
    \\out vec4 result;
    \\
    \\void main() {
    \\    result = vec4(shade, 1.0);
    \\}
    ,
};

const Cube = struct {
    program: render.Program,
    vao: types.Uint = 0,
    vertices: types.Uint = 0,
    indices: types.Uint = 0,
    mvp: types.Int = -1,
    model: types.Int = -1,

    fn init(api: *const opengl.Gl, log: *Io.Writer) !Cube {
        var self: Cube = .{ .program = try render.Program.compile(api, sources, log) };

        api.genVertexArrays(1, @ptrCast(&self.vao));
        api.bindVertexArray(self.vao);

        api.genBuffers(1, @ptrCast(&self.vertices));
        api.bindBuffer(c.array_buffer, self.vertices);
        api.bufferData(c.array_buffer, @sizeOf(@TypeOf(cube_vertices)), &cube_vertices, c.static_draw);

        // One buffer, three attributes, and the offsets say where each one
        // starts inside a vertex.
        api.vertexAttribPointer(0, 3, c.float, types.gl_false, @sizeOf(Vertex), opengl.offset(@offsetOf(Vertex, "position")));
        api.enableVertexAttribArray(0);
        api.vertexAttribPointer(1, 3, c.float, types.gl_false, @sizeOf(Vertex), opengl.offset(@offsetOf(Vertex, "normal")));
        api.enableVertexAttribArray(1);
        api.vertexAttribPointer(2, 3, c.float, types.gl_false, @sizeOf(Vertex), opengl.offset(@offsetOf(Vertex, "colour")));
        api.enableVertexAttribArray(2);

        // The element buffer binding is part of the vertex array object, so
        // binding the array later brings the indices back with it.
        api.genBuffers(1, @ptrCast(&self.indices));
        api.bindBuffer(c.element_array_buffer, self.indices);
        api.bufferData(c.element_array_buffer, @sizeOf(@TypeOf(cube_indices)), &cube_indices, c.static_draw);

        self.mvp = self.program.location(api, "mvp");
        self.model = self.program.location(api, "model");
        return self;
    }

    fn draw(self: Cube, api: *const opengl.Gl, aspect: f32, seconds: f32) void {
        api.enable(c.depth_test);
        api.enable(c.cull_face);
        api.cullFace(c.back);
        api.frontFace(c.ccw);

        // The cube turns about its own vertical axis, and the camera looks
        // down at it from a little above. Those are two different matrices on
        // purpose: tilting the cube instead would work for a moment and then
        // roll it, because a tilt that is applied before a spin is carried
        // round by the spin - the cube ends up face-on with its edges turning
        // in the screen, which looks like a bug in the projection and is not.
        const model = math.Mat4.fromAxisAngle(.unit_y, seconds * 0.6);
        const view = math.Mat4.fromTranslation(.{ .z = -4.6 }).mul(.fromAxisAngle(.unit_x, 0.5));
        const projection = math.perspective(.{
            .fov_y = math.radians(45),
            .aspect = aspect,
            .near = 0.1,
            .far = 100,
            // Depth from -1 to 1, origin at the bottom left: the one place
            // OpenGL, Vulkan and Direct3D disagree, and the one thing to
            // change here for either of the other two.
            .clip = .gl,
        });
        const mvp = projection.mul(view).mul(model);

        self.program.use(api);
        api.uniformMatrix4fv(self.mvp, 1, types.gl_false, &mvp.array());
        api.uniformMatrix4fv(self.model, 1, types.gl_false, &model.array());

        api.bindVertexArray(self.vao);
        api.drawElements(c.triangles, cube_indices.len, c.unsigned_short, opengl.offset(0));
    }

    fn deinit(self: *Cube, api: *const opengl.Gl) void {
        api.deleteBuffers(1, @ptrCast(&self.indices));
        api.deleteBuffers(1, @ptrCast(&self.vertices));
        api.deleteVertexArrays(1, @ptrCast(&self.vao));
        self.program.deinit(api);
        self.* = undefined;
    }
};

// -------------------------------------------------------------------------
// The program
// -------------------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const out = &stdout.interface;

    const options = try Options.fromArguments(init, init.arena.allocator());

    // A window, shown or not: on Windows there is no context without one.
    var window = Window.open(.{
        .title = "Fluxion GL - 3D",
        .width = options.width,
        .height = options.height,
        .visible = options.capture == null,
    }) catch |err| {
        try out.print("no OpenGL 3.3 context on this machine: {t}\n", .{err});
        try out.flush();
        return err;
    };
    defer window.close();

    var api: opengl.Gl = undefined;
    const status = api.tryLoad(window.resolver());
    if (!status.ok()) {
        try out.print("{f}\n", .{status});
        try out.flush();
        return error.CommandMissing;
    }

    try out.print("{f} on {s}\n", .{ try api.version(), api.string(c.renderer) orelse "?" });
    try out.print("{f}, {d} vertices, {d} indices\n", .{
        try api.glslVersion(),
        cube_vertices.len,
        cube_indices.len,
    });
    try out.flush();

    var cube = Cube.init(&api, out) catch |err| {
        try out.flush();
        return err;
    };
    defer cube.deinit(&api);

    // --- one frame to a file, and no window on screen ----------------------
    if (options.capture) |path| {
        var screen = try render.Offscreen.init(&api, options.width, options.height, true);
        defer screen.deinit(&api);

        screen.begin(&api, background);
        cube.draw(&api, aspectOf(options.width, options.height), options.at);

        const pixels = try screen.read(&api, init.gpa);
        defer init.gpa.free(pixels);

        try capture.writePng(
            init.gpa,
            init.io,
            path,
            options.width,
            options.height,
            pixels,
            @as(usize, options.width) * 4,
        );
        try out.print("wrote {s}, {d} by {d}, at {d:.2} seconds\n", .{
            path,
            options.width,
            options.height,
            options.at,
        });
        return out.flush();
    }

    try out.writeAll("a window - escape or close it to quit\n");
    try out.flush();

    const started = Io.Timestamp.now(init.io, .awake).nanoseconds;
    var frames: u64 = 0;

    while (window.pump()) {
        if (window.minimised()) continue;

        const now = Io.Timestamp.now(init.io, .awake).nanoseconds;
        const seconds: f32 = @floatCast(@as(f64, @floatFromInt(now - started)) / std.time.ns_per_s);

        api.viewport(0, 0, @intCast(window.width), @intCast(window.height));
        api.clearColor(background[0], background[1], background[2], background[3]);
        api.clearDepth(1);
        api.clear(c.color_buffer_bit | c.depth_buffer_bit);

        cube.draw(&api, aspectOf(window.width, window.height), seconds);
        window.present();

        frames += 1;
        if (options.frames) |limit| {
            if (frames >= limit) break;
        }
    }

    try out.print("{d} frames\n", .{frames});
    try out.flush();
}

fn aspectOf(width: u32, height: u32) f32 {
    if (height == 0) return 1;
    return @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
}

/// What the command line can say. All of it is about running the example
/// without a person watching: stopping after a fixed number of frames, or not
/// opening a window at all and writing one frame to a file.
const Options = struct {
    /// `--frames N`: stop after N frames.
    frames: ?u64 = null,
    /// `--capture PATH`: no window on screen; render one frame and write it
    /// as a PNG.
    capture: ?[]const u8 = null,
    /// `--at SECONDS`: how far into the turn to capture. The default is a
    /// moment with three faces showing, which is what a cube should look
    /// like.
    at: f32 = 1.2,
    width: u32 = 960,
    height: u32 = 540,

    fn fromArguments(init: std.process.Init, arena: std.mem.Allocator) !Options {
        var options: Options = .{};
        const arguments = try init.minimal.args.toSlice(arena);
        var i: usize = 1;
        while (i < arguments.len) : (i += 1) {
            const argument = arguments[i];
            const value = if (i + 1 < arguments.len) arguments[i + 1] else null;
            if (std.mem.eql(u8, argument, "--frames")) {
                options.frames = try std.fmt.parseInt(u64, value orelse return error.MissingValue, 10);
                i += 1;
            } else if (std.mem.eql(u8, argument, "--capture")) {
                options.capture = value orelse return error.MissingValue;
                i += 1;
            } else if (std.mem.eql(u8, argument, "--at")) {
                options.at = try std.fmt.parseFloat(f32, value orelse return error.MissingValue);
                i += 1;
            } else {
                return error.UnknownArgument;
            }
        }
        return options;
    }
};

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

const testing = std.testing;

test "the cube is closed and its normals point outwards" {
    try testing.expectEqual(@as(usize, 24), cube_vertices.len);
    try testing.expectEqual(@as(usize, 36), cube_indices.len);

    for (cube_vertices) |vertex| {
        // Every corner is a corner of the unit cube.
        for (vertex.position) |component| {
            try testing.expectApproxEqAbs(@as(f32, 1), @abs(component), 0.0001);
        }
        // And its normal points away from the middle rather than towards it,
        // which is what makes the lighting come out the right way round.
        var dot: f32 = 0;
        for (vertex.position, vertex.normal) |p, n| dot += p * n;
        try testing.expect(dot > 0);
    }
}

test "the vertices are laid out as the strides say" {
    try testing.expectEqual(@as(usize, 36), @sizeOf(Vertex));
    try testing.expectEqual(@as(usize, 0), @offsetOf(Vertex, "position"));
    try testing.expectEqual(@as(usize, 12), @offsetOf(Vertex, "normal"));
    try testing.expectEqual(@as(usize, 24), @offsetOf(Vertex, "colour"));
}

test "a frame of it, rendered and looked at" {
    // The only way to know that the winding, the projection and the depth
    // test all agree is to draw the thing and look. This renders one frame
    // into a framebuffer object with nothing on screen behind it, and checks
    // that the cube is where it should be and the background is where it
    // should be.
    var window = try @import("window").openForTest(128, 128);
    defer window.close();

    var api: opengl.Gl = undefined;
    try api.load(window.resolver());

    var log_buffer: [4096]u8 = undefined;
    var log: Io.Writer = .fixed(&log_buffer);
    var cube = Cube.init(&api, &log) catch |err| {
        std.debug.print("{s}\n", .{log.buffered()});
        return err;
    };
    defer cube.deinit(&api);

    var screen = try render.Offscreen.init(&api, 128, 128, true);
    defer screen.deinit(&api);

    screen.begin(&api, background);
    cube.draw(&api, 1.0, 1.2);

    const pixels = try screen.read(&api, testing.allocator);
    defer testing.allocator.free(pixels);
    try testing.expectEqual(null, api.checkError());

    // The middle of the image is the cube, and it is not the background.
    try testing.expect(!isBackground(render.pixelAt(pixels, 128, 64, 64)));

    // The corners are outside it, and they are.
    for ([_][2]u32{ .{ 2, 2 }, .{ 125, 2 }, .{ 2, 125 }, .{ 125, 125 } }) |point| {
        try testing.expect(isBackground(render.pixelAt(pixels, 128, point[0], point[1])));
    }

    // Three faces of a cube are visible at once from a corner, each lit to a
    // different brightness, so the picture holds at least three distinct
    // colours besides the background. Fewer would mean faces are being
    // discarded that should not be - the winding backwards, or the depth test
    // the wrong way round.
    var seen: [16][4]u8 = undefined;
    var count: usize = 0;
    var y: u32 = 20;
    while (y < 110) : (y += 3) {
        var x: u32 = 20;
        while (x < 110) : (x += 3) {
            const pixel = render.pixelAt(pixels, 128, x, y);
            if (isBackground(pixel)) continue;
            for (seen[0..count]) |already| {
                if (std.mem.eql(u8, &already, &pixel)) break;
            } else {
                if (count == seen.len) break;
                seen[count] = pixel;
                count += 1;
            }
        }
    }
    try testing.expect(count >= 3);
}

fn isBackground(pixel: [4]u8) bool {
    // The clear colour, rounded to eight bits a channel, with a byte either
    // way for the conversion.
    for (background[0..3], 0..) |channel, i| {
        const expected: i32 = @intFromFloat(@round(channel * 255));
        if (@abs(@as(i32, pixel[i]) - expected) > 1) return false;
    }
    return true;
}
