// SPDX-License-Identifier: CC0-1.0

//! What `glGetString(GL_VERSION)` and `GL_SHADING_LANGUAGE_VERSION` say, read
//! as numbers.
//!
//! No version query in OpenGL avoids parsing. `GL_MAJOR_VERSION` and
//! `GL_MINOR_VERSION` are integers, but exist only from OpenGL 3.0 and not at
//! all in ES 2.0, so finding out whether you may use them means reading the
//! string first. The string is the one thing every context has:
//!
//!   `4.6.0 NVIDIA 550.54.14`
//!   `3.3.0 - Build 27.20.100.8681`
//!   `4.5 (Core Profile) Mesa 23.2.1`
//!   `OpenGL ES 3.2 Mesa 23.2.1`
//!   `OpenGL ES-CM 1.1`
//!
//! The shape is fixed by the specification and the rest is the vendor's: an
//! optional `OpenGL ES` in front, then major and minor, then a vendor release
//! number, then anything at all. `Version.parse` takes the specified part and
//! hands back the rest as `release`, unread.
//!
//! `Glsl` is the same job for the shading language, whose numbering is not the
//! API's - OpenGL 3.2 speaks GLSL 1.50 - and whose minor is two digits wide,
//! because a shader writes it as one number: `#version 150`. `Version.glsl`
//! gives the version a context implies, and `Glsl.writeDirective` writes the
//! line a shader starts with, including the `es` that ES 3.0 wants.

const std = @import("std");
const testing = std.testing;

/// Which of the two APIs a version belongs to. They share a numbering space
/// but not a meaning: OpenGL ES 3.0 is roughly OpenGL 3.3 with things taken
/// out, not OpenGL 3.0.
pub const Api = enum {
    gl,
    gles,

    /// `OpenGL` or `OpenGL ES`, for a message a person will read.
    pub fn name(self: Api) []const u8 {
        return switch (self) {
            .gl => "OpenGL",
            .gles => "OpenGL ES",
        };
    }
};

/// The string did not start with a version number, which means it did not
/// come from `glGetString` on a live context - the usual cause being a null
/// return, read as an empty string.
pub const ParseError = error{NoVersion};

/// A version of the API itself.
pub const Version = struct {
    api: Api,
    major: u16,
    minor: u16,
    /// Everything after the numbers: the driver's own version, the profile it
    /// felt like mentioning, the name of the renderer. Never parsed here,
    /// because nothing about it is specified, and worth logging whole.
    release: []const u8 = "",

    /// Read a `GL_VERSION` string.
    pub fn parse(text: []const u8) ParseError!Version {
        var rest = std.mem.trim(u8, text, " \t");
        var api: Api = .gl;

        // `OpenGL ES-CM` is the common profile of ES 1.x and `-CL` the common
        // lite one; both are as good as gone, and both still turn up in the
        // strings of embedded drivers.
        for ([_][]const u8{ "OpenGL ES-CM ", "OpenGL ES-CL ", "OpenGL ES " }) |prefix| {
            if (std.mem.startsWith(u8, rest, prefix)) {
                api = .gles;
                rest = std.mem.trimStart(u8, rest[prefix.len..], " ");
                break;
            }
        }

        const major = try number(rest);
        if (major.rest.len == 0 or major.rest[0] != '.') return error.NoVersion;
        const minor = try number(major.rest[1..]);

        // A third number is the vendor's release, which belongs to the tail.
        var tail = minor.rest;
        if (tail.len > 1 and tail[0] == '.' and std.ascii.isDigit(tail[1])) {
            tail = (number(tail[1..]) catch unreachable).rest;
        }

        return .{
            .api = api,
            .major = major.value,
            .minor = minor.value,
            .release = std.mem.trim(u8, tail, " \t"),
        };
    }

    /// Is this at least `major`.`minor`? The comparison is on the numbers
    /// alone, so check `api` first where both are possible: ES 3.0 is not
    /// OpenGL 3.0, and neither implies the other.
    pub fn atLeast(self: Version, major: u16, minor: u16) bool {
        return self.major > major or (self.major == major and self.minor >= minor);
    }

    /// Order two versions by number, for a table of what a driver needs.
    pub fn order(self: Version, other: Version) std.math.Order {
        return switch (std.math.order(self.major, other.major)) {
            .eq => std.math.order(self.minor, other.minor),
            else => |result| result,
        };
    }

    /// The shading language version this API version brings with it, or null
    /// for a context too old to have one.
    ///
    /// The two numberings only line up from OpenGL 3.3 onwards, which is
    /// exactly why this exists: OpenGL 3.2 speaks GLSL 1.50, and a program
    /// that writes `#version 320` into a 3.2 shader gets a compile error with
    /// nothing helpful in it.
    pub fn glsl(self: Version) ?Glsl {
        return switch (self.api) {
            .gles => switch (self.major) {
                0, 1 => null,
                2 => .{ .api = .gles, .major = 1, .minor = 0 },
                else => .{ .api = .gles, .major = self.major, .minor = self.minor * 10 },
            },
            .gl => switch (self.major) {
                0, 1 => null,
                2 => switch (self.minor) {
                    0 => .{ .api = .gl, .major = 1, .minor = 10 },
                    else => .{ .api = .gl, .major = 1, .minor = 20 },
                },
                3 => switch (self.minor) {
                    0 => .{ .api = .gl, .major = 1, .minor = 30 },
                    1 => .{ .api = .gl, .major = 1, .minor = 40 },
                    2 => .{ .api = .gl, .major = 1, .minor = 50 },
                    else => .{ .api = .gl, .major = 3, .minor = 30 },
                },
                else => .{ .api = .gl, .major = self.major, .minor = self.minor * 10 },
            },
        };
    }

    pub fn format(self: Version, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{s} {d}.{d}", .{ self.api.name(), self.major, self.minor });
    }
};

/// A version of the shading language.
pub const Glsl = struct {
    api: Api,
    major: u16,
    /// Two digits wide, as the language writes it: GLSL 4.60 has a minor of
    /// 60, not 6. A string that gives one digit is read as that digit times
    /// ten, so `4.6` and `4.60` mean the same thing here.
    minor: u16,
    release: []const u8 = "",

    /// Read a `GL_SHADING_LANGUAGE_VERSION` string.
    pub fn parse(text: []const u8) ParseError!Glsl {
        var rest = std.mem.trim(u8, text, " \t");
        var api: Api = .gl;
        if (std.mem.startsWith(u8, rest, "OpenGL ES GLSL ES ")) {
            api = .gles;
            rest = std.mem.trimStart(u8, rest["OpenGL ES GLSL ES ".len..], " ");
        }

        const major = try number(rest);
        if (major.rest.len == 0 or major.rest[0] != '.') return error.NoVersion;
        const minor = try number(major.rest[1..]);

        return .{
            .api = api,
            .major = major.value,
            .minor = if (minor.digits == 1) minor.value * 10 else minor.value,
            .release = std.mem.trim(u8, minor.rest, " \t"),
        };
    }

    /// The number that goes in the `#version` line: 330, 460, 300.
    pub fn directive(self: Glsl) u16 {
        return self.major * 100 + self.minor;
    }

    /// Is this at least `major`.`minor`, with the minor written as the
    /// language writes it - `atLeast(3, 30)`, not `atLeast(3, 3)`.
    pub fn atLeast(self: Glsl, major: u16, minor: u16) bool {
        return self.major > major or (self.major == major and self.minor >= minor);
    }

    /// Write the line a shader has to start with, newline and all.
    ///
    /// The `es` on the end is not decoration: an ES 3.0 shader without it is
    /// asking for desktop GLSL 3.00, which does not exist. ES 2.0 is the
    /// exception, because `#version 100` predates the suffix.
    pub fn writeDirective(self: Glsl, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("#version {d}", .{self.directive()});
        if (self.api == .gles and self.directive() >= 300) try w.writeAll(" es");
        try w.writeByte('\n');
    }

    pub fn format(self: Glsl, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{s} GLSL {d}.{d:0>2}", .{ self.api.name(), self.major, self.minor });
    }
};

/// One run of decimal digits, and what came after it. Saturating, because a
/// driver that reports a five-digit major version is broken in a way this
/// cannot fix and should not crash over.
const Number = struct {
    value: u16,
    digits: usize,
    rest: []const u8,
};

fn number(text: []const u8) ParseError!Number {
    var value: u16 = 0;
    var digits: usize = 0;
    while (digits < text.len and std.ascii.isDigit(text[digits])) : (digits += 1) {
        value = value *| 10 +| (text[digits] - '0');
    }
    if (digits == 0) return error.NoVersion;
    return .{ .value = value, .digits = digits, .rest = text[digits..] };
}

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

test "the strings real drivers return" {
    const cases = [_]struct {
        text: []const u8,
        api: Api,
        major: u16,
        minor: u16,
        release: []const u8,
    }{
        .{ .text = "4.6.0 NVIDIA 550.54.14", .api = .gl, .major = 4, .minor = 6, .release = "NVIDIA 550.54.14" },
        .{ .text = "3.3.0 - Build 27.20.100.8681", .api = .gl, .major = 3, .minor = 3, .release = "- Build 27.20.100.8681" },
        .{ .text = "4.5 (Core Profile) Mesa 23.2.1", .api = .gl, .major = 4, .minor = 5, .release = "(Core Profile) Mesa 23.2.1" },
        .{ .text = "2.1 ATI-4.2.15", .api = .gl, .major = 2, .minor = 1, .release = "ATI-4.2.15" },
        .{ .text = "4.1 Metal - 88", .api = .gl, .major = 4, .minor = 1, .release = "Metal - 88" },
        .{ .text = "OpenGL ES 3.2 Mesa 23.2.1", .api = .gles, .major = 3, .minor = 2, .release = "Mesa 23.2.1" },
        .{ .text = "OpenGL ES 3.0.0 (ANGLE 2.1.0)", .api = .gles, .major = 3, .minor = 0, .release = "(ANGLE 2.1.0)" },
        .{ .text = "OpenGL ES-CM 1.1", .api = .gles, .major = 1, .minor = 1, .release = "" },
        .{ .text = "OpenGL ES-CL 1.0", .api = .gles, .major = 1, .minor = 0, .release = "" },
    };

    for (cases) |case| {
        const parsed = try Version.parse(case.text);
        try testing.expectEqual(case.api, parsed.api);
        try testing.expectEqual(case.major, parsed.major);
        try testing.expectEqual(case.minor, parsed.minor);
        try testing.expectEqualStrings(case.release, parsed.release);
    }
}

test "strings that are not versions" {
    try testing.expectError(error.NoVersion, Version.parse(""));
    try testing.expectError(error.NoVersion, Version.parse("   "));
    try testing.expectError(error.NoVersion, Version.parse("NVIDIA"));
    // A major with no minor is not a version either: GL always writes both.
    try testing.expectError(error.NoVersion, Version.parse("4"));
    try testing.expectError(error.NoVersion, Version.parse("4."));
}

test "comparing versions" {
    const context = try Version.parse("4.5 (Core Profile) Mesa 23.2.1");
    try testing.expect(context.atLeast(4, 5));
    try testing.expect(context.atLeast(3, 3));
    try testing.expect(context.atLeast(4, 0));
    try testing.expect(!context.atLeast(4, 6));
    try testing.expect(!context.atLeast(5, 0));

    const older = try Version.parse("3.3.0 Mesa");
    try testing.expectEqual(std.math.Order.lt, older.order(context));
    try testing.expectEqual(std.math.Order.gt, context.order(older));
    try testing.expectEqual(std.math.Order.eq, context.order(context));
}

test "the shading language a context implies" {
    const cases = [_]struct { text: []const u8, directive: u16 }{
        .{ .text = "2.0 driver", .directive = 110 },
        .{ .text = "2.1 driver", .directive = 120 },
        .{ .text = "3.0 driver", .directive = 130 },
        .{ .text = "3.1 driver", .directive = 140 },
        // The one that catches people: 3.2 is 1.50, not 3.20.
        .{ .text = "3.2 driver", .directive = 150 },
        .{ .text = "3.3 driver", .directive = 330 },
        .{ .text = "4.6 driver", .directive = 460 },
        .{ .text = "OpenGL ES 2.0 driver", .directive = 100 },
        .{ .text = "OpenGL ES 3.0 driver", .directive = 300 },
        .{ .text = "OpenGL ES 3.2 driver", .directive = 320 },
    };
    for (cases) |case| {
        const parsed = try Version.parse(case.text);
        try testing.expectEqual(case.directive, parsed.glsl().?.directive());
    }

    // Before shaders there is nothing to ask for.
    try testing.expectEqual(null, (try Version.parse("1.5 driver")).glsl());
    try testing.expectEqual(null, (try Version.parse("OpenGL ES-CM 1.1")).glsl());
}

test "the shading language strings themselves" {
    const desktop = try Glsl.parse("4.60 NVIDIA");
    try testing.expectEqual(Api.gl, desktop.api);
    try testing.expectEqual(4, desktop.major);
    try testing.expectEqual(60, desktop.minor);
    try testing.expectEqual(460, desktop.directive());
    try testing.expectEqualStrings("NVIDIA", desktop.release);

    const es = try Glsl.parse("OpenGL ES GLSL ES 3.20");
    try testing.expectEqual(Api.gles, es.api);
    try testing.expectEqual(320, es.directive());

    // ES 2.0 reports its language as 1.00.
    try testing.expectEqual(100, (try Glsl.parse("OpenGL ES GLSL ES 1.00")).directive());

    // One digit after the point means tenths, not hundredths.
    try testing.expectEqual(460, (try Glsl.parse("4.6")).directive());
    try testing.expectEqual(150, (try Glsl.parse("1.50")).directive());

    try testing.expect(desktop.atLeast(3, 30));
    try testing.expect(!desktop.atLeast(4, 70));
}

test "the line a shader starts with" {
    var buf: [64]u8 = undefined;

    var w: std.Io.Writer = .fixed(&buf);
    try (try Version.parse("3.3.0 NVIDIA")).glsl().?.writeDirective(&w);
    try testing.expectEqualStrings("#version 330\n", w.buffered());

    // ES 3.0 and later carry the suffix; ES 2.0 predates it.
    w = .fixed(&buf);
    try (try Version.parse("OpenGL ES 3.0 ANGLE")).glsl().?.writeDirective(&w);
    try testing.expectEqualStrings("#version 300 es\n", w.buffered());

    w = .fixed(&buf);
    try (try Version.parse("OpenGL ES 2.0 ANGLE")).glsl().?.writeDirective(&w);
    try testing.expectEqualStrings("#version 100\n", w.buffered());
}

test "printing them for a log" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings(
        "OpenGL 4.6",
        try std.fmt.bufPrint(&buf, "{f}", .{try Version.parse("4.6.0 NVIDIA")}),
    );
    try testing.expectEqualStrings(
        "OpenGL ES 3.2",
        try std.fmt.bufPrint(&buf, "{f}", .{try Version.parse("OpenGL ES 3.2 Mesa")}),
    );
    try testing.expectEqualStrings(
        "OpenGL GLSL 3.30",
        try std.fmt.bufPrint(&buf, "{f}", .{try Glsl.parse("3.30")}),
    );
    // The two-digit minor is why this is not printed with {d}.{d}.
    try testing.expectEqualStrings(
        "OpenGL ES GLSL 3.00",
        try std.fmt.bufPrint(&buf, "{f}", .{try Glsl.parse("OpenGL ES GLSL ES 3.00")}),
    );
}
