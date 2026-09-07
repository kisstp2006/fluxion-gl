// SPDX-License-Identifier: BSL-1.0

//! Two dimensions: a dozen textured quads bouncing in a window, in one draw
//! call.
//!
//! Run it with `zig build example-scene2d`. Passing `-- --frames 240` has it
//! close itself after a fixed number of frames. Escape quits.
//!
//! `-- --capture scene2d.png` skips the window entirely: it steps the
//! bouncing to `--at SECONDS`, draws one frame into a framebuffer object and
//! writes it out, which is how this can be looked at on a machine with no
//! display.
//!
//! There is no depth buffer here and no perspective. What there is instead is
//! the thing 2D wants and 3D can take or leave:
//!
//!   * an orthographic matrix, so that one unit is one pixel and the origin
//!     is the bottom left corner - which is where OpenGL's origin already is,
//!     and arguing with it costs more than it saves;
//!   * one quad in a buffer, and a second buffer holding where each sprite
//!     goes and what colour it is, with `vertexAttribDivisor` telling the
//!     driver to step through it once per instance rather than once per
//!     vertex - so a dozen sprites cost one `drawArraysInstanced` and not a
//!     dozen draws;
//!   * that second buffer rewritten every frame with `bufferSubData`, which
//!     is what a sprite renderer actually does;
//!   * alpha blending, so the transparent corners of the texture are
//!     transparent and the overlaps show through.

const std = @import("std");
const Io = std.Io;

const opengl = @import("fluxion_gl");
const capture = @import("capture");
const math = @import("fluxion_math");
const render = @import("render");
const Window = @import("window").Window;

const c = opengl.enums;
const types = opengl.types;

const background = [4]f32{ 0.05, 0.06, 0.09, 1 };

/// How many bounce about. One draw call either way, which is the point.
const count = 12;

// -------------------------------------------------------------------------
// The sprites
// -------------------------------------------------------------------------

/// One quad, as a triangle strip: two floats of position in 0..1 and two of
/// texture coordinate. Four vertices, and the same four for every sprite on
/// the screen.
const quad = [_]f32{
    0, 0, 0, 0,
    1, 0, 1, 0,
    0, 1, 0, 1,
    1, 1, 1, 1,
};

/// What the driver steps through once per sprite: where it is, how big it is,
/// and what colour. Eight floats, and the only thing that differs between one
/// sprite and the next.
const Instance = extern struct {
    /// x, y, size, and a float that is there so the next field starts on a
    /// sixteen-byte boundary - which nothing here requires and every driver
    /// prefers.
    placement: [4]f32,
    colour: [4]f32,
};

/// One sprite's own business, which the GPU never sees.
const Sprite = struct {
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
    size: f32,
    colour: [4]f32,
};

const Scene = struct {
    sprites: [count]Sprite,
    width: f32,
    height: f32,

    /// Deterministic on purpose: `--capture` has to produce the same picture
    /// every time it is asked for the same moment.
    fn init(width: u32, height: u32) Scene {
        var random: std.Random.DefaultPrng = .init(0x5EED);
        const rand = random.random();

        var self: Scene = .{
            .sprites = undefined,
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
        };

        for (&self.sprites, 0..) |*sprite, i| {
            const size = 48 + rand.float(f32) * 64;
            sprite.* = .{
                .x = rand.float(f32) * (self.width - size),
                .y = rand.float(f32) * (self.height - size),
                .dx = (rand.float(f32) - 0.5) * 260,
                .dy = (rand.float(f32) - 0.5) * 260,
                .size = size,
                // Around the wheel, so that no two are the same and none of
                // them is the background.
                .colour = hue(@as(f32, @floatFromInt(i)) / count, 0.85),
            };
        }
        return self;
    }

    fn resize(self: *Scene, width: u32, height: u32) void {
        self.width = @floatFromInt(width);
        self.height = @floatFromInt(height);
    }

    /// Move them, and turn them round at the walls.
    fn step(self: *Scene, seconds: f32) void {
        for (&self.sprites) |*sprite| {
            sprite.x += sprite.dx * seconds;
            sprite.y += sprite.dy * seconds;

            if (sprite.x < 0) {
                sprite.x = 0;
                sprite.dx = -sprite.dx;
            }
            if (sprite.y < 0) {
                sprite.y = 0;
                sprite.dy = -sprite.dy;
            }
            if (sprite.x + sprite.size > self.width) {
                sprite.x = self.width - sprite.size;
                sprite.dx = -sprite.dx;
            }
            if (sprite.y + sprite.size > self.height) {
                sprite.y = self.height - sprite.size;
                sprite.dy = -sprite.dy;
            }
        }
    }

    /// What the instance buffer wants: the same sprites, without anything the
    /// GPU has no use for.
    fn instances(self: Scene) [count]Instance {
        var out: [count]Instance = undefined;
        for (&out, self.sprites) |*instance, sprite| {
            instance.* = .{
                .placement = .{ sprite.x, sprite.y, sprite.size, 0 },
                .colour = sprite.colour,
            };
        }
        return out;
    }
};

/// A colour wheel, so that a dozen sprites are a dozen colours without a
/// table of them.
fn hue(turn: f32, alpha: f32) [4]f32 {
    const angle = turn * std.math.tau;
    return .{
        0.5 + 0.45 * @cos(angle),
        0.5 + 0.45 * @cos(angle - std.math.tau / 3.0),
        0.5 + 0.45 * @cos(angle + std.math.tau / 3.0),
        alpha,
    };
}

/// Sixteen by sixteen, RGBA: a bright border, a dimmer inside, and four
/// corners that are not there at all - which is what makes the blending
/// visible.
fn makeTexture() [16 * 16 * 4]u8 {
    var pixels: [16 * 16 * 4]u8 = undefined;
    for (0..16) |y| {
        for (0..16) |x| {
            const edge = x < 2 or y < 2 or x > 13 or y > 13;
            const corner = (x + y < 4) or (x + (15 - y) < 4) or ((15 - x) + y < 4) or ((15 - x) + (15 - y) < 4);
            const level: u8 = if (edge) 255 else if ((x / 2 + y / 2) % 2 == 0) 190 else 150;

            const at = (y * 16 + x) * 4;
            pixels[at + 0] = level;
            pixels[at + 1] = level;
            pixels[at + 2] = level;
            pixels[at + 3] = if (corner) 0 else 255;
        }
    }
    return pixels;
}

const sources: render.Program.Sources = .{
    .vertex =
    \\#version 330 core
    \\
    \\layout(location = 0) in vec2 corner;
    \\layout(location = 1) in vec2 uv;
    \\
    \\// These two step once per instance rather than once per vertex, which
    \\// is not something the shader can tell: `glVertexAttribDivisor` says so
    \\// on the other side of the API.
    \\layout(location = 2) in vec4 placement;
    \\layout(location = 3) in vec4 tint;
    \\
    \\uniform mat4 projection;
    \\
    \\out vec2 texcoord;
    \\out vec4 colour;
    \\
    \\void main() {
    \\    vec2 world = placement.xy + corner * placement.z;
    \\    texcoord = uv;
    \\    colour = tint;
    \\    gl_Position = projection * vec4(world, 0.0, 1.0);
    \\}
    ,
    .fragment =
    \\#version 330 core
    \\
    \\in vec2 texcoord;
    \\in vec4 colour;
    \\out vec4 result;
    \\
    \\uniform sampler2D atlas;
    \\
    \\void main() {
    \\    result = texture(atlas, texcoord) * colour;
    \\}
    ,
};

const Sprites = struct {
    program: render.Program,
    vao: types.Uint = 0,
    mesh: types.Uint = 0,
    instances: types.Uint = 0,
    texture: types.Uint = 0,
    projection: types.Int = -1,

    fn init(api: *const opengl.Gl, log: *Io.Writer) !Sprites {
        var self: Sprites = .{ .program = try render.Program.compile(api, sources, log) };

        api.genVertexArrays(1, @ptrCast(&self.vao));
        api.bindVertexArray(self.vao);

        // The quad, uploaded once and never touched again.
        api.genBuffers(1, @ptrCast(&self.mesh));
        api.bindBuffer(c.array_buffer, self.mesh);
        api.bufferData(c.array_buffer, @sizeOf(@TypeOf(quad)), &quad, c.static_draw);
        api.vertexAttribPointer(0, 2, c.float, types.gl_false, 4 * @sizeOf(f32), opengl.offset(0));
        api.enableVertexAttribArray(0);
        api.vertexAttribPointer(1, 2, c.float, types.gl_false, 4 * @sizeOf(f32), opengl.offset(2 * @sizeOf(f32)));
        api.enableVertexAttribArray(1);

        // The sprites, rewritten every frame. Passing null for the data
        // allocates without uploading, which is what a buffer that is filled
        // in later wants.
        api.genBuffers(1, @ptrCast(&self.instances));
        api.bindBuffer(c.array_buffer, self.instances);
        api.bufferData(c.array_buffer, @sizeOf(Instance) * count, null, c.dynamic_draw);
        api.vertexAttribPointer(2, 4, c.float, types.gl_false, @sizeOf(Instance), opengl.offset(@offsetOf(Instance, "placement")));
        api.enableVertexAttribArray(2);
        api.vertexAttribPointer(3, 4, c.float, types.gl_false, @sizeOf(Instance), opengl.offset(@offsetOf(Instance, "colour")));
        api.enableVertexAttribArray(3);

        // The divisor is the whole of instancing: zero means "one per
        // vertex", one means "one per instance", and these two attributes
        // describe a sprite rather than a corner.
        api.vertexAttribDivisor(2, 1);
        api.vertexAttribDivisor(3, 1);

        api.genTextures(1, @ptrCast(&self.texture));
        api.activeTexture(c.texture0);
        api.bindTexture(c.texture_2d, self.texture);
        const texels = makeTexture();
        api.texImage2D(c.texture_2d, 0, c.rgba8, 16, 16, 0, c.rgba, c.unsigned_byte, &texels);
        // Nearest, because the point of the picture is the shape rather than
        // the smoothing, and clamped, because a sprite that samples past its
        // own edge picks up the other side of itself.
        api.texParameteri(c.texture_2d, c.texture_min_filter, c.nearest);
        api.texParameteri(c.texture_2d, c.texture_mag_filter, c.nearest);
        api.texParameteri(c.texture_2d, c.texture_wrap_s, c.clamp_to_edge);
        api.texParameteri(c.texture_2d, c.texture_wrap_t, c.clamp_to_edge);

        self.projection = self.program.location(api, "projection");
        self.program.use(api);
        // Which texture unit the sampler reads, as an integer: unit zero.
        api.uniform1i(self.program.location(api, "atlas"), 0);

        return self;
    }

    fn draw(self: Sprites, api: *const opengl.Gl, scene: Scene) void {
        api.disable(c.depth_test);
        api.enable(c.blend);
        api.blendFunc(c.src_alpha, c.one_minus_src_alpha);

        const instances = scene.instances();
        api.bindBuffer(c.array_buffer, self.instances);
        api.bufferSubData(c.array_buffer, 0, @sizeOf(@TypeOf(instances)), &instances);

        // One unit is one pixel, origin at the bottom left - which is where
        // OpenGL puts it, and what `Clip.gl` says.
        const projection = math.orthographic(.{
            .left = 0,
            .right = scene.width,
            .bottom = 0,
            .top = scene.height,
            .near = -1,
            .far = 1,
            .clip = .gl,
        }).array();
        self.program.use(api);
        api.uniformMatrix4fv(self.projection, 1, types.gl_false, &projection);

        api.activeTexture(c.texture0);
        api.bindTexture(c.texture_2d, self.texture);

        api.bindVertexArray(self.vao);
        api.drawArraysInstanced(c.triangle_strip, 0, 4, count);
    }

    fn deinit(self: *Sprites, api: *const opengl.Gl) void {
        api.deleteTextures(1, @ptrCast(&self.texture));
        api.deleteBuffers(1, @ptrCast(&self.instances));
        api.deleteBuffers(1, @ptrCast(&self.mesh));
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

    var window = Window.open(.{
        .title = "Fluxion GL - 2D",
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
    try out.print("{d} sprites, one draw call a frame\n", .{count});
    try out.flush();

    var sprites = Sprites.init(&api, out) catch |err| {
        try out.flush();
        return err;
    };
    defer sprites.deinit(&api);

    var scene: Scene = .init(window.width, window.height);

    // --- one frame to a file, and no window on screen ----------------------
    if (options.capture) |path| {
        // Stepped in the same slices a frame would take, so that the picture
        // is the one the window would have shown at that moment.
        var elapsed: f32 = 0;
        while (elapsed < options.at) : (elapsed += 1.0 / 60.0) scene.step(1.0 / 60.0);

        var screen = try render.Offscreen.init(&api, options.width, options.height, false);
        defer screen.deinit(&api);

        screen.begin(&api, background);
        sprites.draw(&api, scene);

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

    var last = Io.Timestamp.now(init.io, .awake).nanoseconds;
    var frames: u64 = 0;

    while (window.pump()) {
        if (window.minimised()) continue;
        if (window.takeResize()) scene.resize(window.width, window.height);

        const now = Io.Timestamp.now(init.io, .awake).nanoseconds;
        const seconds: f32 = @floatCast(@as(f64, @floatFromInt(now - last)) / std.time.ns_per_s);
        last = now;
        // A frame that took a quarter of a second - the window was being
        // dragged, or the machine was busy - would teleport a sprite through
        // a wall, so the step is capped rather than trusted.
        scene.step(@min(seconds, 1.0 / 20.0));

        api.viewport(0, 0, @intCast(window.width), @intCast(window.height));
        api.clearColor(background[0], background[1], background[2], background[3]);
        api.clear(c.color_buffer_bit);

        sprites.draw(&api, scene);
        window.present();

        frames += 1;
        if (options.frames) |limit| {
            if (frames >= limit) break;
        }
    }

    try out.print("{d} frames\n", .{frames});
    try out.flush();
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
    /// `--at SECONDS`: how far into the bouncing to capture. The default is
    /// long enough for the sprites to have spread out and started to overlap.
    at: f32 = 3.0,
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

test "the instance data is laid out as the strides say" {
    try testing.expectEqual(@as(usize, 32), @sizeOf(Instance));
    try testing.expectEqual(@as(usize, 0), @offsetOf(Instance, "placement"));
    try testing.expectEqual(@as(usize, 16), @offsetOf(Instance, "colour"));
}

test "the sprites stay inside the window" {
    var scene: Scene = .init(320, 200);
    // Long enough for every one of them to have reached a wall several times.
    for (0..600) |_| scene.step(1.0 / 60.0);

    for (scene.sprites) |sprite| {
        try testing.expect(sprite.x >= 0);
        try testing.expect(sprite.y >= 0);
        try testing.expect(sprite.x + sprite.size <= scene.width + 0.001);
        try testing.expect(sprite.y + sprite.size <= scene.height + 0.001);
    }
}

test "the same moment is the same picture" {
    var first: Scene = .init(640, 480);
    var second: Scene = .init(640, 480);
    for (0..120) |_| first.step(1.0 / 60.0);
    for (0..120) |_| second.step(1.0 / 60.0);

    for (first.sprites, second.sprites) |a, b| {
        try testing.expectEqual(a.x, b.x);
        try testing.expectEqual(a.y, b.y);
    }
}

test "a frame of it, rendered and looked at" {
    var window = try @import("window").openForTest(256, 128);
    defer window.close();

    var api: opengl.Gl = undefined;
    try api.load(window.resolver());

    var log_buffer: [4096]u8 = undefined;
    var log: Io.Writer = .fixed(&log_buffer);
    var sprites = Sprites.init(&api, &log) catch |err| {
        std.debug.print("{s}\n", .{log.buffered()});
        return err;
    };
    defer sprites.deinit(&api);

    var scene: Scene = .init(256, 128);
    for (0..180) |_| scene.step(1.0 / 60.0);

    var screen = try render.Offscreen.init(&api, 256, 128, false);
    defer screen.deinit(&api);

    screen.begin(&api, background);
    sprites.draw(&api, scene);

    const pixels = try screen.read(&api, testing.allocator);
    defer testing.allocator.free(pixels);
    try testing.expectEqual(null, api.checkError());

    // Something was drawn, and it was not everything: a dozen sprites of that
    // size cover a good part of a small window and nothing like all of it.
    var covered: usize = 0;
    var colours: [64][3]u8 = undefined;
    var distinct: usize = 0;
    for (0..128) |y| {
        for (0..256) |x| {
            const pixel = render.pixelAt(pixels, 256, @intCast(x), @intCast(y));
            if (isBackground(pixel)) continue;
            covered += 1;
            const rgb: [3]u8 = .{ pixel[0], pixel[1], pixel[2] };
            for (colours[0..distinct]) |already| {
                if (std.mem.eql(u8, &already, &rgb)) break;
            } else {
                if (distinct < colours.len) {
                    colours[distinct] = rgb;
                    distinct += 1;
                }
            }
        }
    }

    try testing.expect(covered > 1000);
    try testing.expect(covered < 256 * 128);
    // A dozen sprites, each a different colour on a different background of
    // whatever is behind it: several distinct colours, and not one.
    try testing.expect(distinct >= 8);
}

fn isBackground(pixel: [4]u8) bool {
    for (background[0..3], 0..) |channel, i| {
        const expected: i32 = @intFromFloat(@round(channel * 255));
        if (@abs(@as(i32, pixel[i]) - expected) > 1) return false;
    }
    return true;
}
