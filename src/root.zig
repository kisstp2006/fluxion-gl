// SPDX-License-Identifier: CC0-1.0

//! Fluxion GL - the entry points of OpenGL and OpenGL ES, found at run time.
//!
//! Eight pieces:
//!
//!   `loader`      fills a struct of function pointers from a getProcAddress
//!   `gl`          the desktop table: OpenGL 3.3 core, later versions optional
//!   `gles`        the ES table: OpenGL ES 2.0, ES 3.0 optional
//!   `enums`       the tokens the commands take
//!   `types`       the C types they are written in
//!   `version`     `GL_VERSION` and the shading language version, as numbers
//!   `extensions`  the extension string or list, searched without allocating
//!   `library`     the GL library itself, for the commands Windows will not
//!                 hand out any other way
//!
//! There is no context creation here, and there will not be: GLFW, SDL, EGL
//! and the platform's own calls do that, and each of them hands back a
//! `getProcAddress`. This library starts where that function does.
//!
//! ```zig
//! var api: opengl.Gl = undefined;
//! try api.load(glfwGetProcAddress);
//!
//! api.clearColor(0.1, 0.1, 0.12, 1);
//! api.clear(c.color_buffer_bit);
//! api.drawArrays(c.triangles, 0, 3);
//! ```
//!
//! Nothing here allocates: a table is a struct the caller owns, an extension
//! list points into the driver's own string, and a version is four numbers
//! and a slice.

const std = @import("std");
const testing = std.testing;

pub const enums = @import("enums.zig");
pub const extensions = @import("extensions.zig");
pub const gl = @import("gl.zig");
pub const gles = @import("gles.zig");
pub const library = @import("library.zig");
pub const loader = @import("loader.zig");
pub const types = @import("types.zig");
pub const version = @import("version.zig");

/// The desktop OpenGL command table. See `gl`.
pub const Gl = gl.Api;

/// The OpenGL ES command table. See `gles`.
pub const Gles = gles.Api;

/// What a `getProcAddress` hands back. See `loader`.
pub const Proc = loader.Proc;

/// What GLFW, SDL, EGL, WGL and GLX all give you. See `loader`.
pub const GetProcAddress = loader.GetProcAddress;

/// What a load found. See `loader`.
pub const Status = loader.Status;

/// A version of the API. See `version`.
pub const Version = version.Version;

/// A version of the shading language. See `version`.
pub const Glsl = version.Glsl;

/// An open GL library. See `library`.
pub const Library = library.Library;

/// A getProcAddress with the library behind it. See `library`.
pub const Chain = library.Chain;

/// Fill any table of function pointers. See `loader.load`.
pub const load = loader.load;

/// The byte offset that goes where a pointer would. See `types.offset`.
pub const offset = types.offset;

test {
    // Pull each module in so `zig build test` runs its tests too.
    _ = enums;
    _ = extensions;
    _ = gl;
    _ = gles;
    _ = library;
    _ = loader;
    _ = types;
    _ = version;
}

/// A driver that stopped at OpenGL 3.2: everything 3.3 added is missing, and
/// so is everything after it.
const Older = struct {
    const absent = [_][]const u8{
        "glGenSamplers",
        "glDeleteSamplers",
        "glBindSampler",
        "glSamplerParameteri",
        "glSamplerParameterf",
        "glVertexAttribDivisor",
        "glGetFragDataLocation",
    };

    pub fn glGetString(name: types.Enum) callconv(.c) ?[*:0]const types.Char {
        return switch (name) {
            enums.version => "3.2.0 Fluxion 1.0",
            enums.shading_language_version => "1.50 Fluxion",
            else => null,
        };
    }

    pub fn glGetIntegerv(pname: types.Enum, data: [*]types.Int) callconv(.c) void {
        data[0] = if (pname == enums.num_extensions) 2 else 0;
    }

    pub fn glGetStringi(name: types.Enum, index: types.Uint) callconv(.c) ?[*:0]const types.Char {
        if (name != enums.extensions) return null;
        return switch (index) {
            0 => "GL_ARB_debug_output",
            1 => "GL_EXT_texture_filter_anisotropic",
            else => null,
        };
    }

    fn stub() callconv(.c) void {}

    fn get(name: [*:0]const u8) callconv(.c) ?Proc {
        const wanted = std.mem.span(name);
        for (absent) |gone| {
            if (std.mem.eql(u8, gone, wanted)) return null;
        }
        inline for (@typeInfo(Older).@"struct".decls) |decl| {
            if (std.mem.eql(u8, decl.name, wanted)) return @ptrCast(&@field(Older, decl.name));
        }
        return @ptrCast(&stub);
    }
};

test "the pieces compose" {
    // The table wants 3.3, the driver has 3.2, and the answer says which
    // command settled it rather than which line of the program crashed.
    var api: Gl = undefined;
    try testing.expectError(error.CommandMissing, api.load(Older.get));

    const status = api.tryLoad(Older.get);
    try testing.expect(!status.ok());
    try testing.expectEqual(Older.absent.len, status.short);
    try testing.expectEqualStrings("glVertexAttribDivisor", status.missing.?);

    // Everything else did load, so the commands that answer the questions
    // about the context are there to be asked.
    const context = try api.version();
    try testing.expect(context.atLeast(3, 2));
    try testing.expect(!context.atLeast(3, 3));

    // And the shading language version is the one a 3.2 context speaks,
    // which is not 3.20.
    var line: [32]u8 = undefined;
    var w: std.Io.Writer = .fixed(&line);
    try context.glsl().?.writeDirective(&w);
    try testing.expectEqualStrings("#version 150\n", w.buffered());

    var buffer: [8][]const u8 = undefined;
    const have = api.extensionNames(&buffer);
    try testing.expectEqual(2, have.count());
    try testing.expect(have.has("ARB_debug_output"));
}

test "a table of your own, for a driver that is not 3.3" {
    // The loader takes any struct of function pointers, so a program that
    // means to run on the driver above declares what it actually calls.
    const Minimal = struct {
        clear: *const fn (mask: types.Bitfield) callconv(.c) void,
        clearColor: *const fn (r: types.Float, g: types.Float, b: types.Float, a: types.Float) callconv(.c) void,
        drawArrays: *const fn (mode: types.Enum, first: types.Int, count: types.Sizei) callconv(.c) void,
        vertexAttribDivisor: ?*const fn (index: types.Uint, divisor: types.Uint) callconv(.c) void,
    };

    var api: Minimal = undefined;
    try load(&api, Older.get);

    // Instancing was 3.3, so it is null here and the compiler will not let a
    // call site pretend otherwise.
    try testing.expectEqual(null, api.vertexAttribDivisor);
    try testing.expectEqual(4, comptime loader.count(Minimal));
    try testing.expectEqualStrings("glVertexAttribDivisor", comptime loader.names(Minimal)[3]);
}

test "the shorthands" {
    try testing.expectEqual(null, offset(0));
    try testing.expectEqual(@as(usize, 24), @intFromPtr(offset(24).?));
    try testing.expectEqual(Version, @TypeOf(try Version.parse("4.6.0 NVIDIA")));
    try testing.expectEqual(gl.Api, Gl);
    try testing.expectEqual(gles.Api, Gles);
}
