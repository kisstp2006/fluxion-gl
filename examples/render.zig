// SPDX-License-Identifier: BSL-1.0

//! The parts of drawing that every example does the same way.
//!
//! The library stops where OpenGL stops, which is further along than a
//! Direct3D loader gets: `opengl.Gl` has every command a frame needs, and
//! there is nothing here that reaches around it. What is here is the
//! boilerplate that has to be written once and is dull to write twice.
//!
//! `Program` is the shader dance. A shader that fails to compile is not an
//! error OpenGL raises - `glCompileShader` returns nothing and the program
//! links to something that draws an empty screen - so every source has to be
//! followed by `glGetShaderiv(compile_status)` and, when that says no, by the
//! driver's own log. That log is the single most useful thing in OpenGL and
//! the easiest to forget to ask for.
//!
//! `Offscreen` is a framebuffer object with nothing on screen behind it, so a
//! frame can be drawn and read back on a machine nobody is looking at. It is
//! what `--capture` uses, and what the tests draw into.
//!
//! Nothing here is part of the library.

const std = @import("std");
const Io = std.Io;

const opengl = @import("fluxion_gl");
const c = opengl.enums;
const types = opengl.types;

const Gl = opengl.Gl;

pub const Error = error{
    ShaderFailed,
    LinkFailed,
    FramebufferIncomplete,
};

/// A linked program, and the two shaders behind it.
pub const Program = struct {
    name: types.Uint,

    pub const Sources = struct {
        vertex: [:0]const u8,
        fragment: [:0]const u8,
    };

    /// Compile both, link them, and delete the shaders - which is allowed the
    /// moment they are attached, because the program holds its own reference.
    ///
    /// `log` is where the driver's complaint goes when something does not
    /// build. It is not optional on purpose: a silent shader failure is the
    /// commonest way to spend an afternoon looking at a black window.
    pub fn compile(api: *const Gl, sources: Sources, log: *Io.Writer) !Program {
        const vertex = try shader(api, c.vertex_shader, sources.vertex, log);
        defer api.deleteShader(vertex);

        const fragment = try shader(api, c.fragment_shader, sources.fragment, log);
        defer api.deleteShader(fragment);

        const name = api.createProgram();
        errdefer api.deleteProgram(name);

        api.attachShader(name, vertex);
        api.attachShader(name, fragment);
        api.linkProgram(name);

        var linked: [1]types.Int = .{0};
        api.getProgramiv(name, c.link_status, &linked);
        if (!types.isTrue(@intCast(linked[0] & 1))) {
            var text: [4096]types.Char = undefined;
            var length: types.Sizei = 0;
            api.getProgramInfoLog(name, text.len, &length, &text);
            try log.print("the program did not link:\n{s}\n", .{text[0..@intCast(length)]});
            return error.LinkFailed;
        }

        return .{ .name = name };
    }

    pub fn use(self: Program, api: *const Gl) void {
        api.useProgram(self.name);
    }

    /// Where a uniform ended up, or -1 for one the linker removed - which
    /// includes every uniform the shader does not actually read.
    pub fn location(self: Program, api: *const Gl, name: [:0]const u8) types.Int {
        return api.getUniformLocation(self.name, name.ptr);
    }

    pub fn deinit(self: *Program, api: *const Gl) void {
        api.deleteProgram(self.name);
        self.* = undefined;
    }
};

fn shader(api: *const Gl, kind: types.Enum, source: [:0]const u8, log: *Io.Writer) !types.Uint {
    const name = api.createShader(kind);
    errdefer api.deleteShader(name);

    api.shaderSource(name, 1, &.{source.ptr}, null);
    api.compileShader(name);

    var compiled: [1]types.Int = .{0};
    api.getShaderiv(name, c.compile_status, &compiled);
    if (!types.isTrue(@intCast(compiled[0] & 1))) {
        var text: [4096]types.Char = undefined;
        var length: types.Sizei = 0;
        api.getShaderInfoLog(name, text.len, &length, &text);
        try log.print("the {s} shader did not compile:\n{s}\n", .{
            if (kind == c.vertex_shader) "vertex" else "fragment",
            text[0..@intCast(length)],
        });
        return error.ShaderFailed;
    }

    return name;
}

/// Somewhere to draw that is not the window.
///
/// A colour renderbuffer and, if asked for, a depth one, in a framebuffer
/// object. Renderbuffers rather than textures because nothing here samples
/// the result: it is drawn into once and read straight back out.
pub const Offscreen = struct {
    framebuffer: types.Uint,
    colour: types.Uint,
    depth: types.Uint,
    width: u32,
    height: u32,

    pub fn init(api: *const Gl, width: u32, height: u32, want_depth: bool) !Offscreen {
        var self: Offscreen = .{
            .framebuffer = 0,
            .colour = 0,
            .depth = 0,
            .width = width,
            .height = height,
        };

        api.genFramebuffers(1, @ptrCast(&self.framebuffer));
        api.bindFramebuffer(c.framebuffer, self.framebuffer);

        api.genRenderbuffers(1, @ptrCast(&self.colour));
        api.bindRenderbuffer(c.renderbuffer, self.colour);
        api.renderbufferStorage(c.renderbuffer, c.rgba8, @intCast(width), @intCast(height));
        api.framebufferRenderbuffer(c.framebuffer, c.color_attachment0, c.renderbuffer, self.colour);

        if (want_depth) {
            api.genRenderbuffers(1, @ptrCast(&self.depth));
            api.bindRenderbuffer(c.renderbuffer, self.depth);
            api.renderbufferStorage(c.renderbuffer, c.depth24_stencil8, @intCast(width), @intCast(height));
            api.framebufferRenderbuffer(c.framebuffer, c.depth_stencil_attachment, c.renderbuffer, self.depth);
        }

        // Anything but complete means the next draw goes nowhere, quietly.
        if (api.checkFramebufferStatus(c.framebuffer) != c.framebuffer_complete) {
            self.deinit(api);
            return error.FramebufferIncomplete;
        }

        return self;
    }

    /// Bind it, cover it, and start a frame.
    pub fn begin(self: Offscreen, api: *const Gl, background: [4]f32) void {
        api.bindFramebuffer(c.framebuffer, self.framebuffer);
        api.viewport(0, 0, @intCast(self.width), @intCast(self.height));
        api.clearColor(background[0], background[1], background[2], background[3]);
        api.clearDepth(1);
        api.clear(c.color_buffer_bit | c.depth_buffer_bit);
    }

    /// The pixels, RGBA, four bytes each, bottom row first - which is where
    /// GL's origin is. The caller owns them.
    pub fn read(self: Offscreen, api: *const Gl, gpa: std.mem.Allocator) ![]u8 {
        const pixels = try gpa.alloc(u8, @as(usize, self.width) * self.height * 4);
        errdefer gpa.free(pixels);

        api.bindFramebuffer(c.framebuffer, self.framebuffer);
        // Rows tightly packed. The default is four-byte alignment, which pads
        // every row of an odd-width image and misaligns everything after it.
        api.pixelStorei(c.pack_alignment, 1);
        api.readPixels(
            0,
            0,
            @intCast(self.width),
            @intCast(self.height),
            c.rgba,
            c.unsigned_byte,
            pixels.ptr,
        );
        return pixels;
    }

    pub fn deinit(self: *Offscreen, api: *const Gl) void {
        api.bindFramebuffer(c.framebuffer, 0);
        if (self.depth != 0) api.deleteRenderbuffers(1, @ptrCast(&self.depth));
        if (self.colour != 0) api.deleteRenderbuffers(1, @ptrCast(&self.colour));
        if (self.framebuffer != 0) api.deleteFramebuffers(1, @ptrCast(&self.framebuffer));
        self.* = undefined;
    }
};

/// The pixel at `x`, `y` of what `Offscreen.read` handed back, counting from
/// the bottom left corner as GL does.
pub fn pixelAt(pixels: []const u8, width: u32, x: u32, y: u32) [4]u8 {
    return pixels[(@as(usize, y) * width + x) * 4 ..][0..4].*;
}

// -------------------------------------------------------------------------
// Tests
//
// These need a context, and a machine with no OpenGL is a machine the
// examples cannot run on rather than a failing test - so they skip.
// -------------------------------------------------------------------------

const Window = @import("window").Window;
const testing = std.testing;

fn context() !Window {
    return Window.open(.{ .title = "fluxion-gl test", .width = 64, .height = 64, .visible = false }) catch |err| switch (err) {
        error.NoModernContext, error.ContextFailed, error.PixelFormatFailed => error.SkipZigTest,
        else => err,
    };
}

const flat_vertex =
    \\#version 330 core
    \\in vec2 position;
    \\void main() { gl_Position = vec4(position, 0.0, 1.0); }
;

const flat_fragment =
    \\#version 330 core
    \\out vec4 colour;
    \\void main() { colour = vec4(1.0, 0.5, 0.25, 1.0); }
;

test "a shader that does not compile says so, and says why" {
    var window = try context();
    defer window.close();

    var api: Gl = undefined;
    try api.load(window.resolver());

    var buffer: [4096]u8 = undefined;
    var log: Io.Writer = .fixed(&buffer);

    const broken = Program.compile(&api, .{
        .vertex =
        \\#version 330 core
        \\void main() { this is not GLSL }
        ,
        .fragment = flat_fragment,
    }, &log);

    try testing.expectError(error.ShaderFailed, broken);
    // Whatever the driver calls it, it said something about the vertex one.
    try testing.expect(std.mem.indexOf(u8, log.buffered(), "vertex") != null);
    try testing.expect(log.buffered().len > 40);
}

test "a triangle drawn offscreen lands where it was aimed" {
    var window = try context();
    defer window.close();

    var api: Gl = undefined;
    try api.load(window.resolver());

    var buffer: [4096]u8 = undefined;
    var log: Io.Writer = .fixed(&buffer);
    var program = Program.compile(&api, .{ .vertex = flat_vertex, .fragment = flat_fragment }, &log) catch |err| {
        std.debug.print("{s}\n", .{log.buffered()});
        return err;
    };
    defer program.deinit(&api);

    var screen = try Offscreen.init(&api, 64, 64, true);
    defer screen.deinit(&api);

    // A triangle over the middle of the target, with its corners short of
    // the corners of it.
    const vertices = [_]f32{ -0.8, -0.8, 0.8, -0.8, 0.0, 0.8 };

    var vao: types.Uint = 0;
    api.genVertexArrays(1, @ptrCast(&vao));
    api.bindVertexArray(vao);
    defer api.deleteVertexArrays(1, @ptrCast(&vao));

    var vbo: types.Uint = 0;
    api.genBuffers(1, @ptrCast(&vbo));
    api.bindBuffer(c.array_buffer, vbo);
    api.bufferData(c.array_buffer, @sizeOf(@TypeOf(vertices)), &vertices, c.static_draw);
    defer api.deleteBuffers(1, @ptrCast(&vbo));

    const position: types.Uint = @intCast(api.getAttribLocation(program.name, "position"));
    api.vertexAttribPointer(position, 2, c.float, types.gl_false, 2 * @sizeOf(f32), opengl.offset(0));
    api.enableVertexAttribArray(position);

    screen.begin(&api, .{ 0, 0, 0, 1 });
    program.use(&api);
    api.drawArrays(c.triangles, 0, 3);

    const pixels = try screen.read(&api, testing.allocator);
    defer testing.allocator.free(pixels);

    try testing.expectEqual(null, api.checkError());

    // The middle is the triangle, and the top corners are not: the shape has
    // a point at the top and a wide base, so getting this backwards - a
    // flipped viewport, a mirrored projection - shows up here.
    const middle = pixelAt(pixels, 64, 32, 24);
    try testing.expect(middle[0] > 200 and middle[1] > 100 and middle[2] < 100);
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, pixelAt(pixels, 64, 2, 60));
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, pixelAt(pixels, 64, 61, 60));
    // The bottom corners are outside it too, because it stops short of them.
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, pixelAt(pixels, 64, 1, 1));
}
