// SPDX-License-Identifier: CC0-1.0

//! The GL shared library, opened by name, for the commands the window
//! system's `getProcAddress` will not return.
//!
//! On Windows this is not an optimisation. `wglGetProcAddress` answers only
//! for commands newer than OpenGL 1.1: ask it for `glClear`, `glViewport`,
//! `glDrawArrays` or `glGenTextures` - the ones every frame calls - and it
//! returns null, because those are exported from `opengl32.dll` directly and
//! Microsoft's loader expects you to have linked them. So a loader that asks
//! only `wglGetProcAddress` produces a table full of holes on the one
//! platform where the holes are in the oldest, most-used commands.
//!
//! `Chain` is the fix, and it is what a program should pass to `load` on
//! Windows: try the context's `getProcAddress` first, because that is the one
//! that knows about the driver's newer entry points, then fall back to the
//! library's exports.
//!
//! ```zig
//! var opengl32 = try library.Library.openGl();
//! defer opengl32.close();
//! var chain: library.Chain = .{ .context = wglGetProcAddress, .library = &opengl32 };
//! try api.load(&chain);
//! ```
//!
//! Elsewhere the fallback is harmless and occasionally useful: GLX returns
//! addresses for everything it knows whether or not a context is current, and
//! EGL is required to, so on those platforms the chain simply never reaches
//! its second link. A program that gets its `getProcAddress` from GLFW or SDL
//! needs none of this - both libraries do the same fallback internally - and
//! can hand that function to `load` on its own.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const loader = @import("loader.zig");

const native_os = builtin.os.tag;

/// The library is not installed, or is not where the loader looks for it.
/// There is no more detail than that on purpose: every platform has its own
/// reasons and none of them help a program that was going to draw.
pub const OpenError = error{LibraryNotFound};

/// An open shared library, and a resolver in its own right: it has a `get`,
/// so `load(&api, &lib)` reads every command straight out of the library's
/// export table.
pub const Library = struct {
    handle: Handle,

    const Handle = switch (native_os) {
        .windows => std.os.windows.HMODULE,
        else => std.DynLib,
    };

    /// What `openGl` tries, in order. The versioned name comes first because
    /// the unversioned one is a developer-package symlink that is often not
    /// installed on the machine a program ships to.
    pub const gl_names: []const [:0]const u8 = switch (native_os) {
        .windows => &.{"opengl32.dll"},
        .macos, .ios, .tvos, .watchos, .visionos => &.{"/System/Library/Frameworks/OpenGL.framework/OpenGL"},
        else => &.{ "libGL.so.1", "libGL.so" },
    };

    /// What `openGles` tries, in order. On Windows this is ANGLE, which is
    /// what Chrome, Firefox and every Electron application ship for ES.
    pub const gles_names: []const [:0]const u8 = switch (native_os) {
        .windows => &.{ "libGLESv2.dll", "GLESv2.dll" },
        .macos, .ios, .tvos, .watchos, .visionos => &.{"libGLESv2.dylib"},
        else => &.{ "libGLESv2.so.2", "libGLESv2.so" },
    };

    /// Open one by name or path.
    ///
    /// On Windows this is `LoadLibraryA`, so the name goes through the system
    /// codepage; the names above are ASCII, and a path that is not should be
    /// loaded by whatever the program already uses for its own files.
    pub fn open(path: [:0]const u8) OpenError!Library {
        comptime switch (native_os) {
            .windows,
            .linux,
            .macos,
            .ios,
            .tvos,
            .watchos,
            .visionos,
            .driverkit,
            .maccatalyst,
            .freebsd,
            .netbsd,
            .openbsd,
            .dragonfly,
            .illumos,
            => {},
            else => @compileError("fluxion-gl: " ++ @tagName(native_os) ++
                " has no shared libraries to open; pass the getProcAddress your window system gives you straight to `load`"),
        };

        switch (native_os) {
            .windows => return .{ .handle = win.LoadLibraryA(path.ptr) orelse return error.LibraryNotFound },
            else => return .{ .handle = std.DynLib.open(path) catch return error.LibraryNotFound },
        }
    }

    /// Open the first of `paths` that is there. Returns `LibraryNotFound`
    /// only when none of them is.
    pub fn openAny(paths: []const [:0]const u8) OpenError!Library {
        for (paths) |path| {
            return open(path) catch continue;
        }
        return error.LibraryNotFound;
    }

    /// The desktop OpenGL library for this platform: `gl_names`.
    pub fn openGl() OpenError!Library {
        return openAny(gl_names);
    }

    /// The OpenGL ES library for this platform: `gles_names`.
    pub fn openGles() OpenError!Library {
        return openAny(gles_names);
    }

    /// Let go of it. The entry points it handed out stop being callable, so
    /// close it when the context is gone, not before.
    pub fn close(self: *Library) void {
        switch (native_os) {
            .windows => _ = win.FreeLibrary(self.handle),
            else => self.handle.close(),
        }
        self.* = undefined;
    }

    /// One exported command, or null. This is the `get` a resolver needs.
    pub fn get(self: *Library, name: [*:0]const u8) ?loader.Proc {
        switch (native_os) {
            .windows => return win.GetProcAddress(self.handle, name),
            else => return self.handle.lookup(loader.Proc, std.mem.span(name)),
        }
    }
};

/// The context's `getProcAddress` first, the library's exports second.
///
/// Both links are optional, so this is also how a program says "just the
/// library" on a platform where it has no context yet, or "just the context"
/// on one where the fallback is pointless.
pub const Chain = struct {
    /// What the window system gave you: `wglGetProcAddress`,
    /// `glXGetProcAddressARB`, `eglGetProcAddress`.
    context: ?loader.GetProcAddress = null,
    /// The library to fall back to, still open for as long as the chain is
    /// used.
    library: ?*Library = null,

    /// The `get` that makes this a resolver.
    pub fn get(self: Chain, name: [*:0]const u8) ?loader.Proc {
        if (self.context) |from_context| {
            if (from_context(name)) |proc| return proc;
        }
        if (self.library) |from_library| return from_library.get(name);
        return null;
    }
};

/// The three calls Windows needs, declared here rather than taken from
/// `std.os.windows`, which no longer carries them. `GetProcAddress` is
/// declared as returning our own `Proc` because that is what it returns: a
/// function pointer whose signature the caller has to know.
const win = struct {
    extern "kernel32" fn LoadLibraryA(path: [*:0]const u8) callconv(.winapi) ?std.os.windows.HMODULE;
    extern "kernel32" fn GetProcAddress(module: std.os.windows.HMODULE, name: [*:0]const u8) callconv(.winapi) ?loader.Proc;
    extern "kernel32" fn FreeLibrary(module: std.os.windows.HMODULE) callconv(.winapi) std.os.windows.BOOL;
};

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

test "a library that is not there" {
    try testing.expectError(error.LibraryNotFound, Library.open("libNotAGraphicsDriver.so.99"));
    try testing.expectError(error.LibraryNotFound, Library.openAny(&.{
        "libNotAGraphicsDriver.so.99",
        "alsoNotThere.dll",
    }));
}

test "the system GL library, on a machine that has one" {
    var lib = Library.openGl() catch return error.SkipZigTest;
    defer lib.close();

    // Whatever else an implementation has, it exports the commands that were
    // in OpenGL 1.0 - which on Windows is exactly the set `wglGetProcAddress`
    // refuses to return, and the reason this file exists.
    try testing.expect(lib.get("glClear") != null);
    try testing.expect(lib.get("glViewport") != null);
    try testing.expect(lib.get("glNotACommand") == null);
}

test "a chain asks the context first" {
    const Context = struct {
        fn get(name: [*:0]const u8) callconv(.c) ?loader.Proc {
            if (std.mem.eql(u8, std.mem.span(name), "glDrawArraysInstanced")) {
                return @ptrCast(&stub);
            }
            return null;
        }
        fn stub() callconv(.c) void {}
    };

    // With neither link there is nothing to ask, and that is not a crash.
    const empty: Chain = .{};
    try testing.expect(empty.get("glClear") == null);

    const context_only: Chain = .{ .context = Context.get };
    try testing.expect(context_only.get("glDrawArraysInstanced") != null);
    try testing.expect(context_only.get("glClear") == null);

    // And with a library behind it, the command the context has not got is
    // found anyway - which is the whole point on Windows.
    var lib = Library.openGl() catch return error.SkipZigTest;
    defer lib.close();
    const chain: Chain = .{ .context = Context.get, .library = &lib };
    try testing.expect(chain.get("glDrawArraysInstanced") != null);
    try testing.expect(chain.get("glClear") != null);
    try testing.expect(chain.get("glNotACommand") == null);
}
