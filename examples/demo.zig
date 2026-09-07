// SPDX-License-Identifier: BSL-1.0

//! A tour of Fluxion GL. Run it with `zig build example`.
//!
//! There is no window here and no graphics card, because a demo that needed
//! one would not run on the machine that builds it. Instead this file carries
//! a driver of its own: two dozen commands that print what they were asked to
//! do, behind a `getProcAddress` that hands them out by name. Everything on
//! the other side of that function is what a program with a real context
//! does, unchanged - resolve the entry points, read the version, look for
//! extensions, build a shader, draw a triangle.
//!
//! Swap `driver.getProcAddress` for `glfwGetProcAddress` and this is a
//! program that draws.

const std = @import("std");
const Io = std.Io;

const opengl = @import("fluxion_gl");
const c = opengl.enums;
const types = opengl.types;

/// What this program calls, and nothing else.
///
/// The full `opengl.Gl` is OpenGL 3.3 core, which is the right table for a
/// program that draws a scene; a program that draws one triangle can say so,
/// and then a driver with only these commands is enough. The loader takes any
/// struct of function pointers.
const Frame = struct {
    getString: *const fn (name: types.Enum) callconv(.c) ?[*:0]const types.Char,
    getStringi: *const fn (name: types.Enum, index: types.Uint) callconv(.c) ?[*:0]const types.Char,
    getIntegerv: *const fn (pname: types.Enum, data: [*]types.Int) callconv(.c) void,
    getError: *const fn () callconv(.c) types.Enum,

    clearColor: *const fn (r: types.Float, g: types.Float, b: types.Float, a: types.Float) callconv(.c) void,
    clear: *const fn (mask: types.Bitfield) callconv(.c) void,
    viewport: *const fn (x: types.Int, y: types.Int, w: types.Sizei, h: types.Sizei) callconv(.c) void,
    enable: *const fn (capability: types.Enum) callconv(.c) void,

    genBuffers: *const fn (n: types.Sizei, buffers: [*]types.Uint) callconv(.c) void,
    bindBuffer: *const fn (target: types.Enum, buffer: types.Uint) callconv(.c) void,
    bufferData: *const fn (
        target: types.Enum,
        size: types.Sizeiptr,
        data: ?*const anyopaque,
        usage: types.Enum,
    ) callconv(.c) void,
    genVertexArrays: *const fn (n: types.Sizei, arrays: [*]types.Uint) callconv(.c) void,
    bindVertexArray: *const fn (array: types.Uint) callconv(.c) void,
    vertexAttribPointer: *const fn (
        index: types.Uint,
        size: types.Int,
        kind: types.Enum,
        normalized: types.Boolean,
        stride: types.Sizei,
        pointer: ?*const anyopaque,
    ) callconv(.c) void,
    enableVertexAttribArray: *const fn (index: types.Uint) callconv(.c) void,

    createShader: *const fn (kind: types.Enum) callconv(.c) types.Uint,
    shaderSource: *const fn (
        shader: types.Uint,
        count: types.Sizei,
        strings: [*]const [*:0]const types.Char,
        lengths: ?[*]const types.Int,
    ) callconv(.c) void,
    compileShader: *const fn (shader: types.Uint) callconv(.c) void,
    getShaderiv: *const fn (shader: types.Uint, pname: types.Enum, params: [*]types.Int) callconv(.c) void,
    createProgram: *const fn () callconv(.c) types.Uint,
    attachShader: *const fn (program: types.Uint, shader: types.Uint) callconv(.c) void,
    linkProgram: *const fn (program: types.Uint) callconv(.c) void,
    useProgram: *const fn (program: types.Uint) callconv(.c) void,
    getUniformLocation: *const fn (program: types.Uint, name: [*:0]const types.Char) callconv(.c) types.Int,
    uniform4f: *const fn (
        location: types.Int,
        v0: types.Float,
        v1: types.Float,
        v2: types.Float,
        v3: types.Float,
    ) callconv(.c) void,

    drawArrays: *const fn (mode: types.Enum, first: types.Int, count: types.Sizei) callconv(.c) void,

    /// Both of these are past the version this program requires, so both are
    /// optional - and this driver has the first and not the second.
    debugMessageCallback: ?*const fn (callback: ?types.DebugProc, user: ?*const anyopaque) callconv(.c) void,
    dispatchCompute: ?*const fn (x: types.Uint, y: types.Uint, z: types.Uint) callconv(.c) void,
};

const vertices = [_]types.Float{
    -0.6, -0.4, 0.0,
    0.6,  -0.4, 0.0,
    0.0,  0.6,  0.0,
};

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const out = &stdout.interface;

    // The driver prints what it is asked to do, and a C callback has nowhere
    // to return an error to, so it writes through a global. GL is global
    // state as well; this is the one place in the demo where that is honest.
    driver.output = out;

    // --- finding the entry points -----------------------------------------
    try out.writeAll("--- loading ---\n");

    var api: Frame = undefined;
    const status = opengl.loader.tryLoad(&api, driver.getProcAddress, .{});
    try out.print("{f}\n", .{status});
    if (!status.ok()) return error.CommandMissing;

    try out.print("asked for {s} first and {s} last, by field name alone\n", .{
        comptime opengl.loader.names(Frame)[0],
        comptime opengl.loader.names(Frame)[opengl.loader.count(Frame) - 1],
    });

    // --- what the context says it is --------------------------------------
    try out.writeAll("\n--- the context ---\n");

    const version = try opengl.Version.parse(std.mem.span(api.getString(c.version).?));
    const glsl = try opengl.Glsl.parse(std.mem.span(api.getString(c.shading_language_version).?));

    try out.print("version    {f}\n", .{version});
    try out.print("renderer   {s}\n", .{std.mem.span(api.getString(c.renderer).?)});
    try out.print("language   {f}, so shaders start with ", .{glsl});
    try glsl.writeDirective(out);

    // The version string and the language version are two different numbers,
    // and the implied one is not always what the driver reports.
    try out.print("implied    {f} from the API version alone\n", .{version.glsl().?});
    try out.print("3.3 or better? {s}\n", .{if (version.atLeast(3, 3)) "yes" else "no"});

    // --- extensions --------------------------------------------------------
    try out.writeAll("\n--- extensions ---\n");

    var total: [1]types.Int = .{0};
    api.getIntegerv(c.num_extensions, &total);

    var names: [32][]const u8 = undefined;
    var found: usize = 0;
    var index: types.Uint = 0;
    while (index < @as(types.Uint, @intCast(total[0])) and found < names.len) : (index += 1) {
        names[found] = std.mem.span(api.getStringi(c.extensions, index).?);
        found += 1;
    }
    const have: opengl.extensions.Set = .{ .names = names[0..found] };

    for (have.names) |name| try out.print("  {s}\n", .{name});
    // A name may be given with the `GL_` or without it, because half the
    // specifications write it one way and half the other.
    try out.print("KHR_debug?               {s}\n", .{if (have.has("KHR_debug")) "yes" else "no"});
    try out.print("GL_ARB_bindless_texture? {s}\n", .{if (have.has("GL_ARB_bindless_texture")) "yes" else "no"});
    if (have.missing(&.{ "GL_KHR_debug", "GL_ARB_bindless_texture" })) |absent| {
        try out.print("still wanted:            {s}\n", .{absent});
    }

    // --- the commands that may not be there --------------------------------
    try out.writeAll("\n--- optional commands ---\n");

    if (api.debugMessageCallback) |install| {
        try out.writeAll("debug output is here, so the driver can talk back:\n");
        install(onDebugMessage, null);
    } else {
        try out.writeAll("no debug output on this context\n");
    }

    if (api.dispatchCompute) |dispatch| {
        dispatch(1, 1, 1);
    } else {
        try out.writeAll("no compute shaders on this context, and the compiler knew it\n");
    }

    // --- setting up to draw -------------------------------------------------
    try out.writeAll("\n--- one triangle ---\n");

    var vao: [1]types.Uint = .{0};
    api.genVertexArrays(1, &vao);
    api.bindVertexArray(vao[0]);

    var vbo: [1]types.Uint = .{0};
    api.genBuffers(1, &vbo);
    api.bindBuffer(c.array_buffer, vbo[0]);
    api.bufferData(c.array_buffer, @sizeOf(@TypeOf(vertices)), &vertices, c.static_draw);

    // Three floats per vertex, tightly packed, starting at the beginning of
    // the buffer - which is where `offset` earns its keep, because the
    // beginning of the buffer is spelled as a pointer that is not one.
    api.vertexAttribPointer(0, 3, c.float, types.gl_false, 3 * @sizeOf(types.Float), opengl.offset(0));
    api.enableVertexAttribArray(0);

    // The shader is built around the directive the context asked for, so the
    // same source compiles on 3.3 and on 4.6 without an #ifdef.
    var source_buffer: [512]u8 = undefined;
    var source_writer: Io.Writer = .fixed(&source_buffer);
    try glsl.writeDirective(&source_writer);
    try source_writer.writeAll(vertex_shader_body);
    try source_writer.writeByte(0);
    const vertex_source: [*:0]const types.Char = @ptrCast(source_writer.buffered().ptr);

    const shader = api.createShader(c.vertex_shader);
    api.shaderSource(shader, 1, &.{vertex_source}, null);
    api.compileShader(shader);

    var compiled: [1]types.Int = .{0};
    api.getShaderiv(shader, c.compile_status, &compiled);
    try out.print("compiled?  {s}\n", .{if (types.isTrue(@intCast(compiled[0]))) "yes" else "no"});

    const program = api.createProgram();
    api.attachShader(program, shader);
    api.linkProgram(program);
    api.useProgram(program);

    const tint = api.getUniformLocation(program, "tint");
    api.uniform4f(tint, 0.9, 0.4, 0.2, 1.0);

    // --- the frame itself ----------------------------------------------------
    api.viewport(0, 0, 1280, 720);
    api.enable(c.depth_test);
    api.clearColor(0.10, 0.10, 0.12, 1.0);
    api.clear(c.color_buffer_bit | c.depth_buffer_bit);
    api.drawArrays(c.triangles, 0, 3);

    // GL keeps a queue of errors and hands them back one at a time, so this
    // drains it rather than reading one.
    var first_error: types.Enum = c.no_error;
    while (true) {
        const code = api.getError();
        if (code == c.no_error) break;
        if (first_error == c.no_error) first_error = code;
    }
    try out.print("errors?    {s}\n", .{if (first_error == c.no_error) "none" else "yes"});

    // --- the tables this library ships with ----------------------------------
    try out.writeAll("\n--- the full tables, against this driver ---\n");

    var desktop: opengl.Gl = undefined;
    var embedded: opengl.Gles = undefined;
    try out.print("OpenGL 3.3 core   {f}\n", .{desktop.tryLoad(driver.getProcAddress)});
    try out.print("OpenGL ES 2.0     {f}\n", .{embedded.tryLoad(driver.getProcAddress)});
    try out.print(
        \\
        \\A real 3.3 driver fills the first of those completely, and a phone
        \\fills the required half of the second. This driver answers for {d}
        \\commands, so both lines are mostly a list of what it has not got -
        \\including, in the second, `glClearDepthf`, which is the desktop's
        \\`glClearDepth` under another name and with another argument type.
        \\That is the sort of difference that makes ES a separate table
        \\rather than this one with fields removed.
        \\
    , .{comptime opengl.loader.count(Frame)});

    try out.flush();
}

const vertex_shader_body =
    \\in vec3 position;
    \\uniform vec4 tint;
    \\out vec4 colour;
    \\void main() {
    \\    colour = tint;
    \\    gl_Position = vec4(position, 1.0);
    \\}
    \\
;

/// What a program passes to `debugMessageCallback`. The driver calls it from
/// inside another command, on whatever thread made the call, so printing is
/// about all it may safely do.
fn onDebugMessage(
    source: types.Enum,
    kind: types.Enum,
    id: types.Uint,
    severity: types.Enum,
    length: types.Sizei,
    message: [*:0]const types.Char,
    user: ?*const anyopaque,
) callconv(.c) void {
    _ = .{ source, id, user };
    const w = driver.output orelse return;
    w.print("  [{s}] {s}\n", .{
        switch (severity) {
            c.debug_severity_high => "high",
            c.debug_severity_medium => "medium",
            c.debug_severity_low => "low",
            else => "note",
        },
        message[0..@intCast(length)],
    }) catch {};
    if (kind == c.debug_type_performance) w.writeAll("  (which is the driver being helpful)\n") catch {};
}

/// A driver that is not there: every command prints its arguments and hands
/// back something plausible.
const driver = struct {
    var output: ?*Io.Writer = null;
    var next_name: types.Uint = 1;
    var debug_callback: ?types.DebugProc = null;

    const reported_extensions = [_][:0]const u8{
        "GL_ARB_debug_output",
        "GL_KHR_debug",
        "GL_EXT_texture_filter_anisotropic",
    };

    /// A C callback has nowhere to put an error, so a failed write is
    /// dropped. In a real driver this is a log line, and the same is true.
    fn note(comptime fmt: []const u8, args: anytype) void {
        const w = output orelse return;
        w.print("  " ++ fmt ++ "\n", args) catch {};
    }

    fn getProcAddress(name: [*:0]const u8) callconv(.c) ?opengl.Proc {
        const wanted = std.mem.span(name);
        inline for (@typeInfo(driver).@"struct".decls) |decl| {
            if (comptime std.mem.startsWith(u8, decl.name, "gl")) {
                if (std.mem.eql(u8, decl.name, wanted)) return @ptrCast(&@field(driver, decl.name));
            }
        }
        return null;
    }

    pub fn glGetString(name: types.Enum) callconv(.c) ?[*:0]const types.Char {
        return switch (name) {
            c.version => "3.3.0 Fluxion Software Rasteriser 1.0",
            c.renderer => "Fluxion Reference Device",
            c.vendor => "Nobody",
            c.shading_language_version => "3.30 Fluxion",
            else => null,
        };
    }

    pub fn glGetStringi(name: types.Enum, index: types.Uint) callconv(.c) ?[*:0]const types.Char {
        if (name != c.extensions or index >= reported_extensions.len) return null;
        return reported_extensions[index].ptr;
    }

    pub fn glGetIntegerv(pname: types.Enum, data: [*]types.Int) callconv(.c) void {
        data[0] = switch (pname) {
            c.num_extensions => @intCast(reported_extensions.len),
            c.max_texture_size => 8192,
            c.max_vertex_attribs => 16,
            else => 0,
        };
    }

    pub fn glGetError() callconv(.c) types.Enum {
        return c.no_error;
    }

    pub fn glClearColor(r: types.Float, g: types.Float, b: types.Float, a: types.Float) callconv(.c) void {
        note("clearColor {d:.2} {d:.2} {d:.2} {d:.2}", .{ r, g, b, a });
    }

    pub fn glClear(mask: types.Bitfield) callconv(.c) void {
        note("clear      colour:{s} depth:{s} stencil:{s}", .{
            yesNo(mask & c.color_buffer_bit != 0),
            yesNo(mask & c.depth_buffer_bit != 0),
            yesNo(mask & c.stencil_buffer_bit != 0),
        });
    }

    pub fn glViewport(x: types.Int, y: types.Int, w: types.Sizei, h: types.Sizei) callconv(.c) void {
        note("viewport   {d},{d} {d}x{d}", .{ x, y, w, h });
    }

    pub fn glEnable(capability: types.Enum) callconv(.c) void {
        note("enable     0x{X:0>4}{s}", .{ capability, if (capability == c.depth_test) " (depth test)" else "" });
    }

    pub fn glGenBuffers(n: types.Sizei, buffers: [*]types.Uint) callconv(.c) void {
        hand(n, buffers);
        note("genBuffers {d} -> {d}", .{ n, buffers[0] });
    }

    pub fn glBindBuffer(target: types.Enum, buffer: types.Uint) callconv(.c) void {
        note("bindBuffer {s} {d}", .{ if (target == c.array_buffer) "array" else "other", buffer });
    }

    pub fn glBufferData(
        target: types.Enum,
        size: types.Sizeiptr,
        data: ?*const anyopaque,
        usage: types.Enum,
    ) callconv(.c) void {
        _ = .{ target, data };
        note("bufferData {d} bytes, {s}", .{ size, if (usage == c.static_draw) "static_draw" else "some other usage" });
    }

    pub fn glGenVertexArrays(n: types.Sizei, arrays: [*]types.Uint) callconv(.c) void {
        hand(n, arrays);
        note("genVertexArrays {d} -> {d}", .{ n, arrays[0] });
    }

    pub fn glBindVertexArray(array: types.Uint) callconv(.c) void {
        note("bindVertexArray {d}", .{array});
    }

    pub fn glVertexAttribPointer(
        index: types.Uint,
        size: types.Int,
        kind: types.Enum,
        normalized: types.Boolean,
        stride: types.Sizei,
        pointer: ?*const anyopaque,
    ) callconv(.c) void {
        note("vertexAttribPointer {d}: {d} x {s}{s}, stride {d}, offset {d}", .{
            index,
            size,
            if (kind == c.float) "float" else "something else",
            if (types.isTrue(normalized)) ", normalised" else "",
            stride,
            @intFromPtr(pointer),
        });
    }

    pub fn glEnableVertexAttribArray(index: types.Uint) callconv(.c) void {
        note("enableVertexAttribArray {d}", .{index});
    }

    pub fn glCreateShader(kind: types.Enum) callconv(.c) types.Uint {
        const name = next_name;
        next_name += 1;
        note("createShader {s} -> {d}", .{ if (kind == c.vertex_shader) "vertex" else "fragment", name });
        return name;
    }

    pub fn glShaderSource(
        shader: types.Uint,
        count: types.Sizei,
        strings: [*]const [*:0]const types.Char,
        lengths: ?[*]const types.Int,
    ) callconv(.c) void {
        _ = lengths;
        const first_line = std.mem.sliceTo(std.mem.span(strings[0]), '\n');
        note("shaderSource {d}: {d} string, starting \"{s}\"", .{ shader, count, first_line });
    }

    pub fn glCompileShader(shader: types.Uint) callconv(.c) void {
        note("compileShader {d}", .{shader});
    }

    pub fn glGetShaderiv(shader: types.Uint, pname: types.Enum, params: [*]types.Int) callconv(.c) void {
        _ = shader;
        params[0] = if (pname == c.compile_status) types.gl_true else 0;
    }

    pub fn glCreateProgram() callconv(.c) types.Uint {
        const name = next_name;
        next_name += 1;
        note("createProgram -> {d}", .{name});
        return name;
    }

    pub fn glAttachShader(program: types.Uint, shader: types.Uint) callconv(.c) void {
        note("attachShader {d} <- {d}", .{ program, shader });
    }

    pub fn glLinkProgram(program: types.Uint) callconv(.c) void {
        note("linkProgram {d}", .{program});
    }

    pub fn glUseProgram(program: types.Uint) callconv(.c) void {
        note("useProgram {d}", .{program});
    }

    pub fn glGetUniformLocation(program: types.Uint, name: [*:0]const types.Char) callconv(.c) types.Int {
        _ = program;
        note("getUniformLocation \"{s}\" -> 0", .{std.mem.span(name)});
        return 0;
    }

    pub fn glUniform4f(
        location: types.Int,
        v0: types.Float,
        v1: types.Float,
        v2: types.Float,
        v3: types.Float,
    ) callconv(.c) void {
        note("uniform4f  {d}: {d:.2} {d:.2} {d:.2} {d:.2}", .{ location, v0, v1, v2, v3 });
    }

    pub fn glDrawArrays(mode: types.Enum, first: types.Int, count: types.Sizei) callconv(.c) void {
        note("drawArrays {s}, {d} vertices from {d}", .{
            if (mode == c.triangles) "triangles" else "some other mode",
            count,
            first,
        });

        // A real driver notices things during a draw. This one notices one
        // thing, and only if somebody asked to be told.
        if (debug_callback) |callback| {
            const message = "vertex shader recompiled for this state, which costs a frame";
            callback(
                c.debug_source_api,
                c.debug_type_performance,
                1,
                c.debug_severity_medium,
                message.len,
                message,
                null,
            );
        }
    }

    pub fn glDebugMessageCallback(callback: ?types.DebugProc, user: ?*const anyopaque) callconv(.c) void {
        _ = user;
        debug_callback = callback;
        note("debugMessageCallback installed", .{});
    }

    fn hand(n: types.Sizei, out: [*]types.Uint) void {
        var i: usize = 0;
        while (i < @as(usize, @intCast(n))) : (i += 1) {
            out[i] = next_name;
            next_name += 1;
        }
    }

    fn yesNo(value: bool) []const u8 {
        return if (value) "yes" else "no";
    }
};
