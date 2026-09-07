// SPDX-License-Identifier: CC0-1.0

//! The desktop OpenGL command table.
//!
//! Everything declared without a `?` is in OpenGL 3.3 core, so a 3.3 context
//! fills the table completely and `load` either works or names the command
//! that was missing. Everything declared with one arrived later - 4.2 storage,
//! 4.3 debug output and compute, 4.4 persistent buffers - and is `null` on a
//! context that has not got it, which is the version check happening at the
//! call site, in the type system, rather than in a comment.
//!
//! 3.3 is the line because it is where the modern API stops moving: vertex
//! array objects, instancing, samplers and explicit attribute locations are
//! all in it, it is what macOS froze at, and it is what a driver from the
//! last fifteen years has. A program that needs less can declare its own
//! table with fewer fields - the loader does not care where the struct came
//! from - and a program that needs more can add optional fields to a copy of
//! this one.
//!
//! Compatibility-profile commands are not here at all. `glBegin`,
//! `glMatrixMode` and the rest still load on Windows and on a compatibility
//! context, and nothing in this library will help you use them.
//!
//! ```zig
//! var api: gl.Api = undefined;
//! try api.load(glfwGetProcAddress);
//!
//! api.clearColor(0.1, 0.1, 0.12, 1);
//! api.clear(c.color_buffer_bit | c.depth_buffer_bit);
//! api.drawArrays(c.triangles, 0, 3);
//! ```

const std = @import("std");
const testing = std.testing;

const enums = @import("enums.zig");
const ext = @import("extensions.zig");
const loader = @import("loader.zig");
const types = @import("types.zig");
const versions = @import("version.zig");

const Bitfield = types.Bitfield;
const Boolean = types.Boolean;
const Char = types.Char;
const Clampf = types.Clampf;
const Double = types.Double;
const Enum = types.Enum;
const Float = types.Float;
const Int = types.Int;
const Intptr = types.Intptr;
const Sizei = types.Sizei;
const Sizeiptr = types.Sizeiptr;
const Sync = types.Sync;
const Uint = types.Uint;
const Uint64 = types.Uint64;

/// One context's entry points. Fill it with `load`, keep it for as long as
/// the context lives, and pass it around by pointer: it is a few kilobytes of
/// function pointers and there is one set per context, not one per program.
pub const Api = struct {
    // ---------------------------------------------------------------------
    // Asking the context about itself
    // ---------------------------------------------------------------------

    getString: *const fn (name: Enum) callconv(.c) ?[*:0]const Char,
    getStringi: *const fn (name: Enum, index: Uint) callconv(.c) ?[*:0]const Char,
    getError: *const fn () callconv(.c) Enum,
    getIntegerv: *const fn (pname: Enum, data: [*]Int) callconv(.c) void,
    getIntegeri_v: *const fn (target: Enum, index: Uint, data: [*]Int) callconv(.c) void,
    getFloatv: *const fn (pname: Enum, data: [*]Float) callconv(.c) void,
    getBooleanv: *const fn (pname: Enum, data: [*]Boolean) callconv(.c) void,

    // ---------------------------------------------------------------------
    // The state a draw is made under
    // ---------------------------------------------------------------------

    viewport: *const fn (x: Int, y: Int, width: Sizei, height: Sizei) callconv(.c) void,
    scissor: *const fn (x: Int, y: Int, width: Sizei, height: Sizei) callconv(.c) void,
    enable: *const fn (capability: Enum) callconv(.c) void,
    disable: *const fn (capability: Enum) callconv(.c) void,
    enablei: *const fn (capability: Enum, index: Uint) callconv(.c) void,
    disablei: *const fn (capability: Enum, index: Uint) callconv(.c) void,
    isEnabled: *const fn (capability: Enum) callconv(.c) Boolean,
    hint: *const fn (target: Enum, mode: Enum) callconv(.c) void,
    pixelStorei: *const fn (pname: Enum, param: Int) callconv(.c) void,

    clear: *const fn (mask: Bitfield) callconv(.c) void,
    clearColor: *const fn (red: Clampf, green: Clampf, blue: Clampf, alpha: Clampf) callconv(.c) void,
    clearDepth: *const fn (depth: Double) callconv(.c) void,
    clearStencil: *const fn (s: Int) callconv(.c) void,
    clearBufferfv: *const fn (buffer: Enum, draw_buffer: Int, value: [*]const Float) callconv(.c) void,
    clearBufferiv: *const fn (buffer: Enum, draw_buffer: Int, value: [*]const Int) callconv(.c) void,
    clearBufferuiv: *const fn (buffer: Enum, draw_buffer: Int, value: [*]const Uint) callconv(.c) void,
    clearBufferfi: *const fn (buffer: Enum, draw_buffer: Int, depth: Float, stencil: Int) callconv(.c) void,

    colorMask: *const fn (red: Boolean, green: Boolean, blue: Boolean, alpha: Boolean) callconv(.c) void,
    depthMask: *const fn (flag: Boolean) callconv(.c) void,
    depthFunc: *const fn (func: Enum) callconv(.c) void,
    depthRange: *const fn (near: Double, far: Double) callconv(.c) void,
    stencilMask: *const fn (mask: Uint) callconv(.c) void,
    stencilMaskSeparate: *const fn (face: Enum, mask: Uint) callconv(.c) void,
    stencilFunc: *const fn (func: Enum, ref: Int, mask: Uint) callconv(.c) void,
    stencilFuncSeparate: *const fn (face: Enum, func: Enum, ref: Int, mask: Uint) callconv(.c) void,
    stencilOp: *const fn (sfail: Enum, dpfail: Enum, dppass: Enum) callconv(.c) void,
    stencilOpSeparate: *const fn (face: Enum, sfail: Enum, dpfail: Enum, dppass: Enum) callconv(.c) void,

    blendFunc: *const fn (src: Enum, dst: Enum) callconv(.c) void,
    blendFuncSeparate: *const fn (src_rgb: Enum, dst_rgb: Enum, src_alpha: Enum, dst_alpha: Enum) callconv(.c) void,
    blendEquation: *const fn (mode: Enum) callconv(.c) void,
    blendEquationSeparate: *const fn (mode_rgb: Enum, mode_alpha: Enum) callconv(.c) void,
    blendColor: *const fn (red: Clampf, green: Clampf, blue: Clampf, alpha: Clampf) callconv(.c) void,

    cullFace: *const fn (mode: Enum) callconv(.c) void,
    frontFace: *const fn (mode: Enum) callconv(.c) void,
    polygonMode: *const fn (face: Enum, mode: Enum) callconv(.c) void,
    polygonOffset: *const fn (factor: Float, units: Float) callconv(.c) void,
    lineWidth: *const fn (width: Float) callconv(.c) void,
    pointSize: *const fn (size: Float) callconv(.c) void,
    sampleCoverage: *const fn (value: Float, invert: Boolean) callconv(.c) void,

    finish: *const fn () callconv(.c) void,
    flush: *const fn () callconv(.c) void,

    // ---------------------------------------------------------------------
    // Buffers
    // ---------------------------------------------------------------------

    genBuffers: *const fn (n: Sizei, buffers: [*]Uint) callconv(.c) void,
    deleteBuffers: *const fn (n: Sizei, buffers: [*]const Uint) callconv(.c) void,
    isBuffer: *const fn (buffer: Uint) callconv(.c) Boolean,
    bindBuffer: *const fn (target: Enum, buffer: Uint) callconv(.c) void,
    bindBufferBase: *const fn (target: Enum, index: Uint, buffer: Uint) callconv(.c) void,
    bindBufferRange: *const fn (target: Enum, index: Uint, buffer: Uint, offset: Intptr, size: Sizeiptr) callconv(.c) void,
    bufferData: *const fn (target: Enum, size: Sizeiptr, data: ?*const anyopaque, usage: Enum) callconv(.c) void,
    bufferSubData: *const fn (target: Enum, offset: Intptr, size: Sizeiptr, data: ?*const anyopaque) callconv(.c) void,
    getBufferSubData: *const fn (target: Enum, offset: Intptr, size: Sizeiptr, data: ?*anyopaque) callconv(.c) void,
    getBufferParameteriv: *const fn (target: Enum, pname: Enum, params: [*]Int) callconv(.c) void,
    copyBufferSubData: *const fn (
        read_target: Enum,
        write_target: Enum,
        read_offset: Intptr,
        write_offset: Intptr,
        size: Sizeiptr,
    ) callconv(.c) void,
    mapBuffer: *const fn (target: Enum, access: Enum) callconv(.c) ?*anyopaque,
    mapBufferRange: *const fn (target: Enum, offset: Intptr, length: Sizeiptr, access: Bitfield) callconv(.c) ?*anyopaque,
    flushMappedBufferRange: *const fn (target: Enum, offset: Intptr, length: Sizeiptr) callconv(.c) void,
    /// False means the contents were lost while they were mapped - a screen
    /// resolution change, a graphics device reset - and have to be uploaded
    /// again. It is not a formality.
    unmapBuffer: *const fn (target: Enum) callconv(.c) Boolean,

    // ---------------------------------------------------------------------
    // Vertex arrays and attributes
    // ---------------------------------------------------------------------

    genVertexArrays: *const fn (n: Sizei, arrays: [*]Uint) callconv(.c) void,
    deleteVertexArrays: *const fn (n: Sizei, arrays: [*]const Uint) callconv(.c) void,
    isVertexArray: *const fn (array: Uint) callconv(.c) Boolean,
    bindVertexArray: *const fn (array: Uint) callconv(.c) void,

    enableVertexAttribArray: *const fn (index: Uint) callconv(.c) void,
    disableVertexAttribArray: *const fn (index: Uint) callconv(.c) void,
    /// `pointer` is a byte offset into the bound `array_buffer`, not an
    /// address: see `types.offset`.
    vertexAttribPointer: *const fn (
        index: Uint,
        size: Int,
        kind: Enum,
        normalized: Boolean,
        stride: Sizei,
        pointer: ?*const anyopaque,
    ) callconv(.c) void,
    /// The integer form. An attribute declared `int` in the shader and fed
    /// through `vertexAttribPointer` arrives converted to float and wrong.
    vertexAttribIPointer: *const fn (
        index: Uint,
        size: Int,
        kind: Enum,
        stride: Sizei,
        pointer: ?*const anyopaque,
    ) callconv(.c) void,
    /// Zero for per-vertex, one for per-instance, n for per n instances.
    vertexAttribDivisor: *const fn (index: Uint, divisor: Uint) callconv(.c) void,
    getVertexAttribiv: *const fn (index: Uint, pname: Enum, params: [*]Int) callconv(.c) void,
    getVertexAttribfv: *const fn (index: Uint, pname: Enum, params: [*]Float) callconv(.c) void,
    vertexAttrib1f: *const fn (index: Uint, v0: Float) callconv(.c) void,
    vertexAttrib2f: *const fn (index: Uint, v0: Float, v1: Float) callconv(.c) void,
    vertexAttrib3f: *const fn (index: Uint, v0: Float, v1: Float, v2: Float) callconv(.c) void,
    vertexAttrib4f: *const fn (index: Uint, v0: Float, v1: Float, v2: Float, v3: Float) callconv(.c) void,
    vertexAttrib4fv: *const fn (index: Uint, v: [*]const Float) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Drawing
    // ---------------------------------------------------------------------

    drawArrays: *const fn (mode: Enum, first: Int, count: Sizei) callconv(.c) void,
    drawArraysInstanced: *const fn (mode: Enum, first: Int, count: Sizei, instances: Sizei) callconv(.c) void,
    drawElements: *const fn (mode: Enum, count: Sizei, kind: Enum, indices: ?*const anyopaque) callconv(.c) void,
    drawElementsInstanced: *const fn (
        mode: Enum,
        count: Sizei,
        kind: Enum,
        indices: ?*const anyopaque,
        instances: Sizei,
    ) callconv(.c) void,
    /// The same draw with a promise about which vertices it touches, which is
    /// what lets the driver upload only that part of the array.
    drawRangeElements: *const fn (
        mode: Enum,
        start: Uint,
        end: Uint,
        count: Sizei,
        kind: Enum,
        indices: ?*const anyopaque,
    ) callconv(.c) void,
    drawElementsBaseVertex: *const fn (
        mode: Enum,
        count: Sizei,
        kind: Enum,
        indices: ?*const anyopaque,
        base_vertex: Int,
    ) callconv(.c) void,
    multiDrawArrays: *const fn (mode: Enum, first: [*]const Int, count: [*]const Sizei, draw_count: Sizei) callconv(.c) void,
    primitiveRestartIndex: *const fn (index: Uint) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Shaders and programs
    // ---------------------------------------------------------------------

    createShader: *const fn (kind: Enum) callconv(.c) Uint,
    deleteShader: *const fn (shader: Uint) callconv(.c) void,
    isShader: *const fn (shader: Uint) callconv(.c) Boolean,
    /// `lengths` may be null, in which case each source is read to its NUL.
    shaderSource: *const fn (
        shader: Uint,
        count: Sizei,
        strings: [*]const [*:0]const Char,
        lengths: ?[*]const Int,
    ) callconv(.c) void,
    compileShader: *const fn (shader: Uint) callconv(.c) void,
    getShaderiv: *const fn (shader: Uint, pname: Enum, params: [*]Int) callconv(.c) void,
    getShaderInfoLog: *const fn (shader: Uint, buf_size: Sizei, length: ?*Sizei, info_log: [*]Char) callconv(.c) void,
    getShaderSource: *const fn (shader: Uint, buf_size: Sizei, length: ?*Sizei, source: [*]Char) callconv(.c) void,

    createProgram: *const fn () callconv(.c) Uint,
    deleteProgram: *const fn (program: Uint) callconv(.c) void,
    isProgram: *const fn (program: Uint) callconv(.c) Boolean,
    attachShader: *const fn (program: Uint, shader: Uint) callconv(.c) void,
    detachShader: *const fn (program: Uint, shader: Uint) callconv(.c) void,
    linkProgram: *const fn (program: Uint) callconv(.c) void,
    useProgram: *const fn (program: Uint) callconv(.c) void,
    validateProgram: *const fn (program: Uint) callconv(.c) void,
    getProgramiv: *const fn (program: Uint, pname: Enum, params: [*]Int) callconv(.c) void,
    getProgramInfoLog: *const fn (program: Uint, buf_size: Sizei, length: ?*Sizei, info_log: [*]Char) callconv(.c) void,

    getAttribLocation: *const fn (program: Uint, name: [*:0]const Char) callconv(.c) Int,
    bindAttribLocation: *const fn (program: Uint, index: Uint, name: [*:0]const Char) callconv(.c) void,
    getActiveAttrib: *const fn (
        program: Uint,
        index: Uint,
        buf_size: Sizei,
        length: ?*Sizei,
        size: *Int,
        kind: *Enum,
        name: [*]Char,
    ) callconv(.c) void,
    /// Minus one for a uniform the linker removed, which includes every
    /// uniform the shader does not actually read.
    getUniformLocation: *const fn (program: Uint, name: [*:0]const Char) callconv(.c) Int,
    getActiveUniform: *const fn (
        program: Uint,
        index: Uint,
        buf_size: Sizei,
        length: ?*Sizei,
        size: *Int,
        kind: *Enum,
        name: [*]Char,
    ) callconv(.c) void,
    getUniformBlockIndex: *const fn (program: Uint, name: [*:0]const Char) callconv(.c) Uint,
    uniformBlockBinding: *const fn (program: Uint, block: Uint, binding: Uint) callconv(.c) void,
    bindFragDataLocation: *const fn (program: Uint, color: Uint, name: [*:0]const Char) callconv(.c) void,
    getFragDataLocation: *const fn (program: Uint, name: [*:0]const Char) callconv(.c) Int,

    uniform1f: *const fn (location: Int, v0: Float) callconv(.c) void,
    uniform2f: *const fn (location: Int, v0: Float, v1: Float) callconv(.c) void,
    uniform3f: *const fn (location: Int, v0: Float, v1: Float, v2: Float) callconv(.c) void,
    uniform4f: *const fn (location: Int, v0: Float, v1: Float, v2: Float, v3: Float) callconv(.c) void,
    uniform1i: *const fn (location: Int, v0: Int) callconv(.c) void,
    uniform2i: *const fn (location: Int, v0: Int, v1: Int) callconv(.c) void,
    uniform3i: *const fn (location: Int, v0: Int, v1: Int, v2: Int) callconv(.c) void,
    uniform4i: *const fn (location: Int, v0: Int, v1: Int, v2: Int, v3: Int) callconv(.c) void,
    uniform1ui: *const fn (location: Int, v0: Uint) callconv(.c) void,
    uniform1fv: *const fn (location: Int, count: Sizei, value: [*]const Float) callconv(.c) void,
    uniform2fv: *const fn (location: Int, count: Sizei, value: [*]const Float) callconv(.c) void,
    uniform3fv: *const fn (location: Int, count: Sizei, value: [*]const Float) callconv(.c) void,
    uniform4fv: *const fn (location: Int, count: Sizei, value: [*]const Float) callconv(.c) void,
    uniform1iv: *const fn (location: Int, count: Sizei, value: [*]const Int) callconv(.c) void,
    uniform2iv: *const fn (location: Int, count: Sizei, value: [*]const Int) callconv(.c) void,
    uniform3iv: *const fn (location: Int, count: Sizei, value: [*]const Int) callconv(.c) void,
    uniform4iv: *const fn (location: Int, count: Sizei, value: [*]const Int) callconv(.c) void,
    /// `transpose` is `gl_false` for the column-major matrices every maths
    /// library on this side of the API produces.
    uniformMatrix2fv: *const fn (location: Int, count: Sizei, transpose: Boolean, value: [*]const Float) callconv(.c) void,
    uniformMatrix3fv: *const fn (location: Int, count: Sizei, transpose: Boolean, value: [*]const Float) callconv(.c) void,
    uniformMatrix4fv: *const fn (location: Int, count: Sizei, transpose: Boolean, value: [*]const Float) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Textures and samplers
    // ---------------------------------------------------------------------

    genTextures: *const fn (n: Sizei, textures: [*]Uint) callconv(.c) void,
    deleteTextures: *const fn (n: Sizei, textures: [*]const Uint) callconv(.c) void,
    isTexture: *const fn (texture: Uint) callconv(.c) Boolean,
    bindTexture: *const fn (target: Enum, texture: Uint) callconv(.c) void,
    activeTexture: *const fn (texture: Enum) callconv(.c) void,
    generateMipmap: *const fn (target: Enum) callconv(.c) void,

    /// `internal_format` is an `Int` here and an `Enum` everywhere else. It is
    /// not a mistake in this table: the command predates sized formats, when
    /// the argument was a component count.
    texImage2D: *const fn (
        target: Enum,
        level: Int,
        internal_format: Int,
        width: Sizei,
        height: Sizei,
        border: Int,
        format: Enum,
        kind: Enum,
        pixels: ?*const anyopaque,
    ) callconv(.c) void,
    texImage3D: *const fn (
        target: Enum,
        level: Int,
        internal_format: Int,
        width: Sizei,
        height: Sizei,
        depth: Sizei,
        border: Int,
        format: Enum,
        kind: Enum,
        pixels: ?*const anyopaque,
    ) callconv(.c) void,
    texSubImage2D: *const fn (
        target: Enum,
        level: Int,
        xoffset: Int,
        yoffset: Int,
        width: Sizei,
        height: Sizei,
        format: Enum,
        kind: Enum,
        pixels: ?*const anyopaque,
    ) callconv(.c) void,
    texSubImage3D: *const fn (
        target: Enum,
        level: Int,
        xoffset: Int,
        yoffset: Int,
        zoffset: Int,
        width: Sizei,
        height: Sizei,
        depth: Sizei,
        format: Enum,
        kind: Enum,
        pixels: ?*const anyopaque,
    ) callconv(.c) void,
    copyTexImage2D: *const fn (
        target: Enum,
        level: Int,
        internal_format: Enum,
        x: Int,
        y: Int,
        width: Sizei,
        height: Sizei,
        border: Int,
    ) callconv(.c) void,
    copyTexSubImage2D: *const fn (
        target: Enum,
        level: Int,
        xoffset: Int,
        yoffset: Int,
        x: Int,
        y: Int,
        width: Sizei,
        height: Sizei,
    ) callconv(.c) void,
    compressedTexImage2D: *const fn (
        target: Enum,
        level: Int,
        internal_format: Enum,
        width: Sizei,
        height: Sizei,
        border: Int,
        image_size: Sizei,
        data: ?*const anyopaque,
    ) callconv(.c) void,
    compressedTexSubImage2D: *const fn (
        target: Enum,
        level: Int,
        xoffset: Int,
        yoffset: Int,
        width: Sizei,
        height: Sizei,
        format: Enum,
        image_size: Sizei,
        data: ?*const anyopaque,
    ) callconv(.c) void,
    getTexImage: *const fn (target: Enum, level: Int, format: Enum, kind: Enum, pixels: ?*anyopaque) callconv(.c) void,
    texParameteri: *const fn (target: Enum, pname: Enum, param: Int) callconv(.c) void,
    texParameterf: *const fn (target: Enum, pname: Enum, param: Float) callconv(.c) void,
    texParameteriv: *const fn (target: Enum, pname: Enum, params: [*]const Int) callconv(.c) void,
    texParameterfv: *const fn (target: Enum, pname: Enum, params: [*]const Float) callconv(.c) void,
    getTexParameteriv: *const fn (target: Enum, pname: Enum, params: [*]Int) callconv(.c) void,
    getTexParameterfv: *const fn (target: Enum, pname: Enum, params: [*]Float) callconv(.c) void,
    texBuffer: *const fn (target: Enum, internal_format: Enum, buffer: Uint) callconv(.c) void,

    genSamplers: *const fn (n: Sizei, samplers: [*]Uint) callconv(.c) void,
    deleteSamplers: *const fn (n: Sizei, samplers: [*]const Uint) callconv(.c) void,
    bindSampler: *const fn (unit: Uint, sampler: Uint) callconv(.c) void,
    samplerParameteri: *const fn (sampler: Uint, pname: Enum, param: Int) callconv(.c) void,
    samplerParameterf: *const fn (sampler: Uint, pname: Enum, param: Float) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Framebuffers and renderbuffers
    // ---------------------------------------------------------------------

    genFramebuffers: *const fn (n: Sizei, framebuffers: [*]Uint) callconv(.c) void,
    deleteFramebuffers: *const fn (n: Sizei, framebuffers: [*]const Uint) callconv(.c) void,
    isFramebuffer: *const fn (framebuffer: Uint) callconv(.c) Boolean,
    bindFramebuffer: *const fn (target: Enum, framebuffer: Uint) callconv(.c) void,
    /// Anything but `framebuffer_complete` means the next draw is silently
    /// dropped, so this is worth calling every time a framebuffer is built.
    checkFramebufferStatus: *const fn (target: Enum) callconv(.c) Enum,
    framebufferTexture2D: *const fn (
        target: Enum,
        attachment: Enum,
        tex_target: Enum,
        texture: Uint,
        level: Int,
    ) callconv(.c) void,
    framebufferTextureLayer: *const fn (
        target: Enum,
        attachment: Enum,
        texture: Uint,
        level: Int,
        layer: Int,
    ) callconv(.c) void,
    framebufferRenderbuffer: *const fn (
        target: Enum,
        attachment: Enum,
        renderbuffer_target: Enum,
        renderbuffer: Uint,
    ) callconv(.c) void,
    getFramebufferAttachmentParameteriv: *const fn (
        target: Enum,
        attachment: Enum,
        pname: Enum,
        params: [*]Int,
    ) callconv(.c) void,
    blitFramebuffer: *const fn (
        src_x0: Int,
        src_y0: Int,
        src_x1: Int,
        src_y1: Int,
        dst_x0: Int,
        dst_y0: Int,
        dst_x1: Int,
        dst_y1: Int,
        mask: Bitfield,
        filter: Enum,
    ) callconv(.c) void,
    drawBuffer: *const fn (buf: Enum) callconv(.c) void,
    drawBuffers: *const fn (n: Sizei, bufs: [*]const Enum) callconv(.c) void,
    readBuffer: *const fn (src: Enum) callconv(.c) void,
    readPixels: *const fn (
        x: Int,
        y: Int,
        width: Sizei,
        height: Sizei,
        format: Enum,
        kind: Enum,
        pixels: ?*anyopaque,
    ) callconv(.c) void,

    genRenderbuffers: *const fn (n: Sizei, renderbuffers: [*]Uint) callconv(.c) void,
    deleteRenderbuffers: *const fn (n: Sizei, renderbuffers: [*]const Uint) callconv(.c) void,
    isRenderbuffer: *const fn (renderbuffer: Uint) callconv(.c) Boolean,
    bindRenderbuffer: *const fn (target: Enum, renderbuffer: Uint) callconv(.c) void,
    renderbufferStorage: *const fn (target: Enum, internal_format: Enum, width: Sizei, height: Sizei) callconv(.c) void,
    renderbufferStorageMultisample: *const fn (
        target: Enum,
        samples: Sizei,
        internal_format: Enum,
        width: Sizei,
        height: Sizei,
    ) callconv(.c) void,
    getRenderbufferParameteriv: *const fn (target: Enum, pname: Enum, params: [*]Int) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Queries, sync objects and transform feedback
    // ---------------------------------------------------------------------

    genQueries: *const fn (n: Sizei, ids: [*]Uint) callconv(.c) void,
    deleteQueries: *const fn (n: Sizei, ids: [*]const Uint) callconv(.c) void,
    beginQuery: *const fn (target: Enum, id: Uint) callconv(.c) void,
    endQuery: *const fn (target: Enum) callconv(.c) void,
    getQueryObjectiv: *const fn (id: Uint, pname: Enum, params: [*]Int) callconv(.c) void,
    getQueryObjectuiv: *const fn (id: Uint, pname: Enum, params: [*]Uint) callconv(.c) void,

    /// A marker in the command stream, not a point in time: it becomes
    /// signalled when everything issued before it has finished.
    fenceSync: *const fn (condition: Enum, flags: Bitfield) callconv(.c) Sync,
    clientWaitSync: *const fn (sync: Sync, flags: Bitfield, timeout: Uint64) callconv(.c) Enum,
    waitSync: *const fn (sync: Sync, flags: Bitfield, timeout: Uint64) callconv(.c) void,
    deleteSync: *const fn (sync: Sync) callconv(.c) void,
    isSync: *const fn (sync: Sync) callconv(.c) Boolean,

    beginTransformFeedback: *const fn (primitive_mode: Enum) callconv(.c) void,
    endTransformFeedback: *const fn () callconv(.c) void,
    transformFeedbackVaryings: *const fn (
        program: Uint,
        count: Sizei,
        varyings: [*]const [*:0]const Char,
        buffer_mode: Enum,
    ) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Past 3.3, and so optional
    // ---------------------------------------------------------------------

    /// 4.2. Allocates every level at once and makes the texture immutable,
    /// which is the difference between a complete texture and one that is
    /// silently unusable because a level was the wrong size.
    texStorage2D: ?*const fn (
        target: Enum,
        levels: Sizei,
        internal_format: Enum,
        width: Sizei,
        height: Sizei,
    ) callconv(.c) void,
    /// 4.2.
    texStorage3D: ?*const fn (
        target: Enum,
        levels: Sizei,
        internal_format: Enum,
        width: Sizei,
        height: Sizei,
        depth: Sizei,
    ) callconv(.c) void,
    /// 4.4. A buffer whose storage never moves, so it can stay mapped while
    /// the GPU reads it.
    bufferStorage: ?*const fn (target: Enum, size: Sizeiptr, data: ?*const anyopaque, flags: Bitfield) callconv(.c) void,
    /// 4.3, or `GL_KHR_debug`, which is where most drivers have it. Worth
    /// asking for even on a driver that has it as an extension: it turns
    /// every silent mistake into a line of text.
    debugMessageCallback: ?*const fn (callback: ?types.DebugProc, user_param: ?*const anyopaque) callconv(.c) void,
    /// 4.3. What to report and what to keep quiet about.
    debugMessageControl: ?*const fn (
        source: Enum,
        kind: Enum,
        severity: Enum,
        count: Sizei,
        ids: ?[*]const Uint,
        enabled: Boolean,
    ) callconv(.c) void,
    /// 4.3. A message of your own, in the same stream as the driver's.
    debugMessageInsert: ?*const fn (
        source: Enum,
        kind: Enum,
        id: Uint,
        severity: Enum,
        length: Sizei,
        buf: [*]const Char,
    ) callconv(.c) void,
    /// 4.3. A name for an object, which is what turns "buffer 7" in a capture
    /// into "terrain vertices".
    objectLabel: ?*const fn (identifier: Enum, name: Uint, length: Sizei, label: ?[*]const Char) callconv(.c) void,
    /// 4.3.
    pushDebugGroup: ?*const fn (source: Enum, id: Uint, length: Sizei, message: [*]const Char) callconv(.c) void,
    /// 4.3.
    popDebugGroup: ?*const fn () callconv(.c) void,
    /// 4.3.
    dispatchCompute: ?*const fn (groups_x: Uint, groups_y: Uint, groups_z: Uint) callconv(.c) void,
    /// 4.2. Without one of these, a compute shader's writes are visible to
    /// the next draw whenever the driver feels like it.
    memoryBarrier: ?*const fn (barriers: Bitfield) callconv(.c) void,
    /// 4.2.
    bindImageTexture: ?*const fn (
        unit: Uint,
        texture: Uint,
        level: Int,
        layered: Boolean,
        layer: Int,
        access: Enum,
        format: Enum,
    ) callconv(.c) void,
    /// 4.3. Says the contents of an attachment are finished with, which on a
    /// tiled renderer saves writing them back to memory.
    invalidateFramebuffer: ?*const fn (target: Enum, count: Sizei, attachments: [*]const Enum) callconv(.c) void,
    /// 4.1, or `GL_ARB_get_program_binary`. A linked program in a blob, to be
    /// put back with `programBinary` next time the application starts.
    getProgramBinary: ?*const fn (
        program: Uint,
        buf_size: Sizei,
        length: ?*Sizei,
        binary_format: *Enum,
        binary: ?*anyopaque,
    ) callconv(.c) void,
    /// 4.1. Fails whenever the driver has been updated, so keep the source.
    programBinary: ?*const fn (
        program: Uint,
        binary_format: Enum,
        binary: ?*const anyopaque,
        length: Sizei,
    ) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Loading, and the few things worth wrapping
    // ---------------------------------------------------------------------

    /// Plain `gl` names, and no extension suffixes: on the desktop, every
    /// command above is core, and an `ARB` or `EXT` entry point beside it is
    /// not always the same function. See `loader.Options.suffixes`.
    pub const options: loader.Options = .{ .prefix = "gl" };

    /// Fill the table from a resolver. See `loader.load`.
    pub fn load(self: *Api, resolver: anytype) loader.Error!void {
        return loader.loadWith(self, resolver, options);
    }

    /// Fill it and report what was there, rather than failing. See
    /// `loader.tryLoad`.
    pub fn tryLoad(self: *Api, resolver: anytype) loader.Status {
        return loader.tryLoad(self, resolver, options);
    }

    /// `getString` as a Zig slice, or null if the context has no such string.
    pub fn string(self: *const Api, name: Enum) ?[]const u8 {
        return std.mem.span(self.getString(name) orelse return null);
    }

    /// The context's version, read from `GL_VERSION`.
    pub fn version(self: *const Api) versions.ParseError!versions.Version {
        return versions.Version.parse(self.string(enums.version) orelse "");
    }

    /// The shading language version the driver reports, which is not always
    /// the one `versions.Version.glsl` predicts - a driver may offer a newer
    /// language than the context's version implies.
    pub fn glslVersion(self: *const Api) versions.ParseError!versions.Glsl {
        return versions.Glsl.parse(self.string(enums.shading_language_version) orelse "");
    }

    /// The extensions this context has, gathered into `buffer` one name at a
    /// time. A core profile has no flat extension string, so this is the only
    /// way to ask; 512 is a roomy buffer and a driver that reports more will
    /// simply have the rest left out.
    pub fn extensionNames(self: *const Api, buffer: [][]const u8) ext.Set {
        var total: [1]Int = .{0};
        self.getIntegerv(enums.num_extensions, &total);

        var found: usize = 0;
        var index: Uint = 0;
        while (index < @as(Uint, @intCast(@max(total[0], 0))) and found < buffer.len) : (index += 1) {
            const name = self.getStringi(enums.extensions, index) orelse continue;
            buffer[found] = std.mem.span(name);
            found += 1;
        }
        return .{ .names = buffer[0..found] };
    }

    /// Drain the error queue and return the first error in it, or null.
    ///
    /// The queue matters: GL records errors and hands them back one call at a
    /// time, so a program that reads a single `getError` after a frame is
    /// reading the oldest mistake, not the newest, and leaves the rest to
    /// turn up later.
    pub fn checkError(self: *const Api) ?Enum {
        var first: Enum = enums.no_error;
        while (true) {
            const code = self.getError();
            if (code == enums.no_error) break;
            if (first == enums.no_error) first = code;
        }
        return if (first == enums.no_error) null else first;
    }
};

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

/// A driver that answers for every command, and answers usefully for the few
/// the table's own methods call.
const FakeDriver = struct {
    const reported = [_][:0]const u8{
        "GL_ARB_debug_output",
        "GL_KHR_debug",
        "GL_EXT_texture_filter_anisotropic",
    };

    pub fn glGetString(name: Enum) callconv(.c) ?[*:0]const Char {
        return switch (name) {
            enums.version => "4.6.0 Fluxion 1.0",
            enums.shading_language_version => "4.60 Fluxion",
            enums.renderer => "Not A Graphics Card",
            else => null,
        };
    }

    pub fn glGetStringi(name: Enum, index: Uint) callconv(.c) ?[*:0]const Char {
        if (name != enums.extensions or index >= reported.len) return null;
        return reported[index].ptr;
    }

    pub fn glGetIntegerv(pname: Enum, data: [*]Int) callconv(.c) void {
        data[0] = switch (pname) {
            enums.num_extensions => @intCast(reported.len),
            enums.max_texture_size => 16384,
            else => 0,
        };
    }

    pub fn glGetError() callconv(.c) Enum {
        return enums.no_error;
    }

    fn stub() callconv(.c) void {}

    fn get(name: [*:0]const u8) callconv(.c) ?loader.Proc {
        const wanted = std.mem.span(name);
        inline for (@typeInfo(FakeDriver).@"struct".decls) |decl| {
            if (std.mem.eql(u8, decl.name, wanted)) return @ptrCast(&@field(FakeDriver, decl.name));
        }
        return @ptrCast(&stub);
    }
};

test "the whole table loads, and every signature casts" {
    var api: Api = undefined;
    const status = api.tryLoad(FakeDriver.get);

    try testing.expect(status.ok());
    try testing.expectEqual(status.requested, status.loaded);
    try testing.expectEqual(0, status.absent);
    try testing.expect(status.requested > 150);
}

test "a driver that stopped at 3.3" {
    const Older = struct {
        fn get(name: [*:0]const u8) callconv(.c) ?loader.Proc {
            const wanted = std.mem.span(name);
            // Everything that arrived after 3.3 is spelled with a version
            // this driver has not got; the rest it answers for.
            for ([_][]const u8{ "glTexStorage2D", "glDispatchCompute", "glDebugMessageCallback" }) |absent| {
                if (std.mem.eql(u8, absent, wanted)) return null;
            }
            return FakeDriver.get(name);
        }
    };

    var api: Api = undefined;
    const status = api.tryLoad(Older.get);

    // Which is not a failure: the core of the table is there.
    try testing.expect(status.ok());
    try testing.expectEqual(3, status.absent);
    try testing.expectEqual(null, api.texStorage2D);
    try testing.expectEqual(null, api.dispatchCompute);
    try testing.expect(api.getProgramBinary != null);

    // And the missing ones are unusable without saying so out loud.
    if (api.dispatchCompute) |dispatch| {
        dispatch(1, 1, 1);
        return error.TestUnexpectedResult;
    }
}

test "a driver too old for the table" {
    const Ancient = struct {
        fn get(name: [*:0]const u8) callconv(.c) ?loader.Proc {
            if (std.mem.eql(u8, std.mem.span(name), "glBindVertexArray")) return null;
            return FakeDriver.get(name);
        }
    };

    var api: Api = undefined;
    try testing.expectError(error.CommandMissing, api.load(Ancient.get));
    try testing.expectEqualStrings("glBindVertexArray", api.tryLoad(Ancient.get).missing.?);
}

test "what the table asks the driver for" {
    const asked = comptime loader.names(Api);
    try testing.expectEqualStrings("glGetString", asked[0]);
    inline for (asked) |name| {
        try testing.expect(std.mem.startsWith(u8, name, "gl"));
        try testing.expect(std.ascii.isUpper(name[2]));
    }

    // The commands that are optional are the ones past 3.3, and nothing else.
    try testing.expect(@typeInfo(@FieldType(Api, "dispatchCompute")) == .optional);
    try testing.expect(@typeInfo(@FieldType(Api, "texStorage2D")) == .optional);
    try testing.expect(@typeInfo(@FieldType(Api, "drawArrays")) != .optional);
    try testing.expect(@typeInfo(@FieldType(Api, "bindVertexArray")) != .optional);
    try testing.expect(@typeInfo(@FieldType(Api, "vertexAttribDivisor")) != .optional);
}

test "the questions a program asks at startup" {
    var api: Api = undefined;
    try api.load(FakeDriver.get);

    const context = try api.version();
    try testing.expectEqual(versions.Api.gl, context.api);
    try testing.expect(context.atLeast(3, 3));
    try testing.expectEqual(460, (try api.glslVersion()).directive());
    try testing.expectEqualStrings("Not A Graphics Card", api.string(enums.renderer).?);
    try testing.expectEqual(null, api.string(enums.vendor));

    var buffer: [64][]const u8 = undefined;
    const have = api.extensionNames(&buffer);
    try testing.expectEqual(3, have.count());
    try testing.expect(have.has("KHR_debug"));
    try testing.expect(have.has("GL_ARB_debug_output"));
    try testing.expectEqualStrings("GL_ARB_bindless_texture", have.missing(&.{"GL_ARB_bindless_texture"}).?);

    var limits: [1]Int = .{0};
    api.getIntegerv(enums.max_texture_size, &limits);
    try testing.expectEqual(16384, limits[0]);

    try testing.expectEqual(null, api.checkError());
}
