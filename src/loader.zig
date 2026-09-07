// SPDX-License-Identifier: BSL-1.0

//! Filling a table of function pointers with the entry points a driver
//! actually has.
//!
//! Nothing in OpenGL is linked. The system library exports the handful of
//! commands that were there in 1997 and nothing since, so every command a
//! modern program calls has to be asked for by name at run time, from a
//! context that is already current. That asking is all a loader is.
//!
//! A table is a plain struct whose fields are function pointers:
//!
//! ```zig
//! const Minimal = struct {
//!     clear: *const fn (mask: Bitfield) callconv(.c) void,
//!     clearColor: *const fn (r: Float, g: Float, b: Float, a: Float) callconv(.c) void,
//!     bindVertexArray: ?*const fn (array: Uint) callconv(.c) void,
//! };
//! ```
//!
//! `load` walks the fields and asks for `glClear`, `glClearColor` and
//! `glBindVertexArray`: the field name is the command name with `gl` taken
//! off and the first letter lowered, which is also how Zig spells a function,
//! so the table reads as Zig and loads as GL.
//!
//! Optionality is in the type, and that is the whole version policy. A
//! `*const fn ...` field is required: if the driver has not got it, loading
//! fails and says which one. A `?*const fn ...` field is optional: if the
//! driver has not got it the field is `null`, loading carries on, and the
//! compiler makes the call site unwrap it - which is the check for "does this
//! context have compute shaders?" happening where the answer matters.
//!
//! A resolver is either the `getProcAddress` the window system handed you or
//! any value with a `get` method, so a fallback chain - see `library` - drops
//! in without changing anything here.
//!
//! **The walk itself is not about OpenGL.** Deriving a symbol name from a
//! field name, asking a resolver for it, and letting the field's type say
//! whether it may be absent is what `fluxion-dyn` does - for Vulkan and for
//! `d3d12.dll` as much as for a GL driver. So that is where it lives, and this
//! module is the OpenGL-facing name for it: the `gl` prefix as a default, the
//! word "command" where `fluxion-dyn` says "symbol", and nothing else.

const std = @import("std");
const testing = std.testing;

const dyn = @import("fluxion_dyn");

/// A function pointer of unknown signature, which is all `getProcAddress`
/// promises to return. Each one is cast to its field's type on the way into
/// the table; the cast is right exactly as far as the table's declaration is,
/// which is why the tables in `gl` and `gles` are worth reading.
pub const Proc = dyn.Proc;

/// The convention the platform's own entry points use: `stdcall` on Windows,
/// the C one everywhere else. On x86-64 Windows the two are the same and this
/// makes no difference; on a 32-bit build they are not.
pub const system = dyn.system;

/// The shape of every `getProcAddress` in the wild: GLFW's
/// `glfwGetProcAddress`, SDL's `SDL_GL_GetProcAddress`, EGL's
/// `eglGetProcAddress`, and the platform's own `wglGetProcAddress` and
/// `glXGetProcAddressARB`.
///
/// A resolver need not be one of these - anything with a `get` method will
/// do, and a function of any convention may be passed straight to `load` -
/// but this is the type a C library hands you, and the one `library.Chain`
/// holds.
pub const GetProcAddress = dyn.GetProcAddress;

/// Loading failed because a command the table requires was not there.
/// `Status.missing` names it; `tryLoad` reports rather than fails.
pub const Error = error{CommandMissing};

/// What a load found. `tryLoad` returns one; `load` turns anything but a
/// clean one into `error.CommandMissing`.
pub const Status = dyn.Status;

/// How field names are turned into the names the driver knows.
///
/// A table declares its own as `pub const options: Options = ...`, which
/// `load` picks up; `loadWith` overrides it for one call.
pub const Options = struct {
    /// Put in front of the capitalised field name. `gl` for both OpenGL and
    /// OpenGL ES; `egl`, `wgl` or `glX` for the window-system tables, which
    /// load exactly the same way.
    prefix: []const u8 = "gl",

    /// Tried, in order, when the plain name is not there: `glBindVertexArray`
    /// first, then `glBindVertexArrayOES`.
    ///
    /// Empty by default, and worth leaving that way unless you know the
    /// extension you are naming. An extension entry point is usually the same
    /// function under an older name, but not always - `glBindFramebufferEXT`
    /// belongs to a different object model than core `glBindFramebuffer`, and
    /// a loader that quietly substitutes one for the other produces a program
    /// that runs and draws nothing. Name the suffix where you have checked
    /// that the substitution holds:
    ///
    /// ```zig
    /// // Vertex arrays on an ES 2.0 context, where they are an extension.
    /// try loader.loadWith(&api, get, .{ .suffixes = &.{"OES"} });
    /// ```
    suffixes: []const []const u8 = &.{},

    /// The same rules under the names `fluxion-dyn` gives them. A GL table
    /// always capitalises, because it always has a prefix.
    pub fn naming(self: Options) dyn.Naming {
        return .{ .prefix = self.prefix, .suffixes = self.suffixes };
    }
};

/// Fill `table` - a pointer to a struct of function pointers - with the
/// driver's entry points, under the table's own `options`.
///
/// The context has to be current on the calling thread already: without one,
/// some drivers return null for everything and others return addresses that
/// belong to a context you are not using.
pub fn load(table: anytype, resolver: anytype) Error!void {
    return loadWith(table, resolver, optionsOf(Pointee(@TypeOf(table))));
}

/// `load` with the naming rules given here instead of the table's own.
pub fn loadWith(table: anytype, resolver: anytype, comptime options: Options) Error!void {
    if (!tryLoad(table, resolver, options).ok()) return error.CommandMissing;
}

/// Fill `table` and report, rather than fail. Use it where a missing command
/// is something to work around or to print, and for the count that belongs in
/// a startup log.
pub fn tryLoad(table: anytype, resolver: anytype, comptime options: Options) Status {
    return dyn.tryLoad(table, resolver, comptime options.naming());
}

/// The name `load` asks the driver for, given a field name: `clear` becomes
/// `glClear`. Comptime, and public because code that looks a command up by
/// hand should spell it the same way.
pub fn commandName(comptime field: []const u8, comptime options: Options) [:0]const u8 {
    return dyn.symbolName(field, comptime options.naming());
}

/// `commandName` with an extension suffix on the end: `bindVertexArray` and
/// `OES` become `glBindVertexArrayOES`.
pub fn commandNameSuffixed(
    comptime field: []const u8,
    comptime options: Options,
    comptime suffix: []const u8,
) [:0]const u8 {
    return dyn.table.symbolNameSuffixed(field, comptime options.naming(), suffix);
}

/// Every name a table asks for, in field order. Comptime, so it costs nothing
/// at run time: it is for printing what a driver was asked for next to what
/// it answered.
pub fn names(comptime Table: type) []const [:0]const u8 {
    return dyn.table.namesWith(Table, comptime optionsOf(Table).naming());
}

/// How many commands a table has.
pub const count = dyn.table.count;

/// How many of them are optional - the width of the gap between the version a
/// table requires and the version it can use.
pub const optionalCount = dyn.table.optionalCount;

// -------------------------------------------------------------------------
// The parts that only exist at compile time
// -------------------------------------------------------------------------

/// The struct behind a `*Table`, with a readable error for the common slip of
/// passing the table itself.
fn Pointee(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .pointer or info.pointer.size != .one or info.pointer.is_const) {
        @compileError("fluxion-gl: load wants a mutable pointer to the table (`&api`), not " ++ @typeName(T));
    }
    return info.pointer.child;
}

fn optionsOf(comptime Table: type) Options {
    return if (@hasDecl(Table, "options")) Table.options else .{};
}

// -------------------------------------------------------------------------
// Tests
//
// These do not re-test what `fluxion-dyn` already covers. They pin the part
// of it this library puts its own name on: the `gl` prefix, the suffix
// fallback GL needs for ES extensions, and `error.CommandMissing`.
// -------------------------------------------------------------------------

fn stub() callconv(.c) void {}

/// A driver that has exactly the commands it was told to have, and remembers
/// what it was asked for.
const Fake = struct {
    have: []const []const u8,
    asked: [16][]const u8 = undefined,
    asked_len: usize = 0,

    pub fn get(self: *Fake, name: [*:0]const u8) ?Proc {
        const wanted = std.mem.span(name);
        if (self.asked_len < self.asked.len) {
            self.asked[self.asked_len] = wanted;
            self.asked_len += 1;
        }
        for (self.have) |command| {
            if (std.mem.eql(u8, command, wanted)) return @ptrCast(&stub);
        }
        return null;
    }

    fn askedFor(self: *const Fake) []const []const u8 {
        return self.asked[0..self.asked_len];
    }
};

const Basic = struct {
    clear: *const fn (mask: c_uint) callconv(.c) void,
    getError: *const fn () callconv(.c) c_uint,
    bindVertexArray: ?*const fn (array: c_uint) callconv(.c) void,
};

test "field names become command names" {
    try testing.expectEqualStrings("glClear", comptime commandName("clear", .{}));
    try testing.expectEqualStrings("glGetError", comptime commandName("getError", .{}));
    // The underscore a few of them carry in the middle survives untouched.
    try testing.expectEqualStrings("glGetIntegeri_v", comptime commandName("getIntegeri_v", .{}));
    // A different API, loaded by the same machinery.
    try testing.expectEqualStrings("eglGetDisplay", comptime commandName("getDisplay", .{ .prefix = "egl" }));
    try testing.expectEqualStrings(
        "glBindVertexArrayOES",
        comptime commandNameSuffixed("bindVertexArray", .{}, "OES"),
    );

    // And the same names, in field order, for a whole table.
    const expected = [_][]const u8{ "glClear", "glGetError", "glBindVertexArray" };
    inline for (comptime names(Basic), expected) |asked, want| {
        try testing.expectEqualStrings(want, asked);
    }
    try testing.expectEqual(3, comptime count(Basic));
    try testing.expectEqual(1, comptime optionalCount(Basic));
}

test "a driver with everything" {
    var fake: Fake = .{ .have = &.{ "glClear", "glGetError", "glBindVertexArray" } };
    var api: Basic = undefined;
    try load(&api, &fake);

    // Asked for in field order, once each.
    try testing.expectEqual(3, fake.askedFor().len);
    try testing.expectEqualStrings("glClear", fake.askedFor()[0]);
    try testing.expectEqualStrings("glBindVertexArray", fake.askedFor()[2]);
    try testing.expect(api.bindVertexArray != null);
}

test "a driver missing an optional command" {
    var fake: Fake = .{ .have = &.{ "glClear", "glGetError" } };
    var api: Basic = undefined;
    const status = tryLoad(&api, &fake, .{});

    try testing.expect(status.ok());
    try testing.expectEqual(3, status.requested);
    try testing.expectEqual(2, status.loaded);
    try testing.expectEqual(1, status.absent);
    try testing.expectEqual(null, api.bindVertexArray);

    // Which is not an error, so the plain call goes through as well.
    try load(&api, &fake);
}

test "a driver missing a required command" {
    var fake: Fake = .{ .have = &.{"glClear"} };
    var api: Basic = undefined;

    const status = tryLoad(&api, &fake, .{});
    try testing.expect(!status.ok());
    try testing.expectEqual(1, status.short);
    try testing.expectEqualStrings("glGetError", status.missing.?);

    try testing.expectError(error.CommandMissing, load(&api, &fake));
}

test "the suffix fallback, and only when it is asked for" {
    const have = [_][]const u8{ "glClear", "glGetError", "glBindVertexArrayOES" };

    var without: Fake = .{ .have = &have };
    var api: Basic = undefined;
    try testing.expectEqual(1, tryLoad(&api, &without, .{}).absent);

    var with: Fake = .{ .have = &have };
    const status = tryLoad(&api, &with, .{ .suffixes = &.{"OES"} });
    try testing.expectEqual(0, status.absent);
    try testing.expect(api.bindVertexArray != null);

    // The plain name is still tried first, so a core command is never
    // quietly answered by an extension.
    try testing.expectEqualStrings("glBindVertexArray", with.askedFor()[2]);
    try testing.expectEqualStrings("glBindVertexArrayOES", with.askedFor()[3]);
}

test "a resolver can be a plain getProcAddress" {
    const Driver = struct {
        fn get(name: [*:0]const u8) callconv(system) ?Proc {
            if (std.mem.eql(u8, std.mem.span(name), "glBindVertexArray")) return null;
            return @ptrCast(&stub);
        }
    };

    var api: Basic = undefined;
    try load(&api, Driver.get);
    try testing.expectEqual(null, api.bindVertexArray);

    // The declared type is the same function, so the pointer form works too.
    const pointer: GetProcAddress = &Driver.get;
    try load(&api, pointer);
}

test "the status prints as one line for a startup log" {
    var buf: [128]u8 = undefined;
    var fake: Fake = .{ .have = &.{"glClear"} };
    var api: Basic = undefined;
    const status = tryLoad(&api, &fake, .{});
    try testing.expectEqualStrings(
        "1/3 loaded, 1 optional absent, 1 required missing, first glGetError",
        try std.fmt.bufPrint(&buf, "{f}", .{status}),
    );
}
