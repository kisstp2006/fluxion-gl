// SPDX-License-Identifier: CC0-1.0

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

const std = @import("std");
const testing = std.testing;

/// A function pointer of unknown signature, which is all `getProcAddress`
/// promises to return. Each one is cast to its field's type on the way into
/// the table; the cast is right exactly as far as the table's declaration is,
/// which is why the tables in `gl` and `gles` are worth reading.
pub const Proc = *const fn () callconv(.c) void;

/// The shape of every `getProcAddress` in the wild: GLFW's
/// `glfwGetProcAddress`, SDL's `SDL_GL_GetProcAddress`, EGL's
/// `eglGetProcAddress`, and the platform's own `wglGetProcAddress` and
/// `glXGetProcAddressARB`.
///
/// A resolver need not be one of these - anything with a `get` method will
/// do - but this is the type a C library hands you.
pub const GetProcAddress = *const fn (name: [*:0]const u8) callconv(.c) ?Proc;

/// Loading failed because a command the table requires was not there.
/// `Status.missing` names it; `tryLoad` reports rather than fails.
pub const Error = error{CommandMissing};

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
};

/// What a load found. `tryLoad` returns one; `load` turns anything but a
/// clean one into `error.CommandMissing`.
pub const Status = struct {
    /// Fields in the table.
    requested: usize = 0,
    /// Fields the driver had an address for.
    loaded: usize = 0,
    /// Optional fields the driver had not; those are `null`.
    absent: usize = 0,
    /// Required fields the driver had not. Those were left exactly as they
    /// were, which for a fresh table means undefined.
    short: usize = 0,
    /// The first required field the driver had not, under the name it was
    /// asked for.
    missing: ?[]const u8 = null,

    /// Is the table safe to call?
    pub fn ok(self: Status) bool {
        return self.short == 0;
    }

    pub fn format(self: Status, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{d}/{d} loaded", .{ self.loaded, self.requested });
        if (self.absent > 0) try w.print(", {d} optional absent", .{self.absent});
        if (self.missing) |name| try w.print(", {d} required missing, first {s}", .{ self.short, name });
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
    const Table = Pointee(@TypeOf(table));
    const fields = @typeInfo(Table).@"struct".fields;

    var status: Status = .{ .requested = fields.len };
    inline for (fields) |field| {
        const Command = CommandType(Table, field);
        const required = @typeInfo(field.type) != .optional;
        const name = comptime commandName(field.name, options);

        var found = resolve(resolver, name);
        inline for (options.suffixes) |suffix| {
            if (found == null) {
                found = resolve(resolver, comptime commandNameSuffixed(field.name, options, suffix));
            }
        }

        if (found) |proc| {
            @field(table, field.name) = @as(Command, @ptrCast(proc));
            status.loaded += 1;
        } else if (required) {
            status.short += 1;
            if (status.missing == null) status.missing = name;
        } else {
            @field(table, field.name) = null;
            status.absent += 1;
        }
    }
    return status;
}

/// The name `load` asks the driver for, given a field name: `clear` becomes
/// `glClear`. Comptime, and public because code that looks a command up by
/// hand should spell it the same way.
pub fn commandName(comptime field: []const u8, comptime options: Options) [:0]const u8 {
    return commandNameSuffixed(field, options, "");
}

/// `commandName` with an extension suffix on the end: `bindVertexArray` and
/// `OES` become `glBindVertexArrayOES`.
pub fn commandNameSuffixed(
    comptime field: []const u8,
    comptime options: Options,
    comptime suffix: []const u8,
) [:0]const u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        if (field.len == 0) @compileError("fluxion-gl: a table field must have a name");
        var buf: [options.prefix.len + field.len + suffix.len:0]u8 = undefined;
        @memcpy(buf[0..options.prefix.len], options.prefix);
        buf[options.prefix.len] = std.ascii.toUpper(field[0]);
        @memcpy(buf[options.prefix.len + 1 ..][0 .. field.len - 1], field[1..]);
        @memcpy(buf[options.prefix.len + field.len ..], suffix);
        buf[buf.len] = 0;
        const frozen = buf;
        return &frozen;
    }
}

/// Every name a table asks for, in field order. Comptime, so it costs nothing
/// at run time: it is for printing what a driver was asked for next to what
/// it answered.
pub fn names(comptime Table: type) []const [:0]const u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        const fields = @typeInfo(Table).@"struct".fields;
        var out: [fields.len][:0]const u8 = undefined;
        for (&out, fields) |*slot, field| slot.* = commandName(field.name, optionsOf(Table));
        const frozen = out;
        return &frozen;
    }
}

/// How many commands a table has.
pub fn count(comptime Table: type) usize {
    return @typeInfo(Table).@"struct".fields.len;
}

/// How many of them are optional - the width of the gap between the version a
/// table requires and the version it can use.
pub fn optionalCount(comptime Table: type) usize {
    comptime {
        var n: usize = 0;
        for (@typeInfo(Table).@"struct".fields) |field| {
            if (@typeInfo(field.type) == .optional) n += 1;
        }
        return n;
    }
}

// -------------------------------------------------------------------------
// The parts that only exist at compile time
// -------------------------------------------------------------------------

/// Ask one resolver for one name. A plain `getProcAddress` is called; a value
/// with a `get` method has that called, which is how `library.Chain` and
/// anything else that carries state joins in.
fn resolve(resolver: anytype, name: [:0]const u8) ?Proc {
    const Resolver = @TypeOf(resolver);
    const returned = switch (@typeInfo(Resolver)) {
        .@"fn" => resolver(name.ptr),
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => resolver(name.ptr),
            else => resolver.get(name.ptr),
        },
        .@"struct" => resolver.get(name.ptr),
        .optional => @compileError("fluxion-gl: the resolver is optional (" ++ @typeName(Resolver) ++
            "); unwrap it, so that a missing getProcAddress is not read as a driver with no commands"),
        else => @compileError("fluxion-gl: a resolver is a getProcAddress function or a value with a `get` method, not " ++
            @typeName(Resolver)),
    };
    return @ptrCast(returned);
}

/// The struct behind a `*Table`, with a readable error for the common slip of
/// passing the table itself.
fn Pointee(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .pointer or info.pointer.size != .one or info.pointer.is_const) {
        @compileError("fluxion-gl: load wants a mutable pointer to the table (`&api`), not " ++ @typeName(T));
    }
    return info.pointer.child;
}

/// The function pointer type a field holds, with the optional taken off.
fn CommandType(comptime Table: type, comptime field: std.builtin.Type.StructField) type {
    const inner = switch (@typeInfo(field.type)) {
        .optional => |optional| optional.child,
        else => field.type,
    };
    const bad = "fluxion-gl: field " ++ @typeName(Table) ++ "." ++ field.name ++ " is " ++
        @typeName(field.type) ++ "; a table field is `*const fn (...) callconv(.c) T`," ++
        " or the optional of one for a command that may be absent";
    switch (@typeInfo(inner)) {
        .pointer => |pointer| {
            if (pointer.size != .one or @typeInfo(pointer.child) != .@"fn") @compileError(bad);
        },
        else => @compileError(bad),
    }
    return inner;
}

fn optionsOf(comptime Table: type) Options {
    return if (@hasDecl(Table, "options")) Table.options else .{};
}

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

fn stub() callconv(.c) void {}

/// A driver that has exactly the commands it was told to have, and remembers
/// what it was asked for.
const Fake = struct {
    have: []const []const u8,
    asked: [16][]const u8 = undefined,
    asked_len: usize = 0,

    fn get(self: *Fake, name: [*:0]const u8) ?Proc {
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
        fn get(name: [*:0]const u8) callconv(.c) ?Proc {
            if (std.mem.eql(u8, std.mem.span(name), "glBindVertexArray")) return null;
            return @ptrCast(&stub);
        }
    };

    var api: Basic = undefined;
    try load(&api, Driver.get);
    try testing.expectEqual(null, api.bindVertexArray);

    // The C type is the same function, so the pointer form works too.
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
