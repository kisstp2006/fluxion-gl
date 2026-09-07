// SPDX-License-Identifier: BSL-1.0

//! What this machine's OpenGL is, printed the way a bug report wants it. Run
//! it with `zig build example-capabilities`.
//!
//! `-- --extensions` lists every extension name as well, which is usually a
//! couple of hundred lines and occasionally the answer.
//!
//! This is the first program to write against a new context and the first
//! thing to ask somebody to run when a program does not draw on their
//! machine. It opens a real context - hidden, because there is nothing to
//! see - and asks it. Nothing below is invented: every number came from the
//! driver.
//!
//! The table it asks with is four commands long. Every version of OpenGL and
//! OpenGL ES back to 2.0 has all four, so it loads on anything with a context
//! at all, which is what a program reporting on a machine it cannot run on
//! needs. The two full tables are loaded afterwards, and what they make of
//! this driver is the last section.

const std = @import("std");
const Io = std.Io;

const opengl = @import("fluxion_gl");
const Window = @import("window").Window;

const c = opengl.enums;
const types = opengl.types;

/// Enough to ask questions with, and nothing else. `getStringi` is optional
/// because ES 2.0 and OpenGL 2.1 have not got it - and on a core profile from
/// 3.0 onwards it is the only way to list extensions, so a program that wants
/// both has to handle both.
const Context = struct {
    getString: *const fn (name: types.Enum) callconv(.c) ?[*:0]const types.Char,
    getIntegerv: *const fn (pname: types.Enum, data: [*]types.Int) callconv(.c) void,
    getError: *const fn () callconv(.c) types.Enum,
    getStringi: ?*const fn (name: types.Enum, index: types.Uint) callconv(.c) ?[*:0]const types.Char,
};

const limits = [_]struct { name: []const u8, token: types.Enum }{
    .{ .name = "texture size", .token = c.max_texture_size },
    .{ .name = "3D texture size", .token = c.max_3d_texture_size },
    .{ .name = "cube map size", .token = c.max_cube_map_texture_size },
    .{ .name = "array layers", .token = c.max_array_texture_layers },
    .{ .name = "renderbuffer size", .token = c.max_renderbuffer_size },
    .{ .name = "vertex attributes", .token = c.max_vertex_attribs },
    .{ .name = "texture units", .token = c.max_combined_texture_image_units },
    .{ .name = "colour attachments", .token = c.max_color_attachments },
    .{ .name = "draw buffers", .token = c.max_draw_buffers },
    .{ .name = "samples", .token = c.max_samples },
    .{ .name = "uniform block size", .token = c.max_uniform_block_size },
    .{ .name = "elements in a draw", .token = c.max_elements_indices },
};

/// The ones worth knowing about by name, whatever else a driver has.
const interesting = [_][]const u8{
    "GL_KHR_debug",
    "GL_ARB_direct_state_access",
    "GL_ARB_buffer_storage",
    "GL_ARB_texture_storage",
    "GL_EXT_texture_filter_anisotropic",
    "GL_ARB_bindless_texture",
};

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const out = &stdout.interface;

    const options = try Options.fromArguments(init, init.arena.allocator());

    // Hidden: there is nothing to draw, and a window that flashes up and goes
    // away again is worse than no window.
    var window = Window.open(.{ .width = 64, .height = 64, .visible = false }) catch |err| {
        try out.print("no OpenGL 3.3 context on this machine: {t}\n", .{err});
        try out.flush();
        return err;
    };
    defer window.close();

    var api: Context = undefined;
    try opengl.load(&api, window.resolver());

    // --- who is answering -------------------------------------------------
    const version = try opengl.Version.parse(std.mem.span(api.getString(c.version).?));
    const glsl = try opengl.Glsl.parse(std.mem.span(api.getString(c.shading_language_version).?));

    try out.print(
        \\--- the context ---
        \\vendor     {s}
        \\renderer   {s}
        \\version    {f}  ({s})
        \\
    , .{
        api.getString(c.vendor) orelse "unknown",
        api.getString(c.renderer) orelse "unknown",
        version,
        version.release,
    });
    try out.print("language   {f}, so a shader starts with ", .{glsl});
    try glsl.writeDirective(out);

    // The profile mask only exists from 3.2, so ask for it the way the rest
    // of the program asks for anything: by version first.
    if (version.api == .gl and version.atLeast(3, 2)) {
        var mask: [1]types.Int = .{0};
        api.getIntegerv(c.context_profile_mask, &mask);
        var flags: [1]types.Int = .{0};
        api.getIntegerv(c.context_flags, &flags);

        try out.print("profile    {s}{s}{s}\n", .{
            if (@as(types.Bitfield, @bitCast(mask[0])) & c.context_core_profile_bit != 0)
                "core"
            else
                "compatibility",
            if (@as(types.Bitfield, @bitCast(flags[0])) & c.context_flag_forward_compatible_bit != 0)
                ", forward compatible"
            else
                "",
            if (@as(types.Bitfield, @bitCast(flags[0])) & c.context_flag_debug_bit != 0)
                ", debug"
            else
                "",
        });
    }

    // --- what it can be asked to do ---------------------------------------
    try out.writeAll("\n--- limits ---\n");
    for (limits) |limit| {
        var value: [1]types.Int = .{0};
        api.getIntegerv(limit.token, &value);
        try out.print("{s:<22} {d}\n", .{ limit.name, value[0] });
    }

    // --- extensions --------------------------------------------------------
    var names: [1024][]const u8 = undefined;
    const have = extensions(api, &names);

    try out.print("\n--- extensions ({d}) ---\n", .{have.count()});
    for (interesting) |name| {
        try out.print("{s:<38} {s}\n", .{ name, if (have.has(name)) "yes" else "no" });
    }
    if (options.list_extensions) {
        try out.writeAll("\n");
        for (have.names) |name| try out.print("  {s}\n", .{name});
    } else {
        try out.writeAll("\n`-- --extensions` lists them all.\n");
    }

    // --- and what the library's own tables make of it -----------------------
    var desktop: opengl.Gl = undefined;
    var embedded: opengl.Gles = undefined;

    try out.print(
        \\
        \\--- the tables against this driver ---
        \\OpenGL 3.3 core   {f}
        \\OpenGL ES 2.0     {f}
        \\
    , .{
        desktop.tryLoad(window.resolver()),
        embedded.tryLoad(window.resolver()),
    });
    try out.print(
        \\
        \\{d} commands in the first, {d} of them optional; {d} and {d} in the
        \\second. A desktop context fills the first - that is what "OpenGL 3.3
        \\core" means, and a driver that fell short would be named here rather
        \\than found out at the first draw. The second is an OpenGL ES table
        \\on a desktop driver: what it finds is whatever ES-compatible entry
        \\points this one happens to export, which is not a context you can
        \\draw ES with and is exactly the kind of half-answer the optional
        \\half of a table exists to report.
        \\
    , .{
        comptime opengl.loader.count(opengl.Gl),
        comptime opengl.loader.optionalCount(opengl.Gl),
        comptime opengl.loader.count(opengl.Gles),
        comptime opengl.loader.optionalCount(opengl.Gles),
    });

    if (api.getError() != c.no_error) try out.writeAll("\nand something went wrong asking\n");
    try out.flush();
}

/// The extensions, whichever way this context has of listing them.
///
/// Up to OpenGL 3.0 and in every version of ES there is a flat string; from
/// 3.0 a core profile returns null there and hands them out one at a time
/// instead. A program that runs on both does this.
fn extensions(api: Context, buffer: [][]const u8) opengl.extensions.Set {
    if (api.getString(c.extensions)) |flat| {
        return opengl.extensions.List.init(std.mem.span(flat)).collect(buffer);
    }

    const getStringi = api.getStringi orelse return .{ .names = buffer[0..0] };
    var total: [1]types.Int = .{0};
    api.getIntegerv(c.num_extensions, &total);

    var found: usize = 0;
    var index: types.Uint = 0;
    while (index < @as(types.Uint, @intCast(@max(total[0], 0))) and found < buffer.len) : (index += 1) {
        buffer[found] = std.mem.span(getStringi(c.extensions, index) orelse continue);
        found += 1;
    }
    return .{ .names = buffer[0..found] };
}

const Options = struct {
    /// `--extensions`: print every name rather than the handful this program
    /// has an opinion about.
    list_extensions: bool = false,

    fn fromArguments(init: std.process.Init, arena: std.mem.Allocator) !Options {
        var options: Options = .{};
        const arguments = try init.minimal.args.toSlice(arena);
        for (arguments[@min(1, arguments.len)..]) |argument| {
            if (std.mem.eql(u8, argument, "--extensions")) {
                options.list_extensions = true;
            } else {
                return error.UnknownArgument;
            }
        }
        return options;
    }
};

test "the questions it asks are ones every context can answer" {
    // Four commands, and all four are in OpenGL 2.0 and in ES 2.0 - so this
    // table loads on anything that has a context at all, which is the point
    // of it being separate from `opengl.Gl`.
    const asked = comptime opengl.loader.names(Context);
    try std.testing.expectEqual(@as(usize, 4), asked.len);
    try std.testing.expectEqualStrings("glGetString", asked[0]);
    try std.testing.expectEqual(@as(usize, 1), comptime opengl.loader.optionalCount(Context));
}
