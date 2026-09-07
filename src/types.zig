// SPDX-License-Identifier: CC0-1.0

//! The C types OpenGL is written in, spelled as Zig types.
//!
//! GL declares its own names for the machine's integers - `GLint`, `GLsizei`,
//! `GLenum` - and a command table has to use the same widths the driver was
//! compiled with, so these are aliases for the C types rather than for `i32`
//! and friends. On every platform GL runs on they come out the same size; the
//! aliases are what makes that a fact rather than a hope.
//!
//! Two of them are worth reading twice:
//!
//!   * `Boolean` is a byte, not a `bool`. GL returns 0 or 1 in eight bits,
//!     and Zig's `bool` has no defined size in an extern signature, so the
//!     tables use `Boolean` and `isTrue` turns one into an answer.
//!   * `Sync` is a nullable pointer to an opaque object, which is how
//!     `GLsync` is declared and why a fence can be compared against `null`.
//!
//! `offset` is here because the one place GL asks for a pointer that is not a
//! pointer - the vertex attribute offset into a bound buffer - has no safe
//! spelling in Zig without it.

const std = @import("std");
const testing = std.testing;

/// `GLenum`: a token from `enums`, not an enumeration in the Zig sense. The
/// values come from one flat numbering shared by every command, which is why
/// `linear` (a filter) and `line` (a polygon mode) are different numbers.
pub const Enum = c_uint;

/// `GLboolean`: one byte, 0 or 1. See `isTrue` and `boolean`.
pub const Boolean = u8;

/// `GLbitfield`: an or-ing of the `_bit` constants.
pub const Bitfield = c_uint;

/// `GLbyte`.
pub const Byte = i8;

/// `GLubyte`.
pub const Ubyte = u8;

/// `GLshort`.
pub const Short = c_short;

/// `GLushort`.
pub const Ushort = c_ushort;

/// `GLint`.
pub const Int = c_int;

/// `GLuint`: also every object name - buffers, textures, programs - because
/// GL hands out integers rather than pointers.
pub const Uint = c_uint;

/// `GLfixed`: 16.16 fixed point, from OpenGL ES.
pub const Fixed = i32;

/// `GLint64`.
pub const Int64 = i64;

/// `GLuint64`: what a timer query counts in, and what a sync object's timeout
/// is measured in.
pub const Uint64 = u64;

/// `GLsizei`: a count or a size. Signed, because GL says so, and negative is
/// an error the driver raises rather than a type the compiler rejects.
pub const Sizei = c_int;

/// `GLfloat`.
pub const Float = f32;

/// `GLclampf`: a float the driver clamps to 0..1.
pub const Clampf = f32;

/// `GLdouble`.
pub const Double = f64;

/// `GLclampd`.
pub const Clampd = f64;

/// `GLchar`: a byte of a shader source or a name. Spelled unsigned here
/// because Zig's string literals are, and the signedness of `char` never
/// reaches a GL call.
pub const Char = u8;

/// `GLintptr`: a byte offset into a buffer object. Pointer-sized, so 32 bits
/// on a 32-bit build.
pub const Intptr = isize;

/// `GLsizeiptr`: a size in bytes of a buffer object. Signed and
/// pointer-sized, for the same reason `Sizei` is signed.
pub const Sizeiptr = isize;

/// What a `Sync` points at. Never dereferenced: the driver owns it and only
/// the sync commands may look inside.
pub const SyncObject = opaque {};

/// `GLsync`: a fence in the command stream, or `null`.
pub const Sync = ?*SyncObject;

/// `GLDEBUGPROC`: what `debugMessageCallback` calls, on the driver's thread,
/// possibly while inside another GL command. Anything it touches has to be
/// safe to touch there, which in practice means printing and nothing else.
///
/// `message` is `length` bytes long and is also NUL-terminated, so either
/// `message[0..@intCast(length)]` or `std.mem.span(message)` reads it.
pub const DebugProc = *const fn (
    source: Enum,
    kind: Enum,
    id: Uint,
    severity: Enum,
    length: Sizei,
    message: [*:0]const Char,
    user_param: ?*const anyopaque,
) callconv(.c) void;

/// `GL_TRUE`.
pub const gl_true: Boolean = 1;

/// `GL_FALSE`.
pub const gl_false: Boolean = 0;

/// A `GLboolean` as an answer.
pub fn isTrue(value: Boolean) bool {
    return value != gl_false;
}

/// An answer as a `GLboolean`, for the arguments that take one - `normalized`
/// on a vertex attribute, `transpose` on a matrix uniform.
pub fn boolean(value: bool) Boolean {
    return if (value) gl_true else gl_false;
}

/// The byte offset that `vertexAttribPointer`, `drawElements` and the other
/// commands taking a `const void *` want when a buffer is bound: not an
/// address at all, but a number of bytes from the start of the buffer.
///
/// It exists because the obvious spelling is wrong in Zig. `@ptrFromInt(0)`
/// is illegal behaviour for a non-optional pointer, and offset zero - the
/// first attribute in every interleaved vertex - is the common case:
///
/// ```zig
/// api.vertexAttribPointer(0, 3, c.float, c.gl_false, stride, offset(0));
/// api.vertexAttribPointer(1, 2, c.float, c.gl_false, stride, offset(12));
/// ```
pub fn offset(byte_offset: usize) ?*const anyopaque {
    if (byte_offset == 0) return null;
    return @ptrFromInt(byte_offset);
}

test "widths match what the driver was compiled with" {
    // Everything a command table passes by value is 32 bits or fewer, apart
    // from the pointer-sized buffer offsets and the 64-bit timers.
    try testing.expectEqual(4, @sizeOf(Enum));
    try testing.expectEqual(4, @sizeOf(Int));
    try testing.expectEqual(4, @sizeOf(Uint));
    try testing.expectEqual(4, @sizeOf(Sizei));
    try testing.expectEqual(4, @sizeOf(Float));
    try testing.expectEqual(8, @sizeOf(Double));
    try testing.expectEqual(1, @sizeOf(Boolean));
    try testing.expectEqual(2, @sizeOf(Short));
    try testing.expectEqual(@sizeOf(usize), @sizeOf(Intptr));
    try testing.expectEqual(@sizeOf(usize), @sizeOf(Sizeiptr));
}

test "booleans in both directions" {
    try testing.expect(isTrue(gl_true));
    try testing.expect(!isTrue(gl_false));
    // Anything not zero is true, which is what a driver returning 2 means.
    try testing.expect(isTrue(2));
    try testing.expectEqual(gl_true, boolean(true));
    try testing.expectEqual(gl_false, boolean(false));
}

test "offsets, including the one that cannot be a pointer" {
    try testing.expectEqual(@as(?*const anyopaque, null), offset(0));
    try testing.expectEqual(@as(usize, 12), @intFromPtr(offset(12).?));
    try testing.expectEqual(@as(usize, 4096), @intFromPtr(offset(4096).?));
}
