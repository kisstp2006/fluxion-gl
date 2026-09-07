// SPDX-License-Identifier: CC0-1.0

//! A graphics driver that is not there.
//!
//! The examples in this directory have to run on the machine that builds
//! them, which has no window and may have no graphics card, so this file
//! stands in for one: a `getProcAddress` that hands out `gl` entry points by
//! name, behind them a software rasteriser, and at the end a framebuffer that
//! `readPixels` copies out like any other.
//!
//! What is real about it is the interface. These are the commands with their
//! true signatures, resolved by `fluxion_gl` exactly as a driver's would be,
//! so the examples on the other side are the program you would write against
//! a live context. Replace `driver.getProcAddress` with `glfwGetProcAddress`
//! and they draw on a screen.
//!
//! What is a toy is everything else. There is no shading language in here.
//! The vertex stage is one matrix multiply and the fragment stage is a
//! multiply of four colours, both fixed:
//!
//!   attribute 0   position, 2 to 4 floats
//!   attribute 1   colour, 3 or 4 floats, white by default
//!   attribute 2   texture coordinates, 2 floats
//!   attribute 3   per-instance offset in xyz and scale in w, when its
//!                 divisor is not zero
//!   attribute 4   per-instance colour, likewise
//!   uniform 0     the model-view-projection matrix, from `uniformMatrix4fv`
//!   uniform 1     a tint, from `uniform4f`
//!
//!   position = mvp * vec4(attribute0 * instance.w + instance.xyz, 1)
//!   colour   = attribute1 * instanceColour * texture(attribute2) * tint
//!
//! It has no clipping, no perspective-correct interpolation, no mipmaps and
//! no multisampling, and it draws triangles and nothing else. At the size
//! these examples print - a few thousand pixels, as characters - none of that
//! shows.

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const opengl = @import("fluxion_gl");
const c = opengl.enums;
const types = opengl.types;

// -------------------------------------------------------------------------
// What an example may set
// -------------------------------------------------------------------------

/// Where the call log goes. Null keeps it quiet, which is what an example
/// that prints a picture wants.
pub var output: ?*Io.Writer = null;

/// Print every command as it arrives. Off by default: a frame is a few
/// hundred calls and only the first example wants to see them all.
pub var log_calls: bool = false;

/// What `getString` answers. An example that wants to be an ES 3.0 device
/// says so here before it loads anything.
pub var reported_version: [:0]const u8 = "3.3.0 Fluxion Software Rasteriser 1.0";
pub var reported_glsl: [:0]const u8 = "3.30 Fluxion";
pub var reported_renderer: [:0]const u8 = "Fluxion Reference Device";
pub var reported_vendor: [:0]const u8 = "Nobody in particular";
pub var reported_extensions: []const [:0]const u8 = &.{
    "GL_ARB_debug_output",
    "GL_KHR_debug",
    "GL_EXT_texture_filter_anisotropic",
    "GL_OES_vertex_array_object",
};

/// Commands to pretend not to have, under the names `getProcAddress` is
/// asked for them: `&.{"glBindVertexArray"}` makes this an older device on
/// purpose. Every driver in the world has a list like this; most of them do
/// not know it.
pub var absent: []const []const u8 = &.{};

/// The largest framebuffer `makeContext` will hand out. A terminal is not
/// large.
pub const max_width = 200;
pub const max_height = 80;

// -------------------------------------------------------------------------
// Standing in for the window library
// -------------------------------------------------------------------------

/// What GLFW's `glfwCreateWindow` and `glfwMakeContextCurrent` amount to
/// here: a framebuffer of this size, and everything else forgotten.
///
/// Call it before `load`, for the same reason a real program does: without a
/// current context, `getProcAddress` is allowed to answer null for
/// everything.
pub fn makeContext(width: usize, height: usize) void {
    state = .{};
    state.width = @min(width, max_width);
    state.height = @min(height, max_height);
    state.viewport = .{ 0, 0, @intCast(state.width), @intCast(state.height) };

    // The objects go with the context that made them, and the memory they
    // were in is handed out again from the start - so they have to be
    // forgotten together, or a name from the last context would point at
    // whatever the next one uploads.
    buffers = @splat(.{});
    textures = @splat(.{});
    arena_used = 0;
    flat_len = null;

    @memset(colour_buffer[0 .. state.width * state.height * 4], 0);
    @memset(depth_buffer[0 .. state.width * state.height], 1.0);
}

/// The one function a program has to be given. Hands back the address of any
/// command this driver has, and null for the rest - which is what a driver
/// that is a version behind does, and what makes the optional half of a
/// command table worth having.
pub fn getProcAddress(name: [*:0]const u8) callconv(.c) ?opengl.Proc {
    const wanted = std.mem.span(name);
    for (absent) |gone| {
        if (std.mem.eql(u8, gone, wanted)) return null;
    }
    inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        if (comptime std.mem.startsWith(u8, decl.name, "gl")) {
            if (std.mem.eql(u8, decl.name, wanted)) return @ptrCast(&@field(@This(), decl.name));
        }
    }
    return null;
}

/// What the frame cost, for the line an example prints at the end.
pub const Stats = struct {
    draw_calls: usize = 0,
    instances: usize = 0,
    triangles: usize = 0,
    pixels: usize = 0,
    uploaded: usize = 0,

    pub fn format(self: Stats, w: *Io.Writer) Io.Writer.Error!void {
        try w.print(
            "{d} draw call{s}, {d} instances, {d} triangles, {d} pixels shaded, {d} bytes uploaded",
            .{ self.draw_calls, if (self.draw_calls == 1) "" else "s", self.instances, self.triangles, self.pixels, self.uploaded },
        );
    }
};

pub fn stats() Stats {
    return state.stats;
}

/// Forget the counters, so that a program can measure one frame rather than
/// every frame since the context was made.
pub fn resetStats() void {
    state.stats = .{};
}

/// Print what `readPixels` handed back, as characters.
///
/// Not part of OpenGL, and the only place in these examples where the
/// framebuffer is treated as anything but bytes. GL's origin is the bottom
/// left corner, so the rows come out of `readPixels` upside down as far as a
/// terminal is concerned, and this walks them backwards.
pub fn writeImage(w: *Io.Writer, pixels: []const u8, width: usize, height: usize) Io.Writer.Error!void {
    const ramp = " .:-=+*#%@";

    try w.writeAll("    +");
    for (0..width) |_| try w.writeAll("-");
    try w.writeAll("+\n");

    var row = height;
    while (row > 0) {
        row -= 1;
        try w.writeAll("    |");
        for (0..width) |column| {
            const at = (row * width + column) * 4;
            const luminance = (@as(u32, pixels[at]) * 2 + @as(u32, pixels[at + 1]) * 3 + @as(u32, pixels[at + 2])) / 6;
            const step = luminance * (ramp.len - 1) / 255;
            try w.writeByte(ramp[@min(step, ramp.len - 1)]);
        }
        try w.writeAll("|\n");
    }

    try w.writeAll("    +");
    for (0..width) |_| try w.writeAll("-");
    try w.writeAll("+\n");
}

// -------------------------------------------------------------------------
// The state a driver keeps, and the memory it keeps it in
// -------------------------------------------------------------------------

const Attribute = struct {
    enabled: bool = false,
    components: usize = 4,
    stride: usize = 0,
    offset: usize = 0,
    buffer: u32 = 0,
    divisor: u32 = 0,
};

const Buffer = struct {
    data: []u8 = &.{},
};

const Texture = struct {
    width: usize = 0,
    height: usize = 0,
    pixels: []u8 = &.{},
};

const State = struct {
    width: usize = 0,
    height: usize = 0,
    viewport: [4]types.Int = .{ 0, 0, 0, 0 },
    scissor: [4]types.Int = .{ 0, 0, 0, 0 },

    clear_colour: [4]f32 = .{ 0, 0, 0, 1 },
    clear_depth: f32 = 1,

    depth_test: bool = false,
    cull_face: bool = false,
    blend: bool = false,
    scissor_test: bool = false,
    cull_mode: types.Enum = c.back,
    front_face: types.Enum = c.ccw,
    blend_src: types.Enum = c.one,
    blend_dst: types.Enum = c.zero,

    attributes: [8]Attribute = @splat(.{}),
    array_buffer: u32 = 0,
    element_buffer: u32 = 0,
    vertex_array: u32 = 0,
    program: u32 = 0,
    texture_2d: u32 = 0,

    mvp: [16]f32 = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
    tint: [4]f32 = .{ 1, 1, 1, 1 },

    next_name: u32 = 1,
    errors: [4]types.Enum = @splat(c.no_error),
    error_count: usize = 0,
    debug_callback: ?types.DebugProc = null,
    stats: Stats = .{},
};

var state: State = .{};

var buffers: [32]Buffer = @splat(.{});
var textures: [16]Texture = @splat(.{});

var colour_buffer: [max_width * max_height * 4]u8 = undefined;
var depth_buffer: [max_width * max_height]f32 = undefined;

/// A driver has memory to give out. This one has this much, and no way of
/// giving any of it back: `deleteBuffers` forgets the name and keeps the
/// bytes, which is fine for a program that runs for a tenth of a second.
var arena: [256 * 1024]u8 = undefined;
var arena_used: usize = 0;

fn allocate(size: usize) []u8 {
    if (arena_used + size > arena.len) {
        raise(c.out_of_memory);
        return &.{};
    }
    defer arena_used += size;
    return arena[arena_used..][0..size];
}

fn raise(code: types.Enum) void {
    if (state.error_count < state.errors.len) {
        state.errors[state.error_count] = code;
        state.error_count += 1;
    }
    if (state.debug_callback) |callback| {
        const message = "the last command was refused";
        callback(c.debug_source_api, c.debug_type_error, code, c.debug_severity_high, message.len, message, null);
    }
}

fn note(comptime fmt: []const u8, args: anytype) void {
    if (!log_calls) return;
    const w = output orelse return;
    w.print("  " ++ fmt ++ "\n", args) catch {};
}

// -------------------------------------------------------------------------
// The commands: asking the context about itself
// -------------------------------------------------------------------------

pub fn glGetString(name: types.Enum) callconv(.c) ?[*:0]const types.Char {
    return switch (name) {
        c.version => reported_version.ptr,
        c.shading_language_version => reported_glsl.ptr,
        c.renderer => reported_renderer.ptr,
        c.vendor => reported_vendor.ptr,
        c.extensions => flatExtensions(),
        else => null,
    };
}

pub fn glGetStringi(name: types.Enum, index: types.Uint) callconv(.c) ?[*:0]const types.Char {
    if (name != c.extensions or index >= reported_extensions.len) return null;
    return reported_extensions[index].ptr;
}

pub fn glGetIntegerv(pname: types.Enum, data: [*]types.Int) callconv(.c) void {
    switch (pname) {
        c.num_extensions => data[0] = @intCast(reported_extensions.len),
        c.major_version => data[0] = 3,
        c.minor_version => data[0] = 3,
        c.max_texture_size => data[0] = 4096,
        c.max_3d_texture_size => data[0] = 256,
        c.max_cube_map_texture_size => data[0] = 4096,
        c.max_array_texture_layers => data[0] = 256,
        c.max_renderbuffer_size => data[0] = 4096,
        c.max_vertex_attribs => data[0] = @intCast(state.attributes.len),
        c.max_texture_image_units => data[0] = 8,
        c.max_combined_texture_image_units => data[0] = 8,
        c.max_draw_buffers => data[0] = 1,
        c.max_color_attachments => data[0] = 1,
        c.max_samples => data[0] = 1,
        c.max_uniform_block_size => data[0] = 16384,
        c.context_profile_mask => data[0] = @intCast(c.context_core_profile_bit),
        c.context_flags => data[0] = 0,
        c.viewport => for (state.viewport, 0..) |v, i| {
            data[i] = v;
        },
        c.max_viewport_dims => {
            data[0] = max_width;
            data[1] = max_height;
        },
        c.sample_buffers, c.samples => data[0] = 0,
        c.subpixel_bits => data[0] = 0,
        else => data[0] = 0,
    }
}

pub fn glGetFloatv(pname: types.Enum, data: [*]types.Float) callconv(.c) void {
    switch (pname) {
        c.color_clear_value => for (state.clear_colour, 0..) |v, i| {
            data[i] = v;
        },
        c.depth_clear_value => data[0] = state.clear_depth,
        else => data[0] = 0,
    }
}

pub fn glGetBooleanv(pname: types.Enum, data: [*]types.Boolean) callconv(.c) void {
    data[0] = types.boolean(glIsEnabled(pname) != 0);
}

pub fn glGetError() callconv(.c) types.Enum {
    if (state.error_count == 0) return c.no_error;
    const first = state.errors[0];
    for (1..state.error_count) |i| state.errors[i - 1] = state.errors[i];
    state.error_count -= 1;
    return first;
}

pub fn glGetShaderPrecisionFormat(
    shader_type: types.Enum,
    precision_type: types.Enum,
    range: [*]types.Int,
    precision: *types.Int,
) callconv(.c) void {
    _ = .{ shader_type, precision_type };
    range[0] = 127;
    range[1] = 127;
    precision.* = 23;
}

// -------------------------------------------------------------------------
// The commands: state
// -------------------------------------------------------------------------

pub fn glViewport(x: types.Int, y: types.Int, width: types.Sizei, height: types.Sizei) callconv(.c) void {
    note("viewport {d},{d} {d}x{d}", .{ x, y, width, height });
    state.viewport = .{ x, y, width, height };
}

pub fn glScissor(x: types.Int, y: types.Int, width: types.Sizei, height: types.Sizei) callconv(.c) void {
    note("scissor {d},{d} {d}x{d}", .{ x, y, width, height });
    state.scissor = .{ x, y, width, height };
}

pub fn glEnable(capability: types.Enum) callconv(.c) void {
    note("enable 0x{X:0>4}", .{capability});
    setCapability(capability, true);
}

pub fn glDisable(capability: types.Enum) callconv(.c) void {
    note("disable 0x{X:0>4}", .{capability});
    setCapability(capability, false);
}

pub fn glIsEnabled(capability: types.Enum) callconv(.c) types.Boolean {
    return types.boolean(switch (capability) {
        c.depth_test => state.depth_test,
        c.cull_face => state.cull_face,
        c.blend => state.blend,
        c.scissor_test => state.scissor_test,
        else => false,
    });
}

fn setCapability(capability: types.Enum, on: bool) void {
    switch (capability) {
        c.depth_test => state.depth_test = on,
        c.cull_face => state.cull_face = on,
        c.blend => state.blend = on,
        c.scissor_test => state.scissor_test = on,
        c.dither, c.multisample, c.debug_output, c.debug_output_synchronous => {},
        else => raise(c.invalid_enum),
    }
}

pub fn glClearColor(red: types.Clampf, green: types.Clampf, blue: types.Clampf, alpha: types.Clampf) callconv(.c) void {
    note("clearColor {d:.2} {d:.2} {d:.2} {d:.2}", .{ red, green, blue, alpha });
    state.clear_colour = .{ red, green, blue, alpha };
}

pub fn glClearDepth(depth: types.Double) callconv(.c) void {
    state.clear_depth = @floatCast(depth);
}

pub fn glClearDepthf(depth: types.Clampf) callconv(.c) void {
    state.clear_depth = depth;
}

pub fn glClear(mask: types.Bitfield) callconv(.c) void {
    note("clear colour:{s} depth:{s}", .{
        if (mask & c.color_buffer_bit != 0) "yes" else "no",
        if (mask & c.depth_buffer_bit != 0) "yes" else "no",
    });

    // A clear is scissored like everything else, which is what makes
    // `scissor` plus `clear` the usual way to paint a rectangle.
    const box = clipBox();
    const packed_colour = pack(state.clear_colour);

    const first_x: usize = @intCast(@max(box[0], 0));
    const first_y: usize = @intCast(@max(box[1], 0));
    const last_x: usize = @intCast(@max(@min(box[2], @as(i64, @intCast(state.width)) - 1), -1) + 1);
    const last_y: usize = @intCast(@max(@min(box[3], @as(i64, @intCast(state.height)) - 1), -1) + 1);

    for (first_y..last_y) |y| {
        for (first_x..last_x) |x| {
            const slot = y * state.width + x;
            if (mask & c.color_buffer_bit != 0) colour_buffer[slot * 4 ..][0..4].* = packed_colour;
            if (mask & c.depth_buffer_bit != 0) depth_buffer[slot] = state.clear_depth;
        }
    }
}

pub fn glBlendFunc(src: types.Enum, dst: types.Enum) callconv(.c) void {
    note("blendFunc 0x{X:0>4} 0x{X:0>4}", .{ src, dst });
    state.blend_src = src;
    state.blend_dst = dst;
}

pub fn glCullFace(mode: types.Enum) callconv(.c) void {
    state.cull_mode = mode;
}

pub fn glFrontFace(mode: types.Enum) callconv(.c) void {
    state.front_face = mode;
}

pub fn glDepthFunc(func: types.Enum) callconv(.c) void {
    _ = func;
}

pub fn glDepthMask(flag: types.Boolean) callconv(.c) void {
    _ = flag;
}

pub fn glColorMask(r: types.Boolean, g: types.Boolean, b: types.Boolean, a: types.Boolean) callconv(.c) void {
    _ = .{ r, g, b, a };
}

pub fn glPixelStorei(pname: types.Enum, param: types.Int) callconv(.c) void {
    _ = .{ pname, param };
}

pub fn glPolygonOffset(factor: types.Float, units: types.Float) callconv(.c) void {
    _ = .{ factor, units };
}

pub fn glLineWidth(width: types.Float) callconv(.c) void {
    _ = width;
}

pub fn glFinish() callconv(.c) void {}

pub fn glFlush() callconv(.c) void {}

// -------------------------------------------------------------------------
// The commands: buffers, vertex arrays and attributes
// -------------------------------------------------------------------------

pub fn glGenBuffers(n: types.Sizei, out: [*]types.Uint) callconv(.c) void {
    hand(n, out);
    note("genBuffers {d} -> {d}", .{ n, out[0] });
}

pub fn glDeleteBuffers(n: types.Sizei, names: [*]const types.Uint) callconv(.c) void {
    for (0..@intCast(n)) |i| {
        if (names[i] < buffers.len) buffers[names[i]] = .{};
    }
}

pub fn glBindBuffer(target: types.Enum, buffer: types.Uint) callconv(.c) void {
    note("bindBuffer {s} {d}", .{ targetName(target), buffer });
    switch (target) {
        c.array_buffer => state.array_buffer = buffer,
        c.element_array_buffer => state.element_buffer = buffer,
        else => {},
    }
}

pub fn glBufferData(
    target: types.Enum,
    size: types.Sizeiptr,
    data: ?*const anyopaque,
    usage: types.Enum,
) callconv(.c) void {
    _ = usage;
    const name = bound(target);
    if (name == 0 or name >= buffers.len) return raise(c.invalid_operation);

    const bytes = allocate(@intCast(size));
    if (data) |source| @memcpy(bytes, @as([*]const u8, @ptrCast(source))[0..bytes.len]);
    buffers[name] = .{ .data = bytes };
    state.stats.uploaded += bytes.len;
    note("bufferData {d} bytes into {d}", .{ size, name });
}

pub fn glBufferSubData(
    target: types.Enum,
    offset: types.Intptr,
    size: types.Sizeiptr,
    data: ?*const anyopaque,
) callconv(.c) void {
    const name = bound(target);
    if (name == 0 or name >= buffers.len) return raise(c.invalid_operation);

    const into = buffers[name].data;
    const at: usize = @intCast(offset);
    const len: usize = @intCast(size);
    if (at + len > into.len) return raise(c.invalid_value);
    if (data) |source| @memcpy(into[at..][0..len], @as([*]const u8, @ptrCast(source))[0..len]);
    state.stats.uploaded += len;
}

pub fn glGenVertexArrays(n: types.Sizei, out: [*]types.Uint) callconv(.c) void {
    hand(n, out);
    note("genVertexArrays {d} -> {d}", .{ n, out[0] });
}

pub fn glDeleteVertexArrays(n: types.Sizei, names: [*]const types.Uint) callconv(.c) void {
    _ = .{ n, names };
}

pub fn glBindVertexArray(array: types.Uint) callconv(.c) void {
    note("bindVertexArray {d}", .{array});
    state.vertex_array = array;
}

pub fn glEnableVertexAttribArray(index: types.Uint) callconv(.c) void {
    if (index >= state.attributes.len) return raise(c.invalid_value);
    state.attributes[index].enabled = true;
    note("enableVertexAttribArray {d}", .{index});
}

pub fn glDisableVertexAttribArray(index: types.Uint) callconv(.c) void {
    if (index >= state.attributes.len) return raise(c.invalid_value);
    state.attributes[index].enabled = false;
}

pub fn glVertexAttribPointer(
    index: types.Uint,
    size: types.Int,
    kind: types.Enum,
    normalized: types.Boolean,
    stride: types.Sizei,
    pointer: ?*const anyopaque,
) callconv(.c) void {
    _ = normalized;
    if (index >= state.attributes.len) return raise(c.invalid_value);
    if (kind != c.float) return raise(c.invalid_enum);

    state.attributes[index] = .{
        .enabled = state.attributes[index].enabled,
        .components = @intCast(size),
        .stride = if (stride == 0) @as(usize, @intCast(size)) * 4 else @intCast(stride),
        .offset = @intFromPtr(pointer),
        .buffer = state.array_buffer,
        .divisor = state.attributes[index].divisor,
    };
    note("vertexAttribPointer {d}: {d} floats, stride {d}, offset {d}", .{
        index,
        size,
        state.attributes[index].stride,
        state.attributes[index].offset,
    });
}

pub fn glVertexAttribDivisor(index: types.Uint, divisor: types.Uint) callconv(.c) void {
    if (index >= state.attributes.len) return raise(c.invalid_value);
    state.attributes[index].divisor = divisor;
    note("vertexAttribDivisor {d} -> every {d} instance(s)", .{ index, divisor });
}

// -------------------------------------------------------------------------
// The commands: shaders, programs and uniforms
// -------------------------------------------------------------------------

pub fn glCreateShader(kind: types.Enum) callconv(.c) types.Uint {
    const name = state.next_name;
    state.next_name += 1;
    note("createShader {s} -> {d}", .{ if (kind == c.vertex_shader) "vertex" else "fragment", name });
    return name;
}

pub fn glDeleteShader(shader: types.Uint) callconv(.c) void {
    _ = shader;
}

pub fn glShaderSource(
    shader: types.Uint,
    count: types.Sizei,
    strings: [*]const [*:0]const types.Char,
    lengths: ?[*]const types.Int,
) callconv(.c) void {
    _ = .{ shader, lengths };
    if (count > 0) {
        note("shaderSource \"{s}\"", .{std.mem.sliceTo(std.mem.span(strings[0]), '\n')});
    }
}

pub fn glCompileShader(shader: types.Uint) callconv(.c) void {
    _ = shader;
}

pub fn glGetShaderiv(shader: types.Uint, pname: types.Enum, params: [*]types.Int) callconv(.c) void {
    _ = shader;
    params[0] = switch (pname) {
        c.compile_status => types.gl_true,
        c.info_log_length => 0,
        else => 0,
    };
}

pub fn glGetShaderInfoLog(
    shader: types.Uint,
    buf_size: types.Sizei,
    length: ?*types.Sizei,
    info_log: [*]types.Char,
) callconv(.c) void {
    _ = .{ shader, buf_size };
    if (length) |written| written.* = 0;
    info_log[0] = 0;
}

pub fn glCreateProgram() callconv(.c) types.Uint {
    const name = state.next_name;
    state.next_name += 1;
    note("createProgram -> {d}", .{name});
    return name;
}

pub fn glDeleteProgram(program: types.Uint) callconv(.c) void {
    _ = program;
}

pub fn glAttachShader(program: types.Uint, shader: types.Uint) callconv(.c) void {
    _ = .{ program, shader };
}

pub fn glDetachShader(program: types.Uint, shader: types.Uint) callconv(.c) void {
    _ = .{ program, shader };
}

pub fn glLinkProgram(program: types.Uint) callconv(.c) void {
    note("linkProgram {d}", .{program});
}

pub fn glValidateProgram(program: types.Uint) callconv(.c) void {
    _ = program;
}

pub fn glGetProgramiv(program: types.Uint, pname: types.Enum, params: [*]types.Int) callconv(.c) void {
    _ = program;
    params[0] = switch (pname) {
        c.link_status, c.validate_status => types.gl_true,
        c.active_uniforms => 2,
        c.active_attributes => 5,
        else => 0,
    };
}

pub fn glGetProgramInfoLog(
    program: types.Uint,
    buf_size: types.Sizei,
    length: ?*types.Sizei,
    info_log: [*]types.Char,
) callconv(.c) void {
    _ = .{ program, buf_size };
    if (length) |written| written.* = 0;
    info_log[0] = 0;
}

pub fn glUseProgram(program: types.Uint) callconv(.c) void {
    note("useProgram {d}", .{program});
    state.program = program;
}

pub fn glBindAttribLocation(program: types.Uint, index: types.Uint, name: [*:0]const types.Char) callconv(.c) void {
    _ = .{ program, index, name };
}

/// The two uniforms this pipeline has, and nothing else: 0 is the matrix, 1
/// is the tint. A real driver looks the name up in the linked program.
pub fn glGetUniformLocation(program: types.Uint, name: [*:0]const types.Char) callconv(.c) types.Int {
    _ = program;
    const wanted = std.mem.span(name);
    if (std.mem.eql(u8, wanted, "mvp")) return 0;
    if (std.mem.eql(u8, wanted, "tint")) return 1;
    return -1;
}

pub fn glGetAttribLocation(program: types.Uint, name: [*:0]const types.Char) callconv(.c) types.Int {
    _ = program;
    const wanted = std.mem.span(name);
    const known = [_][]const u8{ "position", "colour", "uv", "instance", "instance_colour" };
    for (known, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate, wanted)) return @intCast(index);
    }
    return -1;
}

pub fn glUniformMatrix4fv(
    location: types.Int,
    count: types.Sizei,
    transpose: types.Boolean,
    value: [*]const types.Float,
) callconv(.c) void {
    if (location != 0 or count < 1) return;
    if (types.isTrue(transpose)) return raise(c.invalid_value);
    for (0..16) |i| state.mvp[i] = value[i];
}

pub fn glUniform4f(
    location: types.Int,
    v0: types.Float,
    v1: types.Float,
    v2: types.Float,
    v3: types.Float,
) callconv(.c) void {
    if (location != 1) return;
    state.tint = .{ v0, v1, v2, v3 };
}

pub fn glUniform1i(location: types.Int, v0: types.Int) callconv(.c) void {
    _ = .{ location, v0 };
}

pub fn glUniform1f(location: types.Int, v0: types.Float) callconv(.c) void {
    _ = .{ location, v0 };
}

// -------------------------------------------------------------------------
// The commands: textures
// -------------------------------------------------------------------------

pub fn glGenTextures(n: types.Sizei, out: [*]types.Uint) callconv(.c) void {
    hand(n, out);
    note("genTextures {d} -> {d}", .{ n, out[0] });
}

pub fn glDeleteTextures(n: types.Sizei, names: [*]const types.Uint) callconv(.c) void {
    for (0..@intCast(n)) |i| {
        if (names[i] < textures.len) textures[names[i]] = .{};
    }
}

pub fn glBindTexture(target: types.Enum, texture: types.Uint) callconv(.c) void {
    if (target != c.texture_2d) return raise(c.invalid_enum);
    note("bindTexture 2d {d}", .{texture});
    state.texture_2d = texture;
}

pub fn glActiveTexture(texture: types.Enum) callconv(.c) void {
    if (texture != c.texture0) raise(c.invalid_enum);
}

pub fn glGenerateMipmap(target: types.Enum) callconv(.c) void {
    _ = target;
}

pub fn glTexParameteri(target: types.Enum, pname: types.Enum, param: types.Int) callconv(.c) void {
    _ = .{ target, pname, param };
}

pub fn glTexParameterf(target: types.Enum, pname: types.Enum, param: types.Float) callconv(.c) void {
    _ = .{ target, pname, param };
}

/// Only `rgba` bytes, and only the base level: this is a texture unit with
/// nearest filtering and repeat wrapping soldered on.
pub fn glTexImage2D(
    target: types.Enum,
    level: types.Int,
    internal_format: types.Int,
    width: types.Sizei,
    height: types.Sizei,
    border: types.Int,
    format: types.Enum,
    kind: types.Enum,
    pixels: ?*const anyopaque,
) callconv(.c) void {
    _ = .{ target, internal_format, border };
    if (level != 0) return;
    if (format != c.rgba or kind != c.unsigned_byte) return raise(c.invalid_enum);
    if (state.texture_2d == 0 or state.texture_2d >= textures.len) return raise(c.invalid_operation);

    const size: usize = @intCast(width * height * 4);
    const store = allocate(size);
    if (pixels) |source| @memcpy(store, @as([*]const u8, @ptrCast(source))[0..size]);
    textures[state.texture_2d] = .{
        .width = @intCast(width),
        .height = @intCast(height),
        .pixels = store,
    };
    state.stats.uploaded += size;
    note("texImage2D {d}x{d} rgba8", .{ width, height });
}

// -------------------------------------------------------------------------
// The commands: drawing and reading back
// -------------------------------------------------------------------------

pub fn glDrawArrays(mode: types.Enum, first: types.Int, count: types.Sizei) callconv(.c) void {
    note("drawArrays {d} vertices", .{count});
    draw(mode, @intCast(first), @intCast(count), null, 0, 1);
}

pub fn glDrawArraysInstanced(
    mode: types.Enum,
    first: types.Int,
    count: types.Sizei,
    instances: types.Sizei,
) callconv(.c) void {
    note("drawArraysInstanced {d} vertices x {d} instances", .{ count, instances });
    draw(mode, @intCast(first), @intCast(count), null, 0, @intCast(instances));
}

pub fn glDrawElements(
    mode: types.Enum,
    count: types.Sizei,
    kind: types.Enum,
    indices: ?*const anyopaque,
) callconv(.c) void {
    note("drawElements {d} indices", .{count});
    draw(mode, @intFromPtr(indices), @intCast(count), elementBuffer(), kind, 1);
}

pub fn glDrawElementsInstanced(
    mode: types.Enum,
    count: types.Sizei,
    kind: types.Enum,
    indices: ?*const anyopaque,
    instances: types.Sizei,
) callconv(.c) void {
    note("drawElementsInstanced {d} indices x {d} instances", .{ count, instances });
    draw(mode, @intFromPtr(indices), @intCast(count), elementBuffer(), kind, @intCast(instances));
}

/// Straight out of the colour buffer. `rgba` bytes only, and rows from the
/// bottom up, which is where GL's origin is.
pub fn glReadPixels(
    x: types.Int,
    y: types.Int,
    width: types.Sizei,
    height: types.Sizei,
    format: types.Enum,
    kind: types.Enum,
    pixels: ?*anyopaque,
) callconv(.c) void {
    if (format != c.rgba or kind != c.unsigned_byte) return raise(c.invalid_enum);
    const into: [*]u8 = @ptrCast(pixels orelse return raise(c.invalid_value));

    for (0..@intCast(height)) |row| {
        for (0..@intCast(width)) |column| {
            const source_x = @as(usize, @intCast(x)) + column;
            const source_y = @as(usize, @intCast(y)) + row;
            const to = (row * @as(usize, @intCast(width)) + column) * 4;
            if (source_x >= state.width or source_y >= state.height) {
                into[to..][0..4].* = .{ 0, 0, 0, 0 };
            } else {
                into[to..][0..4].* = colour_buffer[(source_y * state.width + source_x) * 4 ..][0..4].*;
            }
        }
    }
}

pub fn glDebugMessageCallback(callback: ?types.DebugProc, user: ?*const anyopaque) callconv(.c) void {
    _ = user;
    state.debug_callback = callback;
    note("debugMessageCallback installed", .{});
}

pub fn glDebugMessageControl(
    source: types.Enum,
    kind: types.Enum,
    severity: types.Enum,
    count: types.Sizei,
    ids: ?[*]const types.Uint,
    enabled: types.Boolean,
) callconv(.c) void {
    _ = .{ source, kind, severity, count, ids, enabled };
}

pub fn glObjectLabel(
    identifier: types.Enum,
    name: types.Uint,
    length: types.Sizei,
    label: ?[*]const types.Char,
) callconv(.c) void {
    _ = .{ identifier, name };
    if (label) |text| note("objectLabel \"{s}\"", .{text[0..@intCast(length)]});
}

// -------------------------------------------------------------------------
// The rasteriser
// -------------------------------------------------------------------------

const Vertex = struct {
    clip: [4]f32,
    colour: [4]f32,
    uv: [2]f32,
};

fn draw(
    mode: types.Enum,
    first: usize,
    count: usize,
    indices: ?[]const u8,
    index_type: types.Enum,
    instances: usize,
) void {
    if (state.program == 0) return raise(c.invalid_operation);
    if (count < 3) return;

    state.stats.draw_calls += 1;
    state.stats.instances += instances;

    for (0..instances) |instance| {
        var triangle: usize = 0;
        while (triangle + 3 <= count) : (triangle += 1) {
            const corners: [3]usize = switch (mode) {
                c.triangles => .{ triangle, triangle + 1, triangle + 2 },
                c.triangle_strip => if (triangle % 2 == 0)
                    .{ triangle, triangle + 1, triangle + 2 }
                else
                    .{ triangle + 1, triangle, triangle + 2 },
                c.triangle_fan => .{ 0, triangle + 1, triangle + 2 },
                else => return raise(c.invalid_enum),
            };

            var vertices: [3]Vertex = undefined;
            for (&vertices, corners) |*vertex, corner| {
                const element = if (indices) |list|
                    readIndex(list, first, index_type, corner)
                else
                    first + corner;
                vertex.* = shade(element, instance);
            }
            rasterise(vertices[0], vertices[1], vertices[2]);

            if (mode == c.triangles) triangle += 2;
        }
    }
}

/// The vertex stage: fetch, transform, and work out one colour.
fn shade(element: usize, instance: usize) Vertex {
    var position: [4]f32 = .{ 0, 0, 0, 1 };
    _ = fetch(0, element, instance, &position);

    var colour: [4]f32 = .{ 1, 1, 1, 1 };
    _ = fetch(1, element, instance, &colour);

    var uv: [4]f32 = .{ 0, 0, 0, 0 };
    _ = fetch(2, element, instance, &uv);

    var placement: [4]f32 = .{ 0, 0, 0, 1 };
    _ = fetch(3, element, instance, &placement);

    var instance_colour: [4]f32 = .{ 1, 1, 1, 1 };
    _ = fetch(4, element, instance, &instance_colour);

    const local: [4]f32 = .{
        position[0] * placement[3] + placement[0],
        position[1] * placement[3] + placement[1],
        position[2] * placement[3] + placement[2],
        1,
    };

    var clip: [4]f32 = .{ 0, 0, 0, 0 };
    for (0..4) |row| {
        for (0..4) |column| clip[row] += state.mvp[column * 4 + row] * local[column];
    }

    var out: [4]f32 = undefined;
    for (0..4) |i| out[i] = colour[i] * instance_colour[i] * state.tint[i];

    return .{ .clip = clip, .colour = out, .uv = .{ uv[0], uv[1] } };
}

/// One attribute of one vertex, out of whichever buffer it was pointed at.
fn fetch(index_of: usize, element: usize, instance: usize, out: *[4]f32) bool {
    const attribute = state.attributes[index_of];
    if (!attribute.enabled) return false;
    if (attribute.buffer == 0 or attribute.buffer >= buffers.len) return false;

    const data = buffers[attribute.buffer].data;
    const step = if (attribute.divisor == 0) element else instance / attribute.divisor;
    const at = attribute.offset + step * attribute.stride;
    if (at + attribute.components * 4 > data.len) return false;

    for (0..attribute.components) |i| {
        out[i] = @bitCast(std.mem.readInt(u32, data[at + i * 4 ..][0..4], builtin.cpu.arch.endian()));
    }
    return true;
}

fn rasterise(first: Vertex, second: Vertex, third: Vertex) void {
    // No clipper: a triangle with a vertex behind the eye is dropped whole
    // rather than cut in two.
    if (first.clip[3] <= 0 or second.clip[3] <= 0 or third.clip[3] <= 0) return;

    var corners = [3]Vertex{ first, second, third };
    var screen = [3][3]f32{ toScreen(first.clip), toScreen(second.clip), toScreen(third.clip) };
    var area = edge(screen[0], screen[1], screen[2]);
    if (area == 0) return;

    if (state.cull_face) {
        const front_facing = if (state.front_face == c.ccw) area > 0 else area < 0;
        const drop = switch (state.cull_mode) {
            c.back => !front_facing,
            c.front => front_facing,
            else => true,
        };
        if (drop) return;
    }

    // Whichever way round it arrived, rasterise it counter-clockwise. That
    // makes the winding one thing rather than two, which is what lets
    // `covers` decide a shared edge with a single rule.
    if (area < 0) {
        std.mem.swap(Vertex, &corners[1], &corners[2]);
        std.mem.swap([3]f32, &screen[1], &screen[2]);
        area = -area;
    }

    state.stats.triangles += 1;

    var min_x = @min(screen[0][0], @min(screen[1][0], screen[2][0]));
    var max_x = @max(screen[0][0], @max(screen[1][0], screen[2][0]));
    var min_y = @min(screen[0][1], @min(screen[1][1], screen[2][1]));
    var max_y = @max(screen[0][1], @max(screen[1][1], screen[2][1]));

    const box = clipBox();
    min_x = @max(min_x, @as(f32, @floatFromInt(box[0])));
    min_y = @max(min_y, @as(f32, @floatFromInt(box[1])));
    max_x = @min(max_x, @as(f32, @floatFromInt(box[2])));
    max_y = @min(max_y, @as(f32, @floatFromInt(box[3])));
    if (min_x > max_x or min_y > max_y) return;

    var y: usize = @intFromFloat(@floor(@max(min_y, 0)));
    const y_end: usize = @intFromFloat(@floor(@max(max_y, 0)));
    while (y <= y_end and y < state.height) : (y += 1) {
        var x: usize = @intFromFloat(@floor(@max(min_x, 0)));
        const x_end: usize = @intFromFloat(@floor(@max(max_x, 0)));
        while (x <= x_end and x < state.width) : (x += 1) {
            // The sample is the middle of the pixel, not its corner.
            const point: [3]f32 = .{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5, 0 };

            const e0 = edge(screen[1], screen[2], point);
            const e1 = edge(screen[2], screen[0], point);
            const e2 = edge(screen[0], screen[1], point);
            if (!covers(e0, screen[1], screen[2])) continue;
            if (!covers(e1, screen[2], screen[0])) continue;
            if (!covers(e2, screen[0], screen[1])) continue;

            const w0 = e0 / area;
            const w1 = e1 / area;
            const w2 = e2 / area;

            const z = w0 * screen[0][2] + w1 * screen[1][2] + w2 * screen[2][2];
            const slot = y * state.width + x;
            if (state.depth_test and z >= depth_buffer[slot]) continue;

            var colour: [4]f32 = undefined;
            for (0..4) |i| {
                colour[i] = w0 * corners[0].colour[i] + w1 * corners[1].colour[i] + w2 * corners[2].colour[i];
            }

            const u = w0 * corners[0].uv[0] + w1 * corners[1].uv[0] + w2 * corners[2].uv[0];
            const v = w0 * corners[0].uv[1] + w1 * corners[1].uv[1] + w2 * corners[2].uv[1];
            const texel = sample(u, v);
            for (0..4) |i| colour[i] *= texel[i];

            if (state.depth_test) depth_buffer[slot] = z;
            write(slot, colour);
            state.stats.pixels += 1;
        }
    }
}

fn toScreen(clip: [4]f32) [3]f32 {
    const ndc: [3]f32 = .{ clip[0] / clip[3], clip[1] / clip[3], clip[2] / clip[3] };
    const x = @as(f32, @floatFromInt(state.viewport[0])) + (ndc[0] * 0.5 + 0.5) * @as(f32, @floatFromInt(state.viewport[2]));
    const y = @as(f32, @floatFromInt(state.viewport[1])) + (ndc[1] * 0.5 + 0.5) * @as(f32, @floatFromInt(state.viewport[3]));
    return .{ x, y, ndc[2] * 0.5 + 0.5 };
}

fn edge(a: [3]f32, b: [3]f32, point: [3]f32) f32 {
    return (b[0] - a[0]) * (point[1] - a[1]) - (b[1] - a[1]) * (point[0] - a[0]);
}

/// Whether a pixel on the wrong side of nothing at all belongs to this
/// triangle: the top-left rule.
///
/// A pixel centre that lands exactly on an edge is inside both of the
/// triangles that share it, and drawing it twice is visible the moment
/// anything is blended - a quad gets a brighter line down its diagonal.
/// The cure is to give the pixel to one of them by a rule that flips with
/// the edge's direction, and since the two triangles walk their shared edge
/// in opposite directions, exactly one of them keeps it.
///
/// This is written for the winding `rasterise` normalises to, which is
/// counter-clockwise with y upwards: an edge is owned if it runs downwards,
/// or exactly horizontally to the left.
fn covers(weight: f32, from: [3]f32, to: [3]f32) bool {
    if (weight > 0) return true;
    if (weight < 0) return false;

    const dx = to[0] - from[0];
    const dy = to[1] - from[1];
    return dy < 0 or (dy == 0 and dx < 0);
}

/// The viewport, and the scissor box if there is one.
fn clipBox() [4]i64 {
    var box: [4]i64 = .{
        state.viewport[0],
        state.viewport[1],
        @as(i64, state.viewport[0]) + state.viewport[2] - 1,
        @as(i64, state.viewport[1]) + state.viewport[3] - 1,
    };
    if (state.scissor_test) {
        box[0] = @max(box[0], state.scissor[0]);
        box[1] = @max(box[1], state.scissor[1]);
        box[2] = @min(box[2], @as(i64, state.scissor[0]) + state.scissor[2] - 1);
        box[3] = @min(box[3], @as(i64, state.scissor[1]) + state.scissor[3] - 1);
    }
    return box;
}

fn sample(u: f32, v: f32) [4]f32 {
    const texture = textures[if (state.texture_2d < textures.len) state.texture_2d else 0];
    if (texture.width == 0 or texture.height == 0) return .{ 1, 1, 1, 1 };

    // Nearest, and repeat, because that is all there is.
    const x = wrap(u, texture.width);
    const y = wrap(v, texture.height);
    const at = (y * texture.width + x) * 4;
    var out: [4]f32 = undefined;
    for (0..4) |i| out[i] = @as(f32, @floatFromInt(texture.pixels[at + i])) / 255;
    return out;
}

fn wrap(coordinate: f32, size: usize) usize {
    const scaled = coordinate * @as(f32, @floatFromInt(size));
    const floored = @floor(scaled);
    const modulo = @mod(floored, @as(f32, @floatFromInt(size)));
    return @min(@as(usize, @intFromFloat(@max(modulo, 0))), size - 1);
}

fn write(slot: usize, source: [4]f32) void {
    var final = source;
    if (state.blend) {
        const dst = unpack(colour_buffer[slot * 4 ..][0..4].*);
        const factors = blendFactors(source[3]);
        for (0..4) |i| final[i] = source[i] * factors[0] + dst[i] * factors[1];
    }
    colour_buffer[slot * 4 ..][0..4].* = pack(final);
}

fn blendFactors(alpha: f32) [2]f32 {
    return .{ blendFactor(state.blend_src, alpha), blendFactor(state.blend_dst, alpha) };
}

fn blendFactor(which: types.Enum, alpha: f32) f32 {
    return switch (which) {
        c.one => 1,
        c.zero => 0,
        c.src_alpha => alpha,
        c.one_minus_src_alpha => 1 - alpha,
        else => 1,
    };
}

fn pack(colour: [4]f32) [4]u8 {
    var out: [4]u8 = undefined;
    for (&out, colour) |*byte, channel| {
        byte.* = @intFromFloat(@round(std.math.clamp(channel, 0, 1) * 255));
    }
    return out;
}

fn unpack(bytes: [4]u8) [4]f32 {
    var out: [4]f32 = undefined;
    for (&out, bytes) |*channel, byte| channel.* = @as(f32, @floatFromInt(byte)) / 255;
    return out;
}

// -------------------------------------------------------------------------
// Odds and ends
// -------------------------------------------------------------------------

fn hand(n: types.Sizei, out: [*]types.Uint) void {
    for (0..@intCast(n)) |i| {
        out[i] = state.next_name;
        state.next_name += 1;
    }
}

fn bound(target: types.Enum) u32 {
    return switch (target) {
        c.array_buffer => state.array_buffer,
        c.element_array_buffer => state.element_buffer,
        else => 0,
    };
}

fn elementBuffer() ?[]const u8 {
    if (state.element_buffer == 0 or state.element_buffer >= buffers.len) return null;
    return buffers[state.element_buffer].data;
}

fn readIndex(list: []const u8, offset: usize, kind: types.Enum, at: usize) usize {
    return switch (kind) {
        c.unsigned_byte => list[offset + at],
        c.unsigned_short => std.mem.readInt(u16, list[offset + at * 2 ..][0..2], builtin.cpu.arch.endian()),
        c.unsigned_int => std.mem.readInt(u32, list[offset + at * 4 ..][0..4], builtin.cpu.arch.endian()),
        else => 0,
    };
}

fn targetName(target: types.Enum) []const u8 {
    return switch (target) {
        c.array_buffer => "array",
        c.element_array_buffer => "element_array",
        c.uniform_buffer => "uniform",
        else => "other",
    };
}

var flat: [1024]u8 = undefined;
var flat_len: ?usize = null;

/// `getString(extensions)` wants one string with spaces in it, and
/// `getStringi` wants them one at a time. Drivers keep both; so does this.
fn flatExtensions() [*:0]const types.Char {
    if (flat_len == null) {
        var at: usize = 0;
        for (reported_extensions, 0..) |name, i| {
            if (i > 0 and at < flat.len) {
                flat[at] = ' ';
                at += 1;
            }
            const room = @min(name.len, flat.len - at - 1);
            @memcpy(flat[at..][0..room], name[0..room]);
            at += room;
        }
        flat[at] = 0;
        flat_len = at;
    }
    return @ptrCast(&flat);
}

// -------------------------------------------------------------------------
// Tests
//
// The examples print pictures, and a picture is only worth printing if the
// thing that drew it is right. These check the parts of GL's behaviour the
// examples lean on: where the origin is, what the scissor box covers, which
// triangle wins the depth test, which one culling drops, that blending
// happens once a pixel and not twice, and that an instanced draw draws every
// instance.
// -------------------------------------------------------------------------

const testing = std.testing;

fn pixelAt(x: usize, y: usize) [4]u8 {
    return colour_buffer[(y * state.width + x) * 4 ..][0..4].*;
}

/// A buffer of floats, bound to `array_buffer`.
fn upload(values: []const f32) types.Uint {
    var name: [1]types.Uint = .{0};
    glGenBuffers(1, &name);
    glBindBuffer(c.array_buffer, name[0]);
    glBufferData(c.array_buffer, @intCast(values.len * @sizeOf(f32)), values.ptr, c.static_draw);
    return name[0];
}

/// Position and colour, interleaved seven floats a vertex, which is what most
/// of these tests want.
fn describeVertices() void {
    glVertexAttribPointer(0, 3, c.float, types.gl_false, 7 * @sizeOf(f32), null);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 4, c.float, types.gl_false, 7 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    glEnableVertexAttribArray(1);
    glUseProgram(glCreateProgram());
}

/// Two triangles covering the whole of clip space, in one strip.
const full_screen = [_]f32{
    -1, -1, 0, 1, 1, 1, 1,
    1,  -1, 0, 1, 1, 1, 1,
    -1, 1,  0, 1, 1, 1, 1,
    1,  1,  0, 1, 1, 1, 1,
};

test "a fresh context is black, and a clear fills it" {
    makeContext(8, 4);
    try testing.expectEqual([4]u8{ 0, 0, 0, 0 }, pixelAt(0, 0));

    glClearColor(1, 0, 0, 1);
    glClear(c.color_buffer_bit);
    for (0..4) |y| {
        for (0..8) |x| try testing.expectEqual([4]u8{ 255, 0, 0, 255 }, pixelAt(x, y));
    }
}

test "the scissor box holds for a clear as well as for a draw" {
    makeContext(8, 4);
    glClearColor(0, 0, 0, 1);
    glClear(c.color_buffer_bit);

    // The top half only, counting from the bottom, because that is where GL
    // counts from.
    glEnable(c.scissor_test);
    glScissor(0, 2, 8, 2);
    glClearColor(1, 1, 1, 1);
    glClear(c.color_buffer_bit);
    glDisable(c.scissor_test);

    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, pixelAt(4, 0));
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, pixelAt(4, 1));
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, pixelAt(4, 2));
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, pixelAt(4, 3));

    // And `readPixels` hands the rows back in that order too: row zero is the
    // bottom one, which is why `writeImage` walks them backwards.
    var pixels: [8 * 4 * 4]u8 = undefined;
    glReadPixels(0, 0, 8, 4, c.rgba, c.unsigned_byte, &pixels);
    try testing.expectEqual(@as(u8, 0), pixels[0]);
    try testing.expectEqual(@as(u8, 255), pixels[(2 * 8) * 4]);
}

test "a triangle covering clip space covers the viewport" {
    makeContext(16, 8);
    glClearColor(0, 0, 0, 1);
    glClear(c.color_buffer_bit);

    _ = upload(&full_screen);
    describeVertices();
    glDrawArrays(c.triangle_strip, 0, 4);

    for (0..8) |y| {
        for (0..16) |x| try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, pixelAt(x, y));
    }
    try testing.expectEqual(@as(usize, 2), stats().triangles);
    try testing.expectEqual(@as(usize, 16 * 8), stats().pixels);
}

test "the depth test keeps the nearer triangle, whichever order they arrive in" {
    // Two full-screen quads: a red one at z = 0.5 and a blue one at z = -0.5,
    // which is nearer. The nearer one has to win both ways round.
    const near = [_]f32{
        -1, -1, -0.5, 0, 0, 1, 1,
        1,  -1, -0.5, 0, 0, 1, 1,
        -1, 1,  -0.5, 0, 0, 1, 1,
        1,  1,  -0.5, 0, 0, 1, 1,
    };
    const far = [_]f32{
        -1, -1, 0.5, 1, 0, 0, 1,
        1,  -1, 0.5, 1, 0, 0, 1,
        -1, 1,  0.5, 1, 0, 0, 1,
        1,  1,  0.5, 1, 0, 0, 1,
    };

    for ([_]bool{ true, false }) |near_first| {
        makeContext(4, 4);
        glClearColor(0, 0, 0, 1);
        glClearDepth(1);
        glClear(c.color_buffer_bit | c.depth_buffer_bit);
        glEnable(c.depth_test);

        const first = upload(if (near_first) &near else &far);
        const second = upload(if (near_first) &far else &near);

        glBindBuffer(c.array_buffer, first);
        describeVertices();
        glDrawArrays(c.triangle_strip, 0, 4);

        glBindBuffer(c.array_buffer, second);
        describeVertices();
        glDrawArrays(c.triangle_strip, 0, 4);

        try testing.expectEqual([4]u8{ 0, 0, 255, 255 }, pixelAt(2, 2));
    }

    // And with the test off, the last one drawn wins instead - which is the
    // second picture the cube example prints.
    makeContext(4, 4);
    glClearColor(0, 0, 0, 1);
    glClear(c.color_buffer_bit | c.depth_buffer_bit);
    _ = upload(&near);
    describeVertices();
    glDrawArrays(c.triangle_strip, 0, 4);
    _ = upload(&far);
    describeVertices();
    glDrawArrays(c.triangle_strip, 0, 4);
    try testing.expectEqual([4]u8{ 255, 0, 0, 255 }, pixelAt(2, 2));
}

test "culling drops the faces wound the other way" {
    // The same triangle, counter-clockwise and clockwise.
    const forwards = [_]f32{
        -1, -1, 0, 1, 1, 1, 1,
        1,  -1, 0, 1, 1, 1, 1,
        0,  1,  0, 1, 1, 1, 1,
    };
    const backwards = [_]f32{
        1,  -1, 0, 1, 1, 1, 1,
        -1, -1, 0, 1, 1, 1, 1,
        0,  1,  0, 1, 1, 1, 1,
    };

    makeContext(8, 8);
    glEnable(c.cull_face);
    glCullFace(c.back);
    glFrontFace(c.ccw);

    _ = upload(&forwards);
    describeVertices();
    glDrawArrays(c.triangles, 0, 3);
    try testing.expectEqual(@as(usize, 1), stats().triangles);

    _ = upload(&backwards);
    describeVertices();
    glDrawArrays(c.triangles, 0, 3);
    try testing.expectEqual(@as(usize, 1), stats().triangles);

    // Turn culling off and the second one is rasterised after all.
    glDisable(c.cull_face);
    glDrawArrays(c.triangles, 0, 3);
    try testing.expectEqual(@as(usize, 2), stats().triangles);
}

test "blending happens once a pixel, including along a shared edge" {
    makeContext(16, 8);
    glClearColor(0, 0, 0, 1);
    glClear(c.color_buffer_bit);

    glEnable(c.blend);
    glBlendFunc(c.src_alpha, c.one_minus_src_alpha);

    // A white quad at half alpha over black: every pixel should come out the
    // same grey. The two triangles share the diagonal, so a pixel on it would
    // be blended twice and come out brighter - which is the bug this is here
    // to catch.
    const half = [_]f32{
        -1, -1, 0, 1, 1, 1, 0.5,
        1,  -1, 0, 1, 1, 1, 0.5,
        -1, 1,  0, 1, 1, 1, 0.5,
        1,  1,  0, 1, 1, 1, 0.5,
    };
    _ = upload(&half);
    describeVertices();
    glDrawArrays(c.triangle_strip, 0, 4);

    const expected = pixelAt(0, 0);
    try testing.expectEqual(@as(u8, 128), expected[0]);
    for (0..8) |y| {
        for (0..16) |x| try testing.expectEqual(expected, pixelAt(x, y));
    }

    // Again on a square framebuffer, where the diagonal runs from corner to
    // corner and lands exactly on pixel centres - the case the rectangle
    // above misses, and the only one where the tie is real.
    makeContext(8, 8);
    glClearColor(0, 0, 0, 1);
    glClear(c.color_buffer_bit);
    glEnable(c.blend);
    glBlendFunc(c.src_alpha, c.one_minus_src_alpha);
    _ = upload(&half);
    describeVertices();
    glDrawArrays(c.triangle_strip, 0, 4);

    for (0..8) |y| {
        for (0..8) |x| try testing.expectEqual(expected, pixelAt(x, y));
    }

    // Sixty-four pixels for sixty-four pixels: every one covered, none of
    // them twice.
    try testing.expectEqual(@as(usize, 64), stats().pixels);
}

test "an instanced draw draws every instance, once each" {
    makeContext(24, 8);
    glClearColor(0, 0, 0, 1);
    glClear(c.color_buffer_bit);

    // A quad an eighth of clip space wide and a quarter of it tall, sitting
    // at its own origin so that the instance data is what places it.
    const quad = [_]f32{
        0,    0,   0, 1, 1, 1, 1,
        0.25, 0,   0, 1, 1, 1, 1,
        0,    0.5, 0, 1, 1, 1, 1,
        0.25, 0.5, 0, 1, 1, 1, 1,
    };
    _ = upload(&quad);
    describeVertices();

    // Three instances, each with its own offset and scale in xyzw and its own
    // colour after it.
    const placements = [_]f32{
        -0.9, -0.9, 0, 1, 1, 0, 0, 1,
        -0.2, -0.9, 0, 1, 0, 1, 0, 1,
        0.5,  -0.9, 0, 1, 0, 0, 1, 1,
    };
    _ = upload(&placements);
    glVertexAttribPointer(3, 4, c.float, types.gl_false, 8 * @sizeOf(f32), null);
    glEnableVertexAttribArray(3);
    glVertexAttribDivisor(3, 1);
    glVertexAttribPointer(4, 4, c.float, types.gl_false, 8 * @sizeOf(f32), @ptrFromInt(4 * @sizeOf(f32)));
    glEnableVertexAttribArray(4);
    glVertexAttribDivisor(4, 1);

    glDrawArraysInstanced(c.triangle_strip, 0, 4, 3);

    try testing.expectEqual(@as(usize, 1), stats().draw_calls);
    try testing.expectEqual(@as(usize, 3), stats().instances);
    try testing.expectEqual(@as(usize, 6), stats().triangles);

    // One patch of each colour, in the order the instance buffer gave them,
    // and nothing but the clear between them.
    try testing.expectEqual([4]u8{ 255, 0, 0, 255 }, pixelAt(2, 1));
    try testing.expectEqual([4]u8{ 0, 255, 0, 255 }, pixelAt(11, 1));
    try testing.expectEqual([4]u8{ 0, 0, 255, 255 }, pixelAt(19, 1));
    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, pixelAt(7, 1));
}

test "an indexed draw reads the indices it was given" {
    makeContext(8, 8);
    glClearColor(0, 0, 0, 1);
    glClear(c.color_buffer_bit);

    _ = upload(&full_screen);
    describeVertices();

    // The same four vertices as two triangles, spelled with indices.
    const indices = [_]u16{ 0, 1, 2, 2, 1, 3 };
    var name: [1]types.Uint = .{0};
    glGenBuffers(1, &name);
    glBindBuffer(c.element_array_buffer, name[0]);
    glBufferData(c.element_array_buffer, @sizeOf(@TypeOf(indices)), &indices, c.static_draw);

    glDrawElements(c.triangles, indices.len, c.unsigned_short, null);

    try testing.expectEqual(@as(usize, 2), stats().triangles);
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, pixelAt(4, 4));
}

test "a texture is sampled, and not upside down" {
    makeContext(8, 8);
    glClearColor(0, 0, 0, 1);
    glClear(c.color_buffer_bit);

    // Two rows: black underneath, white on top, as texture memory is laid out
    // from v = 0 upwards.
    const texels = [_]u8{
        0,   0,   0,   255, 0,   0,   0,   255,
        255, 255, 255, 255, 255, 255, 255, 255,
    };
    var texture: [1]types.Uint = .{0};
    glGenTextures(1, &texture);
    glBindTexture(c.texture_2d, texture[0]);
    glTexImage2D(c.texture_2d, 0, c.rgba8, 2, 2, 0, c.rgba, c.unsigned_byte, &texels);

    // A full-screen quad, sampling the middle of each row so that nothing
    // depends on how the edges wrap.
    const quad = [_]f32{
        -1, -1, 0, 1, 1, 1, 1, 0.25, 0.25,
        1,  -1, 0, 1, 1, 1, 1, 0.75, 0.25,
        -1, 1,  0, 1, 1, 1, 1, 0.25, 0.75,
        1,  1,  0, 1, 1, 1, 1, 0.75, 0.75,
    };
    _ = upload(&quad);
    glVertexAttribPointer(0, 3, c.float, types.gl_false, 9 * @sizeOf(f32), null);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 4, c.float, types.gl_false, 9 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(2, 2, c.float, types.gl_false, 9 * @sizeOf(f32), @ptrFromInt(7 * @sizeOf(f32)));
    glEnableVertexAttribArray(2);
    glUseProgram(glCreateProgram());
    glDrawArrays(c.triangle_strip, 0, 4);

    try testing.expectEqual([4]u8{ 0, 0, 0, 255 }, pixelAt(4, 1));
    try testing.expectEqual([4]u8{ 255, 255, 255, 255 }, pixelAt(4, 6));
}

test "errors queue up and come back one at a time" {
    makeContext(4, 4);
    try testing.expectEqual(c.no_error, glGetError());

    glEnable(0x1234);
    glBindTexture(c.texture_3d, 1);
    try testing.expectEqual(c.invalid_enum, glGetError());
    try testing.expectEqual(c.invalid_enum, glGetError());
    try testing.expectEqual(c.no_error, glGetError());

    // Drawing with no program bound is the one a program actually hits.
    _ = upload(&full_screen);
    glVertexAttribPointer(0, 3, c.float, types.gl_false, 7 * @sizeOf(f32), null);
    glEnableVertexAttribArray(0);
    glDrawArrays(c.triangle_strip, 0, 4);
    try testing.expectEqual(c.invalid_operation, glGetError());
    try testing.expectEqual(@as(usize, 0), stats().triangles);
}

test "a new context forgets the objects the last one made" {
    makeContext(4, 4);
    const first = upload(&full_screen);
    try testing.expect(buffers[first].data.len > 0);

    makeContext(4, 4);
    try testing.expectEqual(@as(usize, 0), buffers[first].data.len);
    try testing.expectEqual(@as(usize, 0), stats().draw_calls);
}

test "the whole thing loads through getProcAddress, like a driver" {
    makeContext(4, 4);

    const Table = struct {
        clearColor: *const fn (r: types.Float, g: types.Float, b: types.Float, a: types.Float) callconv(.c) void,
        clear: *const fn (mask: types.Bitfield) callconv(.c) void,
        getError: *const fn () callconv(.c) types.Enum,
        // Not in this driver, and so null rather than a promise.
        dispatchCompute: ?*const fn (x: types.Uint, y: types.Uint, z: types.Uint) callconv(.c) void,
    };

    var api: Table = undefined;
    const status = opengl.loader.tryLoad(&api, getProcAddress, .{});
    try testing.expect(status.ok());
    try testing.expectEqual(@as(usize, 1), status.absent);
    try testing.expectEqual(null, api.dispatchCompute);

    api.clearColor(0, 1, 0, 1);
    api.clear(c.color_buffer_bit);
    try testing.expectEqual([4]u8{ 0, 255, 0, 255 }, pixelAt(1, 1));
    try testing.expectEqual(c.no_error, api.getError());
}
