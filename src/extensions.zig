// SPDX-License-Identifier: CC0-1.0

//! Which extensions a context has, asked without allocating.
//!
//! Two ways to ask, because OpenGL changed its mind. Up to 3.0, and in every
//! version of ES, `glGetString(GL_EXTENSIONS)` returns the set as one
//! space-separated string - that is `List`. From 3.0 that returns null in a
//! core profile and the set comes one name at a time from `glGetStringi` -
//! that is `Set`, over a buffer the caller owns.
//!
//! Both answer the same questions and neither copies: a `List` points into the
//! driver's own string and a `Set` is a slice of pointers into it, both valid
//! as long as the context.
//!
//! A name may be given with or without the `GL_` on the front, because half
//! the specifications write it one way and half the other:
//!
//! ```zig
//! list.has("GL_ARB_debug_output") == list.has("ARB_debug_output")
//! ```

const std = @import("std");
const testing = std.testing;

/// The extension string, as one blob. Cheap to make, linear to search - which
/// is the right trade for the handful of lookups a program does at startup
/// and the wrong one for a lookup in a loop.
pub const List = struct {
    text: []const u8,

    /// Wrap what `glGetString(GL_EXTENSIONS)` returned. A driver that has no
    /// extensions returns an empty string, and a core profile returns null,
    /// which is a different thing: use `Set` there.
    pub fn init(text: []const u8) List {
        return .{ .text = text };
    }

    /// Is `name` in the list?
    pub fn has(self: List, name: []const u8) bool {
        var it = self.iterator();
        while (it.next()) |token| {
            if (matches(token, name)) return true;
        }
        return false;
    }

    /// Are all of them?
    pub fn hasAll(self: List, names: []const []const u8) bool {
        return self.missing(names) == null;
    }

    /// The first of `names` that is not there, for an error message that says
    /// what to install rather than that something is wrong.
    pub fn missing(self: List, names: []const []const u8) ?[]const u8 {
        for (names) |name| {
            if (!self.has(name)) return name;
        }
        return null;
    }

    /// How many extensions the context has.
    pub fn count(self: List) usize {
        var n: usize = 0;
        var it = self.iterator();
        while (it.next()) |_| n += 1;
        return n;
    }

    /// Walk the names in the order the driver listed them.
    pub fn iterator(self: List) Iterator {
        return .{ .inner = std.mem.tokenizeAny(u8, self.text, " \t\n\r") };
    }

    /// Split the string into `buffer` and hand back a `Set` over as much of
    /// it as fit, so that one flat string and one indexed query end up the
    /// same shape. Nothing is copied: the slices point into the string.
    pub fn collect(self: List, buffer: [][]const u8) Set {
        var n: usize = 0;
        var it = self.iterator();
        while (it.next()) |token| {
            if (n == buffer.len) break;
            buffer[n] = token;
            n += 1;
        }
        return .{ .names = buffer[0..n] };
    }
};

/// The names one at a time, as `glGetStringi` gives them.
pub const Set = struct {
    names: []const []const u8,

    /// Is `name` in the set?
    pub fn has(self: Set, name: []const u8) bool {
        for (self.names) |token| {
            if (matches(token, name)) return true;
        }
        return false;
    }

    /// Are all of them?
    pub fn hasAll(self: Set, names: []const []const u8) bool {
        return self.missing(names) == null;
    }

    /// The first of `names` that is not there.
    pub fn missing(self: Set, names: []const []const u8) ?[]const u8 {
        for (names) |name| {
            if (!self.has(name)) return name;
        }
        return null;
    }

    /// How many extensions the context has - or, if the buffer it was
    /// gathered into was too small, how many fit.
    pub fn count(self: Set) usize {
        return self.names.len;
    }
};

/// The names, one per step.
pub const Iterator = struct {
    inner: std.mem.TokenIterator(u8, .any),

    pub fn next(self: *Iterator) ?[]const u8 {
        return self.inner.next();
    }
};

/// One name against one query, with the `GL_` on the front optional.
fn matches(token: []const u8, name: []const u8) bool {
    if (std.mem.eql(u8, token, name)) return true;
    return std.mem.startsWith(u8, token, "GL_") and std.mem.eql(u8, token[3..], name);
}

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

/// What a middling desktop driver reports, cut down to a line that fits.
const reported = "GL_ARB_debug_output GL_ARB_texture_storage GL_EXT_texture_filter_anisotropic GL_KHR_debug";

test "asking a flat string" {
    const list: List = .init(reported);

    try testing.expect(list.has("GL_KHR_debug"));
    try testing.expect(list.has("KHR_debug"));
    try testing.expect(!list.has("GL_ARB_bindless_texture"));
    try testing.expectEqual(4, list.count());

    // A prefix of a name is not the name, and neither is a name with more on
    // the end - the string is searched by token, not by substring.
    try testing.expect(!list.has("GL_KHR"));
    try testing.expect(!list.has("GL_KHR_debug_output"));
    try testing.expect(!list.has("debug"));
}

test "a context with nothing to report" {
    const empty: List = .init("");
    try testing.expectEqual(0, empty.count());
    try testing.expect(!empty.has("GL_KHR_debug"));
    try testing.expect(empty.hasAll(&.{}));
    try testing.expectEqualStrings("GL_KHR_debug", empty.missing(&.{"GL_KHR_debug"}).?);
}

test "several at once, and which one is short" {
    const list: List = .init(reported);
    try testing.expect(list.hasAll(&.{ "GL_KHR_debug", "ARB_texture_storage" }));
    try testing.expectEqual(null, list.missing(&.{"GL_KHR_debug"}));

    // The answer names the missing one, so the message can too.
    try testing.expectEqualStrings(
        "GL_ARB_bindless_texture",
        list.missing(&.{ "GL_KHR_debug", "GL_ARB_bindless_texture", "GL_ARB_sparse_texture" }).?,
    );
}

test "walking them" {
    const list: List = .init(reported);
    var it = list.iterator();
    try testing.expectEqualStrings("GL_ARB_debug_output", it.next().?);
    try testing.expectEqualStrings("GL_ARB_texture_storage", it.next().?);
    try testing.expectEqualStrings("GL_EXT_texture_filter_anisotropic", it.next().?);
    try testing.expectEqualStrings("GL_KHR_debug", it.next().?);
    try testing.expectEqual(null, it.next());

    // Drivers have been known to put two spaces between names, or a trailing
    // one; a run of blanks is one separator.
    const untidy: List = .init("  GL_KHR_debug   GL_ARB_debug_output \n");
    try testing.expectEqual(2, untidy.count());
    try testing.expect(untidy.has("GL_ARB_debug_output"));
}

test "the two ways of asking end up the same" {
    // What the indexed query would have handed back, name by name.
    const gathered: Set = .{ .names = &.{
        "GL_ARB_debug_output",
        "GL_ARB_texture_storage",
        "GL_EXT_texture_filter_anisotropic",
        "GL_KHR_debug",
    } };

    var buffer: [16][]const u8 = undefined;
    const collected = List.init(reported).collect(&buffer);

    try testing.expectEqual(gathered.count(), collected.count());
    for (gathered.names, collected.names) |a, b| try testing.expectEqualStrings(a, b);
    try testing.expect(collected.has("KHR_debug"));
    try testing.expect(gathered.has("KHR_debug"));
    try testing.expectEqualStrings(
        "GL_ARB_bindless_texture",
        gathered.missing(&.{"GL_ARB_bindless_texture"}).?,
    );
}

test "a buffer too small keeps what fit" {
    var buffer: [2][]const u8 = undefined;
    const collected = List.init(reported).collect(&buffer);
    try testing.expectEqual(2, collected.count());
    try testing.expect(collected.has("GL_ARB_debug_output"));
    try testing.expect(!collected.has("GL_KHR_debug"));
}
