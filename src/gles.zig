// SPDX-License-Identifier: CC0-1.0

//! The OpenGL ES command table.
//!
//! Everything declared without a `?` is in OpenGL ES 2.0, which is the floor
//! of anything that still runs: every phone, every browser through WebGL,
//! every set-top box, and ANGLE on Windows. Everything declared with one
//! arrived in ES 3.0 or later - vertex array objects, instancing, 3D
//! textures, sync objects, uniform blocks - and is `null` where the driver
//! has not got it.
//!
//! ES is not a subset of the desktop API with the same spelling. `glClearDepthf`
//! takes a float where desktop takes a double, `glReadPixels` is allowed to
//! refuse every format but one, there is no `glPolygonMode` and there never
//! will be, and the shading language is a different language with its own
//! version numbering. Those differences are why this is a separate table
//! rather than the other one with fields removed: a program that means ES
//! should say so, and get a compile error where it strays.
//!
//! What is the same is the loading. These are `gl` names, resolved by the
//! same `loader` from the same `getProcAddress` - `eglGetProcAddress`, or
//! whatever GLFW and SDL hand over for an ES context.
//!
//! ```zig
//! var api: gles.Api = undefined;
//! try api.load(eglGetProcAddress);
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
const Enum = types.Enum;
const Float = types.Float;
const Int = types.Int;
const Intptr = types.Intptr;
const Sizei = types.Sizei;
const Sizeiptr = types.Sizeiptr;
const Sync = types.Sync;
const Uint = types.Uint;
const Uint64 = types.Uint64;

/// One ES context's entry points.
pub const Api = struct {
    // ---------------------------------------------------------------------
    // Asking the context about itself
    // ---------------------------------------------------------------------

    getString: *const fn (name: Enum) callconv(.c) ?[*:0]const Char,
    getError: *const fn () callconv(.c) Enum,
    getIntegerv: *const fn (pname: Enum, data: [*]Int) callconv(.c) void,
    getFloatv: *const fn (pname: Enum, data: [*]Float) callconv(.c) void,
    getBooleanv: *const fn (pname: Enum, data: [*]Boolean) callconv(.c) void,
    /// What precision the compiler actually offers for a `mediump` float,
    /// which on ES 2.0 is a real question with a real answer.
    getShaderPrecisionFormat: *const fn (
        shader_type: Enum,
        precision_type: Enum,
        range: [*]Int,
        precision: *Int,
    ) callconv(.c) void,

    // ---------------------------------------------------------------------
    // The state a draw is made under
    // ---------------------------------------------------------------------

    viewport: *const fn (x: Int, y: Int, width: Sizei, height: Sizei) callconv(.c) void,
    scissor: *const fn (x: Int, y: Int, width: Sizei, height: Sizei) callconv(.c) void,
    enable: *const fn (capability: Enum) callconv(.c) void,
    disable: *const fn (capability: Enum) callconv(.c) void,
    isEnabled: *const fn (capability: Enum) callconv(.c) Boolean,
    hint: *const fn (target: Enum, mode: Enum) callconv(.c) void,
    pixelStorei: *const fn (pname: Enum, param: Int) callconv(.c) void,

    clear: *const fn (mask: Bitfield) callconv(.c) void,
    clearColor: *const fn (red: Clampf, green: Clampf, blue: Clampf, alpha: Clampf) callconv(.c) void,
    /// A float, where desktop GL takes a double. There is no `glClearDepth`
    /// in ES, and asking for one is the commonest way a ported program fails
    /// to load.
    clearDepthf: *const fn (depth: Clampf) callconv(.c) void,
    clearStencil: *const fn (s: Int) callconv(.c) void,

    colorMask: *const fn (red: Boolean, green: Boolean, blue: Boolean, alpha: Boolean) callconv(.c) void,
    depthMask: *const fn (flag: Boolean) callconv(.c) void,
    depthFunc: *const fn (func: Enum) callconv(.c) void,
    depthRangef: *const fn (near: Clampf, far: Clampf) callconv(.c) void,
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
    polygonOffset: *const fn (factor: Float, units: Float) callconv(.c) void,
    lineWidth: *const fn (width: Float) callconv(.c) void,
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
    bufferData: *const fn (target: Enum, size: Sizeiptr, data: ?*const anyopaque, usage: Enum) callconv(.c) void,
    bufferSubData: *const fn (target: Enum, offset: Intptr, size: Sizeiptr, data: ?*const anyopaque) callconv(.c) void,
    getBufferParameteriv: *const fn (target: Enum, pname: Enum, params: [*]Int) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Vertex attributes
    // ---------------------------------------------------------------------

    enableVertexAttribArray: *const fn (index: Uint) callconv(.c) void,
    disableVertexAttribArray: *const fn (index: Uint) callconv(.c) void,
    /// On ES 2.0 `pointer` may be a real pointer into client memory, with no
    /// buffer bound at all - the one place ES is more permissive than a
    /// desktop core profile. With a buffer bound it is a byte offset, as on
    /// the desktop: see `types.offset`.
    vertexAttribPointer: *const fn (
        index: Uint,
        size: Int,
        kind: Enum,
        normalized: Boolean,
        stride: Sizei,
        pointer: ?*const anyopaque,
    ) callconv(.c) void,
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
    /// On ES 2.0 the index type is `unsigned_byte` or `unsigned_short` only.
    /// `unsigned_int` needs ES 3.0 or `GL_OES_element_index_uint`, and a mesh
    /// with more than 65536 vertices is where a port first notices.
    drawElements: *const fn (mode: Enum, count: Sizei, kind: Enum, indices: ?*const anyopaque) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Shaders and programs
    // ---------------------------------------------------------------------

    createShader: *const fn (kind: Enum) callconv(.c) Uint,
    deleteShader: *const fn (shader: Uint) callconv(.c) void,
    isShader: *const fn (shader: Uint) callconv(.c) Boolean,
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
    /// Pre-compiled shaders, in a format the driver chose. The reason ES has
    /// this and the desktop does not is that an ES device may ship without a
    /// compiler at all - see `shader_compiler`.
    shaderBinary: *const fn (
        count: Sizei,
        shaders: [*]const Uint,
        binary_format: Enum,
        binary: ?*const anyopaque,
        length: Sizei,
    ) callconv(.c) void,
    /// A hint that no more shaders will be compiled, so the compiler's memory
    /// can go back. Compiling another one after it is still allowed.
    releaseShaderCompiler: *const fn () callconv(.c) void,

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
    /// ES 2.0 has no `layout(location = ...)`, so this is how an attribute
    /// gets a known index: called before linking, every time.
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

    uniform1f: *const fn (location: Int, v0: Float) callconv(.c) void,
    uniform2f: *const fn (location: Int, v0: Float, v1: Float) callconv(.c) void,
    uniform3f: *const fn (location: Int, v0: Float, v1: Float, v2: Float) callconv(.c) void,
    uniform4f: *const fn (location: Int, v0: Float, v1: Float, v2: Float, v3: Float) callconv(.c) void,
    uniform1i: *const fn (location: Int, v0: Int) callconv(.c) void,
    uniform2i: *const fn (location: Int, v0: Int, v1: Int) callconv(.c) void,
    uniform3i: *const fn (location: Int, v0: Int, v1: Int, v2: Int) callconv(.c) void,
    uniform4i: *const fn (location: Int, v0: Int, v1: Int, v2: Int, v3: Int) callconv(.c) void,
    uniform1fv: *const fn (location: Int, count: Sizei, value: [*]const Float) callconv(.c) void,
    uniform2fv: *const fn (location: Int, count: Sizei, value: [*]const Float) callconv(.c) void,
    uniform3fv: *const fn (location: Int, count: Sizei, value: [*]const Float) callconv(.c) void,
    uniform4fv: *const fn (location: Int, count: Sizei, value: [*]const Float) callconv(.c) void,
    uniform1iv: *const fn (location: Int, count: Sizei, value: [*]const Int) callconv(.c) void,
    uniform2iv: *const fn (location: Int, count: Sizei, value: [*]const Int) callconv(.c) void,
    uniform3iv: *const fn (location: Int, count: Sizei, value: [*]const Int) callconv(.c) void,
    uniform4iv: *const fn (location: Int, count: Sizei, value: [*]const Int) callconv(.c) void,
    /// `transpose` must be `gl_false` on ES 2.0: transposing on upload is one
    /// of the things ES took out.
    uniformMatrix2fv: *const fn (location: Int, count: Sizei, transpose: Boolean, value: [*]const Float) callconv(.c) void,
    uniformMatrix3fv: *const fn (location: Int, count: Sizei, transpose: Boolean, value: [*]const Float) callconv(.c) void,
    uniformMatrix4fv: *const fn (location: Int, count: Sizei, transpose: Boolean, value: [*]const Float) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Textures
    // ---------------------------------------------------------------------

    genTextures: *const fn (n: Sizei, textures: [*]Uint) callconv(.c) void,
    deleteTextures: *const fn (n: Sizei, textures: [*]const Uint) callconv(.c) void,
    isTexture: *const fn (texture: Uint) callconv(.c) Boolean,
    bindTexture: *const fn (target: Enum, texture: Uint) callconv(.c) void,
    activeTexture: *const fn (texture: Enum) callconv(.c) void,
    generateMipmap: *const fn (target: Enum) callconv(.c) void,
    /// On ES 2.0 `internal_format` has to equal `format`, and both are
    /// unsized: `rgba`, not `rgba8`. ES 3.0 accepts the sized forms, and a
    /// texture that works on the desktop and not on a phone is usually this.
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
    texParameteri: *const fn (target: Enum, pname: Enum, param: Int) callconv(.c) void,
    texParameterf: *const fn (target: Enum, pname: Enum, param: Float) callconv(.c) void,
    texParameteriv: *const fn (target: Enum, pname: Enum, params: [*]const Int) callconv(.c) void,
    texParameterfv: *const fn (target: Enum, pname: Enum, params: [*]const Float) callconv(.c) void,
    getTexParameteriv: *const fn (target: Enum, pname: Enum, params: [*]Int) callconv(.c) void,
    getTexParameterfv: *const fn (target: Enum, pname: Enum, params: [*]Float) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Framebuffers and renderbuffers
    // ---------------------------------------------------------------------

    genFramebuffers: *const fn (n: Sizei, framebuffers: [*]Uint) callconv(.c) void,
    deleteFramebuffers: *const fn (n: Sizei, framebuffers: [*]const Uint) callconv(.c) void,
    isFramebuffer: *const fn (framebuffer: Uint) callconv(.c) Boolean,
    bindFramebuffer: *const fn (target: Enum, framebuffer: Uint) callconv(.c) void,
    checkFramebufferStatus: *const fn (target: Enum) callconv(.c) Enum,
    framebufferTexture2D: *const fn (
        target: Enum,
        attachment: Enum,
        tex_target: Enum,
        texture: Uint,
        level: Int,
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
    /// ES 2.0 promises exactly one format will work - `rgba` and
    /// `unsigned_byte` - plus whatever `implementation_color_read_format`
    /// says. Anything else is `invalid_operation`.
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
    getRenderbufferParameteriv: *const fn (target: Enum, pname: Enum, params: [*]Int) callconv(.c) void,

    // ---------------------------------------------------------------------
    // ES 3.0, and so optional
    // ---------------------------------------------------------------------

    /// The indexed extension query. ES kept the flat string as well, so this
    /// is a convenience here rather than the only way in - unlike a desktop
    /// core profile, where it is the only way.
    getStringi: ?*const fn (name: Enum, index: Uint) callconv(.c) ?[*:0]const Char,
    getIntegeri_v: ?*const fn (target: Enum, index: Uint, data: [*]Int) callconv(.c) void,

    /// Vertex array objects. On ES 2.0 they are `GL_OES_vertex_array_object`,
    /// which is the one extension worth loading by suffix: see
    /// `loader.Options.suffixes`.
    genVertexArrays: ?*const fn (n: Sizei, arrays: [*]Uint) callconv(.c) void,
    deleteVertexArrays: ?*const fn (n: Sizei, arrays: [*]const Uint) callconv(.c) void,
    isVertexArray: ?*const fn (array: Uint) callconv(.c) Boolean,
    bindVertexArray: ?*const fn (array: Uint) callconv(.c) void,

    drawArraysInstanced: ?*const fn (mode: Enum, first: Int, count: Sizei, instances: Sizei) callconv(.c) void,
    drawElementsInstanced: ?*const fn (
        mode: Enum,
        count: Sizei,
        kind: Enum,
        indices: ?*const anyopaque,
        instances: Sizei,
    ) callconv(.c) void,
    drawRangeElements: ?*const fn (
        mode: Enum,
        start: Uint,
        end: Uint,
        count: Sizei,
        kind: Enum,
        indices: ?*const anyopaque,
    ) callconv(.c) void,
    vertexAttribDivisor: ?*const fn (index: Uint, divisor: Uint) callconv(.c) void,
    vertexAttribIPointer: ?*const fn (
        index: Uint,
        size: Int,
        kind: Enum,
        stride: Sizei,
        pointer: ?*const anyopaque,
    ) callconv(.c) void,

    mapBufferRange: ?*const fn (target: Enum, offset: Intptr, length: Sizeiptr, access: Bitfield) callconv(.c) ?*anyopaque,
    unmapBuffer: ?*const fn (target: Enum) callconv(.c) Boolean,
    flushMappedBufferRange: ?*const fn (target: Enum, offset: Intptr, length: Sizeiptr) callconv(.c) void,
    copyBufferSubData: ?*const fn (
        read_target: Enum,
        write_target: Enum,
        read_offset: Intptr,
        write_offset: Intptr,
        size: Sizeiptr,
    ) callconv(.c) void,
    bindBufferBase: ?*const fn (target: Enum, index: Uint, buffer: Uint) callconv(.c) void,
    bindBufferRange: ?*const fn (target: Enum, index: Uint, buffer: Uint, offset: Intptr, size: Sizeiptr) callconv(.c) void,
    getUniformBlockIndex: ?*const fn (program: Uint, name: [*:0]const Char) callconv(.c) Uint,
    uniformBlockBinding: ?*const fn (program: Uint, block: Uint, binding: Uint) callconv(.c) void,
    getFragDataLocation: ?*const fn (program: Uint, name: [*:0]const Char) callconv(.c) Int,

    uniform1ui: ?*const fn (location: Int, v0: Uint) callconv(.c) void,
    uniform2ui: ?*const fn (location: Int, v0: Uint, v1: Uint) callconv(.c) void,
    uniform3ui: ?*const fn (location: Int, v0: Uint, v1: Uint, v2: Uint) callconv(.c) void,
    uniform4ui: ?*const fn (location: Int, v0: Uint, v1: Uint, v2: Uint, v3: Uint) callconv(.c) void,
    uniform1uiv: ?*const fn (location: Int, count: Sizei, value: [*]const Uint) callconv(.c) void,

    texImage3D: ?*const fn (
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
    texSubImage3D: ?*const fn (
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
    copyTexSubImage3D: ?*const fn (
        target: Enum,
        level: Int,
        xoffset: Int,
        yoffset: Int,
        zoffset: Int,
        x: Int,
        y: Int,
        width: Sizei,
        height: Sizei,
    ) callconv(.c) void,
    compressedTexImage3D: ?*const fn (
        target: Enum,
        level: Int,
        internal_format: Enum,
        width: Sizei,
        height: Sizei,
        depth: Sizei,
        border: Int,
        image_size: Sizei,
        data: ?*const anyopaque,
    ) callconv(.c) void,
    texStorage2D: ?*const fn (
        target: Enum,
        levels: Sizei,
        internal_format: Enum,
        width: Sizei,
        height: Sizei,
    ) callconv(.c) void,
    texStorage3D: ?*const fn (
        target: Enum,
        levels: Sizei,
        internal_format: Enum,
        width: Sizei,
        height: Sizei,
        depth: Sizei,
    ) callconv(.c) void,

    genSamplers: ?*const fn (n: Sizei, samplers: [*]Uint) callconv(.c) void,
    deleteSamplers: ?*const fn (n: Sizei, samplers: [*]const Uint) callconv(.c) void,
    bindSampler: ?*const fn (unit: Uint, sampler: Uint) callconv(.c) void,
    samplerParameteri: ?*const fn (sampler: Uint, pname: Enum, param: Int) callconv(.c) void,
    samplerParameterf: ?*const fn (sampler: Uint, pname: Enum, param: Float) callconv(.c) void,

    framebufferTextureLayer: ?*const fn (
        target: Enum,
        attachment: Enum,
        texture: Uint,
        level: Int,
        layer: Int,
    ) callconv(.c) void,
    renderbufferStorageMultisample: ?*const fn (
        target: Enum,
        samples: Sizei,
        internal_format: Enum,
        width: Sizei,
        height: Sizei,
    ) callconv(.c) void,
    blitFramebuffer: ?*const fn (
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
    /// Worth more on a phone than anywhere else: it tells a tiled renderer
    /// not to write the depth buffer back to memory at the end of the frame.
    invalidateFramebuffer: ?*const fn (target: Enum, count: Sizei, attachments: [*]const Enum) callconv(.c) void,
    drawBuffers: ?*const fn (n: Sizei, bufs: [*]const Enum) callconv(.c) void,
    readBuffer: ?*const fn (src: Enum) callconv(.c) void,
    clearBufferfv: ?*const fn (buffer: Enum, draw_buffer: Int, value: [*]const Float) callconv(.c) void,
    clearBufferiv: ?*const fn (buffer: Enum, draw_buffer: Int, value: [*]const Int) callconv(.c) void,
    clearBufferuiv: ?*const fn (buffer: Enum, draw_buffer: Int, value: [*]const Uint) callconv(.c) void,
    clearBufferfi: ?*const fn (buffer: Enum, draw_buffer: Int, depth: Float, stencil: Int) callconv(.c) void,

    genQueries: ?*const fn (n: Sizei, ids: [*]Uint) callconv(.c) void,
    deleteQueries: ?*const fn (n: Sizei, ids: [*]const Uint) callconv(.c) void,
    beginQuery: ?*const fn (target: Enum, id: Uint) callconv(.c) void,
    endQuery: ?*const fn (target: Enum) callconv(.c) void,
    getQueryObjectuiv: ?*const fn (id: Uint, pname: Enum, params: [*]Uint) callconv(.c) void,

    fenceSync: ?*const fn (condition: Enum, flags: Bitfield) callconv(.c) Sync,
    clientWaitSync: ?*const fn (sync: Sync, flags: Bitfield, timeout: Uint64) callconv(.c) Enum,
    waitSync: ?*const fn (sync: Sync, flags: Bitfield, timeout: Uint64) callconv(.c) void,
    deleteSync: ?*const fn (sync: Sync) callconv(.c) void,

    beginTransformFeedback: ?*const fn (primitive_mode: Enum) callconv(.c) void,
    endTransformFeedback: ?*const fn () callconv(.c) void,
    transformFeedbackVaryings: ?*const fn (
        program: Uint,
        count: Sizei,
        varyings: [*]const [*:0]const Char,
        buffer_mode: Enum,
    ) callconv(.c) void,

    /// A linked program in a blob. ES had this before the desktop did,
    /// because a phone cannot afford to compile shaders at every start.
    getProgramBinary: ?*const fn (
        program: Uint,
        buf_size: Sizei,
        length: ?*Sizei,
        binary_format: *Enum,
        binary: ?*anyopaque,
    ) callconv(.c) void,
    programBinary: ?*const fn (
        program: Uint,
        binary_format: Enum,
        binary: ?*const anyopaque,
        length: Sizei,
    ) callconv(.c) void,

    // ---------------------------------------------------------------------
    // Loading, and the few things worth wrapping
    // ---------------------------------------------------------------------

    /// The same `gl` prefix as the desktop table, and no suffixes by default.
    /// An ES 2.0 context that has vertex arrays as `GL_OES_vertex_array_object`
    /// is the one case worth turning them on for:
    ///
    /// ```zig
    /// try loader.loadWith(&api, get, .{ .suffixes = &.{"OES"} });
    /// ```
    pub const options: loader.Options = .{ .prefix = "gl" };

    /// Fill the table from a resolver. See `loader.load`.
    pub fn load(self: *Api, resolver: anytype) loader.Error!void {
        return loader.loadWith(self, resolver, options);
    }

    /// Fill it and report what was there, rather than failing. On ES this is
    /// the call to reach for: the difference between a 2.0 and a 3.2 driver
    /// is most of the optional half of this table.
    pub fn tryLoad(self: *Api, resolver: anytype) loader.Status {
        return loader.tryLoad(self, resolver, options);
    }

    /// `getString` as a Zig slice, or null if the context has no such string.
    pub fn string(self: *const Api, name: Enum) ?[]const u8 {
        return std.mem.span(self.getString(name) orelse return null);
    }

    /// The context's version, read from `GL_VERSION`: `OpenGL ES 3.2 ...`.
    pub fn version(self: *const Api) versions.ParseError!versions.Version {
        return versions.Version.parse(self.string(enums.version) orelse "");
    }

    /// The shading language version, read from
    /// `GL_SHADING_LANGUAGE_VERSION`: `OpenGL ES GLSL ES 3.20 ...`.
    pub fn glslVersion(self: *const Api) versions.ParseError!versions.Glsl {
        return versions.Glsl.parse(self.string(enums.shading_language_version) orelse "");
    }

    /// The extensions this context has, gathered into `buffer`.
    ///
    /// The flat string first, because ES never took it away, and the indexed
    /// query only if a driver hands back nothing.
    pub fn extensionNames(self: *const Api, buffer: [][]const u8) ext.Set {
        if (self.string(enums.extensions)) |flat| {
            if (flat.len > 0) return ext.List.init(flat).collect(buffer);
        }

        const getStringi = self.getStringi orelse return .{ .names = buffer[0..0] };
        var total: [1]Int = .{0};
        self.getIntegerv(enums.num_extensions, &total);

        var found: usize = 0;
        var index: Uint = 0;
        while (index < @as(Uint, @intCast(@max(total[0], 0))) and found < buffer.len) : (index += 1) {
            const name = getStringi(enums.extensions, index) orelse continue;
            buffer[found] = std.mem.span(name);
            found += 1;
        }
        return .{ .names = buffer[0..found] };
    }

    /// Drain the error queue and return the first error in it, or null. See
    /// `gl.Api.checkError`.
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

/// An ES 3.0 driver that answers for everything, and usefully for the strings.
const FakeDriver = struct {
    pub fn glGetString(name: Enum) callconv(.c) ?[*:0]const Char {
        return switch (name) {
            enums.version => "OpenGL ES 3.0.0 (Fluxion 1.0)",
            enums.shading_language_version => "OpenGL ES GLSL ES 3.00",
            enums.renderer => "Not A Telephone",
            enums.extensions => "GL_OES_vertex_array_object GL_OES_element_index_uint GL_KHR_debug",
            else => null,
        };
    }

    pub fn glGetError() callconv(.c) Enum {
        return enums.no_error;
    }

    pub fn glGetIntegerv(pname: Enum, data: [*]Int) callconv(.c) void {
        data[0] = switch (pname) {
            enums.max_texture_size => 4096,
            enums.max_vertex_attribs => 16,
            else => 0,
        };
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

/// A driver with ES 2.0 and nothing else, apart from the one extension that
/// every ES 2.0 driver in practice has.
const Es2Driver = struct {
    fn get(name: [*:0]const u8) callconv(.c) ?loader.Proc {
        const wanted = std.mem.span(name);
        if (std.mem.eql(u8, wanted, "glBindVertexArrayOES")) return FakeDriver.get(name);
        inline for (comptime loader.names(Api)) |command| {
            if (std.mem.eql(u8, command, wanted)) {
                const field = command["gl".len..];
                if (@typeInfo(@FieldType(Api, lowerFirst(field))) == .optional) return null;
                return FakeDriver.get(name);
            }
        }
        return null;
    }

    fn lowerFirst(comptime name: []const u8) []const u8 {
        comptime {
            return [_]u8{std.ascii.toLower(name[0])} ++ name[1..];
        }
    }
};

test "the whole table loads, and every signature casts" {
    var api: Api = undefined;
    const status = api.tryLoad(FakeDriver.get);

    try testing.expect(status.ok());
    try testing.expectEqual(status.requested, status.loaded);
    try testing.expectEqual(0, status.absent);
    try testing.expect(status.requested > 130);
}

test "an ES 2.0 driver fills the required half and no more" {
    var api: Api = undefined;
    const status = api.tryLoad(Es2Driver.get);

    // Nothing required is missing, so the table is usable...
    try testing.expect(status.ok());
    try testing.expectEqual(comptime loader.optionalCount(Api), status.absent);
    try testing.expect(status.absent > 40);

    // ...and everything ES 3.0 brought is null, which the compiler will not
    // let a call site forget.
    try testing.expectEqual(null, api.bindVertexArray);
    try testing.expectEqual(null, api.drawArraysInstanced);
    try testing.expectEqual(null, api.fenceSync);
    try testing.expectEqual(status.requested - status.absent, status.loaded);
}

test "the one extension worth loading by suffix" {
    var api: Api = undefined;
    // Without asking, the OES entry point is not substituted for the core one.
    _ = api.tryLoad(Es2Driver.get);
    try testing.expectEqual(null, api.bindVertexArray);

    // With it, an ES 2.0 context gets vertex arrays.
    const status = loader.tryLoad(&api, Es2Driver.get, .{ .suffixes = &.{"OES"} });
    try testing.expect(status.ok());
    try testing.expect(api.bindVertexArray != null);
    // And the commands ES 2.0 really has not got are still absent.
    try testing.expectEqual(null, api.fenceSync);
}

test "what the table asks the driver for" {
    const asked = comptime loader.names(Api);
    inline for (asked) |name| {
        try testing.expect(std.mem.startsWith(u8, name, "gl"));
        try testing.expect(std.ascii.isUpper(name[2]));
    }

    // The ES spellings, which are what makes this a separate table.
    try testing.expect(@hasField(Api, "clearDepthf"));
    try testing.expect(@hasField(Api, "depthRangef"));
    try testing.expect(!@hasField(Api, "clearDepth"));
    try testing.expect(!@hasField(Api, "polygonMode"));
    try testing.expect(!@hasField(Api, "drawBuffer"));
}

test "the questions a program asks at startup" {
    var api: Api = undefined;
    try api.load(FakeDriver.get);

    const context = try api.version();
    try testing.expectEqual(versions.Api.gles, context.api);
    try testing.expectEqual(3, context.major);
    try testing.expectEqual(0, context.minor);
    try testing.expectEqual(300, (try api.glslVersion()).directive());
    try testing.expectEqualStrings("Not A Telephone", api.string(enums.renderer).?);

    var buffer: [16][]const u8 = undefined;
    const have = api.extensionNames(&buffer);
    try testing.expectEqual(3, have.count());
    try testing.expect(have.has("OES_vertex_array_object"));
    try testing.expect(!have.has("GL_EXT_disjoint_timer_query"));

    var limits: [1]Int = .{0};
    api.getIntegerv(enums.max_vertex_attribs, &limits);
    try testing.expectEqual(16, limits[0]);

    try testing.expectEqual(null, api.checkError());
}
