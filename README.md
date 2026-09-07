# Fluxion GL

The entry points of OpenGL and OpenGL ES, found at run time. For Zig 0.16.
Eight pieces that fit together:

| Module | What it is |
| --- | --- |
| `loader` | Fills a struct of function pointers from a `getProcAddress`, by field name. Optionality is in the type: a `?*const fn` field is a command that may be absent. [Fluxion Dyn](https://github.com/kisstp2006/fluxion-dyn) with the `gl` prefix built in. |
| `gl` | The desktop table: every command of OpenGL 3.3 core, with 4.x - storage, debug output, compute - as optional fields. |
| `gles` | The OpenGL ES table: every command of ES 2.0, with ES 3.0 optional. A separate table because ES is a separate API, not a subset with the same spelling. |
| `enums` | The tokens the commands take, under the Khronos names with `GL_` taken off, plus the four that are defined as a sum. |
| `types` | `GLenum`, `GLsizei`, `GLsync` and the rest, and the byte offset that goes where a pointer would. |
| `version` | `GL_VERSION` and `GL_SHADING_LANGUAGE_VERSION` read as numbers, including the line a shader has to start with. |
| `extensions` | The extension string or the indexed list, searched without allocating and without caring about the `GL_` prefix. |
| `library` | The GL library opened by name, for the commands `wglGetProcAddress` refuses to return - which on Windows is `glClear` and every other one from 1997. What each platform calls it; the opening itself is [Fluxion Dyn](https://github.com/kisstp2006/fluxion-dyn). |

Both tables answer to the same calls, so a program that runs on the desktop
and on a phone writes its startup once:

| Call | What it does |
| --- | --- |
| `load` | Fill the table, or fail naming the command that was not there. |
| `tryLoad` | Fill it and report: how many loaded, how many optional ones were absent, which required one was missing. |
| `string` | A `glGetString` as a Zig slice. |
| `version` / `glslVersion` | Those strings, as numbers. |
| `extensionNames` | The extensions, gathered into a buffer you own. |
| `checkError` | Drain the error queue and return the first error in it, or null. |

There is no context creation here, and there will not be: GLFW, SDL, EGL and
the platform's own calls do that, and each of them hands back a
`getProcAddress`. This library starts where that function does.

Nothing here allocates. A table is a struct the caller owns, an extension list
points into the driver's own string, and a version is four numbers and a
slice.

## Install

```bash
zig fetch --save git+https://github.com/kisstp2006/fluxion-gl
```

Or, for a checkout next to your project, add to `build.zig.zon`:

```zig
.dependencies = .{
    .fluxion_gl = .{ .path = "../fluxion-gl" },
},
```

Either way, wire it up in `build.zig`:

```zig
const fluxion = b.dependency("fluxion_gl", .{
    .target = target,
    .optimize = optimize,
});
exe_mod.addImport("fluxion_gl", fluxion.module("fluxion_gl"));
```

```zig
const opengl = @import("fluxion_gl");
const c = opengl.enums;
```

One dependency comes with it, fetched the same way and needing nothing from
you: [Fluxion Dyn](https://github.com/kisstp2006/fluxion-dyn), where `loader`
and `library` get their machinery from.

## Tour

### loader

A table is a plain struct whose fields are function pointers. The field name
is the command name with `gl` taken off and the first letter lowered, which is
also how Zig spells a function, so the table reads as Zig and loads as GL:

```zig
const Frame = struct {
    clear: *const fn (mask: opengl.types.Bitfield) callconv(.c) void,
    drawArrays: *const fn (mode: opengl.types.Enum, first: opengl.types.Int, count: opengl.types.Sizei) callconv(.c) void,
    dispatchCompute: ?*const fn (x: opengl.types.Uint, y: opengl.types.Uint, z: opengl.types.Uint) callconv(.c) void,
};

var api: Frame = undefined;
try opengl.load(&api, glfwGetProcAddress);   // asks for glClear, glDrawArrays, glDispatchCompute
```

Optionality is in the type, and that is the whole version policy. A
`*const fn ...` field is required and loading fails naming it; a
`?*const fn ...` field is left `null` when the driver has not got it, and the
compiler makes the call site unwrap it — so "does this context have compute
shaders?" is asked where the answer matters:

```zig
if (api.dispatchCompute) |dispatch| {
    dispatch(groups, 1, 1);
} else {
    // the slow path, which a program that ships has to have anyway
}
```

When missing commands are something to report rather than to fail on,
`tryLoad` hands back a line for the startup log:

```zig
const status = opengl.loader.tryLoad(&api, get, .{});
std.log.info("{f}", .{status});
// 176/211 loaded, 14 optional absent, 21 required missing, first glGenSamplers
```

The context has to be current on the calling thread before any of this: some
drivers return null for everything without one, others return addresses that
belong to a context you are not using.

### gl

The desktop table. Everything without a `?` is OpenGL 3.3 core, so a 3.3
context fills it completely; everything with one arrived later:

```zig
var api: opengl.Gl = undefined;
try api.load(glfwGetProcAddress);

api.viewport(0, 0, width, height);
api.clearColor(0.1, 0.1, 0.12, 1);
api.clear(c.color_buffer_bit | c.depth_buffer_bit);

api.bindVertexArray(vao);
api.useProgram(program);
api.drawElements(c.triangles, index_count, c.unsigned_int, opengl.offset(0));
```

3.3 is the line because it is where the modern API stops moving: vertex array
objects, instancing, samplers and explicit attribute locations are all in it,
and it is what macOS froze at. A program that needs less declares its own
table with fewer fields; a program that needs more adds optional fields to a
copy of this one. The loader does not care where the struct came from.

Four methods come with the table, and each is the thing people write by hand
and get slightly wrong:

```zig
const version = try api.version();          // GL_VERSION, parsed
const glsl = try api.glslVersion();         // GL_SHADING_LANGUAGE_VERSION
const renderer = api.string(c.renderer).?;  // any of them, as a slice

if (api.checkError()) |code| std.log.err("GL error 0x{X}", .{code});
```

`checkError` drains the queue rather than reading one entry, because GL
records errors and hands them back one call at a time: a program that reads a
single `getError` after a frame is reading the oldest mistake, not the newest.

### gles

The same, for OpenGL ES. Everything without a `?` is ES 2.0 - the floor of
anything that still runs - and everything with one is ES 3.0 or later:

```zig
var api: opengl.Gles = undefined;
const status = api.tryLoad(eglGetProcAddress);

if (api.bindVertexArray) |bind| bind(vao);   // ES 3.0, or an extension
api.clearDepthf(1.0);                        // and not clearDepth, which ES has not got
```

It is a separate table rather than the desktop one with fields removed, because
ES is a different API that shares an ancestor: `glClearDepthf` takes a float
where desktop takes a double, `glReadPixels` may refuse every format but one,
there is no `glPolygonMode`, and the shading language numbers itself. A program
that means ES should say so, and get a compile error where it strays.

On an ES 2.0 context, vertex array objects are `GL_OES_vertex_array_object`.
That is the one case where the suffix fallback is worth turning on:

```zig
try opengl.loader.loadWith(&api, get, .{ .suffixes = &.{"OES"} });
```

It is off by default, and worth leaving off for anything you have not checked.
An extension entry point is usually the same function under an older name, but
not always: `glBindFramebufferEXT` belongs to a different object model than
`glBindFramebuffer`, and substituting one for the other draws nothing.

### enums

The tokens, under the Khronos names with `GL_` taken off and lowered, so
anything findable in the specification is findable here:

```zig
api.texParameteri(c.texture_2d, c.texture_min_filter, c.linear_mipmap_linear);
api.texImage2D(c.texture_2d, 0, c.srgb8_alpha8, w, h, 0, c.rgba, c.unsigned_byte, pixels);
api.enable(c.depth_test);
api.blendFunc(c.src_alpha, c.one_minus_src_alpha);
```

GL's tokens are one flat numbering shared by every argument of every command,
which is why `linear` is a texture filter and `line` is a polygon mode and
nothing but the spelling keeps them apart. The four that are defined as a sum
are functions, because a driver with 192 texture units would need a long
table:

```zig
api.activeTexture(c.textureUnit(3));
api.framebufferTexture2D(c.framebuffer, c.colorAttachment(1), c.texture_2d, tex, 0);
api.texImage2D(c.cubeFace(face), 0, c.rgba8, w, h, 0, c.rgba, c.unsigned_byte, side);
```

### types

The C types GL is written in, as aliases rather than as `i32` and friends,
because a table has to match the widths the driver was compiled with. Two are
worth reading twice: `Boolean` is a byte and not a `bool`, and `Sync` is a
nullable pointer to an opaque object.

`offset` is the one function here, and it exists because the obvious spelling
is wrong in Zig. Where a buffer is bound, GL wants a byte offset in an
argument declared as a pointer, and `@ptrFromInt(0)` - the first attribute of
every interleaved vertex - is illegal behaviour:

```zig
api.vertexAttribPointer(0, 3, c.float, opengl.types.gl_false, stride, opengl.offset(0));
api.vertexAttribPointer(1, 2, c.float, opengl.types.gl_false, stride, opengl.offset(12));
```

### version

There is no version query in OpenGL that does not need parsing.
`GL_MAJOR_VERSION` is an integer, but it only exists from 3.0 and not at all
in ES 2.0, so a program that has to find out whether it may use it has already
had to read the string:

```zig
const version = try opengl.Version.parse("4.6.0 NVIDIA 550.54.14");
version.api;              // .gl
version.atLeast(3, 3);    // true
version.release;          // "NVIDIA 550.54.14", unread and worth logging whole
```

`OpenGL ES 3.2 Mesa 23.2.1` parses the same way and comes out `.gles`. The
shading language has its own numbering, two digits wide, and it is not the
API's:

```zig
const glsl = (try opengl.Version.parse("3.2 driver")).glsl().?;
glsl.directive();                    // 150, because OpenGL 3.2 speaks GLSL 1.50
try glsl.writeDirective(writer);     // "#version 150\n"
```

That is the point of the module. A program that writes `#version 320` into a
3.2 shader gets a compile error with nothing helpful in it, and the `es` that
ES 3.0 wants and ES 2.0 does not is the same trap one version down.

### extensions

Two ways to ask, because OpenGL changed its mind. Up to 3.0, and in every
version of ES, `glGetString(GL_EXTENSIONS)` returns the set as one
space-separated string; from 3.0 a core profile returns null there and hands
the names out one at a time instead. Both end up the same shape, and neither
copies anything:

```zig
var buffer: [512][]const u8 = undefined;
const have = api.extensionNames(&buffer);

have.has("GL_KHR_debug");        // the specification's spelling
have.has("KHR_debug");           // and the one everybody says
have.missing(&.{ "GL_KHR_debug", "GL_ARB_bindless_texture" });  // the first one absent
```

```zig
// Or, given the flat string from an ES 2.0 context:
const list = opengl.extensions.List.init(api.string(c.extensions).?);
if (list.has("OES_vertex_array_object")) { ... }
```

### library

On Windows this is not an optimisation. `wglGetProcAddress` answers only for
commands newer than OpenGL 1.1: ask it for `glClear`, `glViewport`,
`glDrawArrays` or `glGenTextures` - the ones every frame calls - and it
returns null, because those are exported from `opengl32.dll` directly. A
loader that asks only `wglGetProcAddress` produces a table full of holes in
the oldest and most-used commands.

`Chain` is the fix: the context's `getProcAddress` first, the library's
exports second.

```zig
var opengl32 = try opengl.Library.openGl();
defer opengl32.close();

var chain: opengl.Chain = .{ .context = wglGetProcAddress, .library = &opengl32 };
try api.load(&chain);
```

A resolver is either a `getProcAddress` or any value with a `get` method,
which is all a chain is. Elsewhere the fallback is harmless and rarely
reached, and a program that gets its `getProcAddress` from GLFW or SDL needs
none of this - both libraries do the same fallback internally.

## Everything together

```zig
// The window library made a context and made it current; this is the rest.
var api: opengl.Gl = undefined;
const status = api.tryLoad(glfwGetProcAddress);
std.log.info("{f}", .{status});
if (!status.ok()) return error.GlTooOld;

const version = try api.version();
std.log.info("{f}, {s}", .{ version, api.string(c.renderer).? });

// The shader is built around the version the context reported, so one source
// compiles on 3.3 and on 4.6.
var source: std.Io.Writer = .fixed(&buffer);
try (try api.glslVersion()).writeDirective(&source);
try source.writeAll(shader_body);

// Debug output is 4.3, so it may not be there - and where it is, it turns
// every silent mistake into a line of text.
if (api.debugMessageCallback) |install| {
    api.enable(c.debug_output);
    install(onMessage, null);
}

api.clearColor(0.1, 0.1, 0.12, 1);
api.clear(c.color_buffer_bit | c.depth_buffer_bit);
api.drawArrays(c.triangles, 0, 3);
```

`zig build example` runs exactly this, against a driver that does not exist:
two dozen commands that print what they were asked to do, so the tour draws
its triangle on a machine with no graphics card at all.

## Examples

Each has a step of its own. The two with windows in them open one and keep it
until it is closed — escape or the close button — and they take
`-- --frames N` to stop after a fixed count instead, or `-- --capture out.png`
to skip the window altogether and write one frame to a file:

```bash
zig build example-cube3d                              # a window, until you close it
zig build example-cube3d -- --capture cube3d.png      # no window, one PNG
```

`--capture` is the same drawing into a framebuffer object instead of the one
the window owns, so it works on a machine nobody is looking at — and it is
what makes the pictures in this README reproducible.

`zig build examples` runs all five in turn and has to finish on its own, so it
runs those two in `--capture` mode: it writes `zig-out/scene2d.png` and
`zig-out/cube3d.png` rather than flashing a window for three seconds and
taking it away again.

| Example | What it shows |
| --- | --- |
| `zig build example` | The tour: resolving entry points, reading the version, looking for extensions, and one triangle's worth of calls printed as a driver receives them. No context and no window. |
| `zig build example-capabilities` | What this machine's OpenGL is — vendor, renderer, version, shading language, profile, limits, extensions — asked of a real context through a four-command table that loads on anything back to ES 2.0. |
| `zig build example-portable` | The same triangle on a desktop 3.3 driver, an ES 3.0 device and an ES 2.0 one, deciding between `glClearDepth` and `glClearDepthf` and between having vertex arrays and not, by loading tables rather than by `#ifdef`. |
| `zig build example-scene2d` | 2D: a dozen textured quads bouncing in a window, in one instanced draw call, with an orthographic matrix and alpha blending. |
| `zig build example-cube3d` | 3D: a lit cube turning, with a depth buffer, backface culling, a perspective projection and a normal per face. |

The first and the third talk to a driver that is not there — `examples/driver.zig`,
which answers `getProcAddress` and remembers what it was told — because they
are about loading rather than drawing, and a fake driver can be a version
behind on purpose. The other three open a real context and use the real one.

`examples/window.zig` is the Win32 and WGL that a context needs and nothing
more, including the two-step bootstrap: `wglCreateContextAttribsARB` is the
call that makes a 3.3 core context and is itself an extension, so it has to be
fetched from an old-style context that is then thrown away. It is also where
`library.Chain` earns its place — the window hands `load` the context's
`getProcAddress` with `opengl32.dll` behind it, which is the only combination
that fills a table on Windows.

`examples/render.zig` is the shader boilerplate, `examples/capture.zig` writes
a frame out as a PNG, and `examples/matrix.zig` is the four-by-fours. None of
the five is part of the library: a loader has no business having an opinion
about your vectors, and less about your pixels.

All of them carry tests, and `zig build test` runs them, because an entry
point nothing has called is a guess. They open a hidden context and draw into
a framebuffer object: the cube renders a frame and checks that its middle is
the cube, its corners are the background, and at least three faces are
visible, which is the only way to be sure the winding, the projection and the
depth test all agree.

One of those tests exists because of a bug it found. The bootstrap window is
created and destroyed inside `open`, and its `WM_DESTROY` reached the message
procedure the real window uses — so the first `pump` saw a window that had
already gone, and the example opened a window, drew nothing, and reported
zero frames. The bootstrap gets a window class of its own now, and the test
opens a window and pumps it twice.

The three that need a context are Win32 only, and `zig build` leaves them out
on other systems rather than failing there: the library runs anywhere, a
window does not. Elsewhere GLFW or SDL make the context, and `load` takes
their `getProcAddress` exactly the same way.

## Build

```bash
zig build test        # run the test suite
zig build example     # build and run the demo tour
zig build examples    # build and run every example
zig build docs        # generate API docs into zig-out/docs
```

The tests load both tables against fake drivers — one with everything, one
that stopped at OpenGL 3.2, one with ES 2.0 and no more — and check that every
signature in them casts, that the names asked for are the C names, and that
what is missing is reported rather than called. The version strings are
checked against the ones NVIDIA, Mesa, Intel, ANGLE and Apple actually return.

On Windows they also open a real context and fill the whole desktop table from
a real driver, which is the only test that can say the two hundred and eleven
signatures in it are the ones the driver expects.

## Requirements

Zig 0.16.0.

## License


`SPDX-License-Identifier: BSL-1.0`

[Boost Software License 1.0](LICENSE) - permissive, and short enough to read
in a minute: use it, change it, ship it, in anything. The one obligation is
that the copyright notice and the licence text travel with the *source*; a
binary built from it carries nothing, which is the difference from MIT and
BSD and the reason this is the usual choice for a library that ends up
compiled into somebody else's program.

Fluxion libraries are licensed by layer: the foundation is CC0, the engine
infrastructure this one belongs to is BSL-1.0, and what builds on top of it
is BSD.
