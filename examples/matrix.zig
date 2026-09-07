// SPDX-License-Identifier: CC0-1.0

//! The four-by-four matrices the examples upload, and nothing else.
//!
//! This is not part of the library. A loader has no business having an
//! opinion about your vectors, and every program that draws already has a
//! maths library of its own; this one exists so that `sprites.zig` and
//! `cube.zig` can be about OpenGL.
//!
//! The layout is the one `uniformMatrix4fv` expects with `transpose` set to
//! `gl_false`: sixteen floats, column by column, so element `[c * 4 + r]` is
//! row `r` of column `c`. Getting that backwards is the classic first bug of
//! a 3D program - the picture is not wrong, it is inside out - and it is why
//! the multiply below is written out rather than looped over cleverly.

const std = @import("std");
const testing = std.testing;

pub const Mat4 = [16]f32;

pub const identity: Mat4 = .{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
};

/// `a` applied after `b`, which is what a program means by `projection *
/// view * model`.
pub fn multiply(a: Mat4, b: Mat4) Mat4 {
    var out: Mat4 = undefined;
    for (0..4) |column| {
        for (0..4) |row| {
            var sum: f32 = 0;
            for (0..4) |k| sum += a[k * 4 + row] * b[column * 4 + k];
            out[column * 4 + row] = sum;
        }
    }
    return out;
}

/// All of them, left to right: `chain(&.{ projection, view, model })`.
pub fn chain(matrices: []const Mat4) Mat4 {
    var out: Mat4 = identity;
    for (matrices) |m| out = multiply(out, m);
    return out;
}

/// A box of world space onto the unit cube. What a 2D program uses, with
/// `top` and `bottom` the way round that puts the origin where it wants it.
pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
    return .{
        2 / (right - left),               0,                                0,                            0,
        0,                                2 / (top - bottom),               0,                            0,
        0,                                0,                                -2 / (far - near),            0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1,
    };
}

/// The other one: things further away get smaller. `fovy` is in radians and
/// measures the whole vertical angle, not half of it.
pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const focal = 1 / @tan(fovy / 2);
    return .{
        focal / aspect, 0,     0,                               0,
        0,              focal, 0,                               0,
        0,              0,     (far + near) / (near - far),     -1,
        0,              0,     (2 * far * near) / (near - far), 0,
    };
}

pub fn translate(x: f32, y: f32, z: f32) Mat4 {
    return .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        x, y, z, 1,
    };
}

pub fn scale(x: f32, y: f32, z: f32) Mat4 {
    return .{
        x, 0, 0, 0,
        0, y, 0, 0,
        0, 0, z, 0,
        0, 0, 0, 1,
    };
}

pub fn rotateX(radians: f32) Mat4 {
    const s = @sin(radians);
    const c = @cos(radians);
    return .{
        1, 0,  0, 0,
        0, c,  s, 0,
        0, -s, c, 0,
        0, 0,  0, 1,
    };
}

pub fn rotateY(radians: f32) Mat4 {
    const s = @sin(radians);
    const c = @cos(radians);
    return .{
        c, 0, -s, 0,
        0, 1, 0,  0,
        s, 0, c,  0,
        0, 0, 0,  1,
    };
}

pub fn rotateZ(radians: f32) Mat4 {
    const s = @sin(radians);
    const c = @cos(radians);
    return .{
        c,  s, 0, 0,
        -s, c, 0, 0,
        0,  0, 1, 0,
        0,  0, 0, 1,
    };
}

/// A point through a matrix, which is what the driver's vertex stage does
/// and what these tests check against by hand.
pub fn transform(m: Mat4, v: [4]f32) [4]f32 {
    var out: [4]f32 = .{ 0, 0, 0, 0 };
    for (0..4) |row| {
        for (0..4) |column| out[row] += m[column * 4 + row] * v[column];
    }
    return out;
}

test "identity leaves a point where it was" {
    const p = transform(identity, .{ 1, 2, 3, 1 });
    try testing.expectEqual([4]f32{ 1, 2, 3, 1 }, p);
}

test "the translation is in the last column, not the last row" {
    const m = translate(5, 6, 7);
    try testing.expectEqual(@as(f32, 5), m[12]);
    const p = transform(m, .{ 1, 1, 1, 1 });
    try testing.expectEqual([4]f32{ 6, 7, 8, 1 }, p);
}

test "the order of a chain is right to left" {
    // Scale first, then translate: the translation is not scaled.
    const m = chain(&.{ translate(10, 0, 0), scale(2, 2, 2) });
    const p = transform(m, .{ 1, 0, 0, 1 });
    try testing.expectEqual(@as(f32, 12), p[0]);

    // The other way round, it is.
    const n = chain(&.{ scale(2, 2, 2), translate(10, 0, 0) });
    try testing.expectEqual(@as(f32, 22), transform(n, .{ 1, 0, 0, 1 })[0]);
}

test "ortho puts the corners of its box on the corners of the cube" {
    const m = ortho(0, 100, 0, 50, -1, 1);
    const bottom_left = transform(m, .{ 0, 0, 0, 1 });
    const top_right = transform(m, .{ 100, 50, 0, 1 });
    try testing.expectApproxEqAbs(@as(f32, -1), bottom_left[0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, -1), bottom_left[1], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 1), top_right[0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 1), top_right[1], 0.0001);
}

test "perspective divides by distance" {
    const m = perspective(std.math.pi / 2.0, 1, 0.1, 100);
    const near = transform(m, .{ 1, 0, -1, 1 });
    const far = transform(m, .{ 1, 0, -4, 1 });

    // The same x, four times as far away, ends up a quarter as wide once the
    // divide by w has happened.
    try testing.expectApproxEqAbs(near[0] / near[3] / 4, far[0] / far[3], 0.0001);
    try testing.expectEqual(@as(f32, 1), near[3]);
}
