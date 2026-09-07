// SPDX-License-Identifier: BSL-1.0

//! A window with an OpenGL context in it.
//!
//! Nothing here is Fluxion GL, and nothing here is OpenGL either. A context
//! comes from the window system rather than from the API it is a context
//! for - WGL on Windows, GLX or EGL on Linux, EGL on Android - so a program
//! that draws needs this before it needs a loader at all. `fluxion-platform`
//! does all of that, on whichever windowing system this machine has; what is
//! left here is the shape the examples want, which is one struct with a
//! `pump` and a `present`, and the Escape key closing it.
//!
//! ```zig
//! var window = try Window.open(.{ .title = "Example", .width = 960, .height = 540 });
//! defer window.close();
//!
//! var api: opengl.Gl = undefined;
//! try api.load(window.resolver());
//!
//! while (window.pump()) {
//!     // draw
//!     window.present();
//! }
//! ```
//!
//! **`resolver` is where the two libraries meet.** The platform window has a
//! `get` and is therefore a resolver in `fluxion-dyn`'s sense, so it is handed
//! to `load` as it is. It already asks in both places a command can be - the
//! context's extension mechanism, and the GL library's own exports, which is
//! where `glClear` and everything else from 1.1 lives on Windows - so no
//! `Chain` is needed around it. This is not part of the library, and it is
//! not a dependency of it either: `fluxion_platform` is lazy in
//! `build.zig.zon`, fetched for the examples and for nothing else.

const std = @import("std");

const opengl = @import("fluxion_gl");
const platform = @import("fluxion_platform");

pub const Window = struct {
    /// Boxed, because a `platform.Window` is an id and a pointer to its
    /// context, and a context that moved would leave every handle to it
    /// pointing at where it used to be.
    ctx: *platform.Context,
    win: platform.Window,
    /// The framebuffer, in pixels - which on a high-DPI display is not the
    /// size the window was asked for.
    width: u32,
    height: u32,
    resized: bool = false,

    /// Everything the platform layer can fail with. Most of it means "not on
    /// this machine" rather than "something went wrong": see `isAbsent`.
    pub const Error = platform.Error;

    pub const Options = struct {
        title: []const u8 = "Fluxion GL",
        width: u32 = 960,
        height: u32 = 540,
        /// The version to ask the driver for. It may hand back a newer one -
        /// a core profile is allowed to be forwards compatible - but not an
        /// older one.
        major: u8 = 3,
        minor: u8 = 3,
        /// Off means the window is never shown: the context and its buffers
        /// are real, and nothing appears on screen. That is how `--capture`
        /// runs on a machine somebody is using for something else.
        visible: bool = true,
        /// Ask for a context that reports its own mistakes, which costs
        /// nothing on a driver that has `GL_KHR_debug` and is ignored by one
        /// that has not.
        debug: bool = false,
    };

    /// Open a window whose framebuffer is about `width` by `height`, and make
    /// a core context current on it.
    pub fn open(options: Options) Error!Window {
        const gpa = std.heap.smp_allocator;

        const ctx = try gpa.create(platform.Context);
        errdefer gpa.destroy(ctx);
        ctx.* = try platform.Context.init(gpa, .{});
        errdefer ctx.deinit();

        const win = try ctx.createWindow(.{
            .title = options.title,
            .width = options.width,
            .height = options.height,
            .visible = options.visible,
            .gl = .{
                .major = options.major,
                .minor = options.minor,
                .profile = .core,
                .debug = options.debug,
            },
        });
        errdefer win.destroy();

        try win.makeContextCurrent();
        // One frame a refresh. Without it a loop that draws two triangles
        // runs at several thousand frames a second and heats the room. Not
        // granted everywhere, and not worth failing over.
        win.setSwapInterval(.vsync) catch {};

        const size = win.framebufferSize();
        return .{
            .ctx = ctx,
            .win = win,
            .width = size[0],
            .height = size[1],
        };
    }

    /// Is this error the machine's answer rather than the program's fault?
    /// A test that opens a window skips on these, and a program says so and
    /// stops.
    pub fn isAbsent(err: Error) bool {
        return switch (err) {
            error.Unsupported,
            error.NoDisplay,
            error.ConnectionFailed,
            error.WindowCreationFailed,
            error.Unavailable,
            => true,
            error.OutOfMemory => false,
        };
    }

    /// What to hand `load`: the window itself.
    pub fn resolver(self: *Window) platform.Window {
        return self.win;
    }

    /// Drain everything in the queue and answer whether the window is still
    /// there. This does not wait: a program that draws every frame must not
    /// block on an event that may never arrive.
    pub fn pump(self: *Window) bool {
        self.ctx.pump() catch return false;
        while (self.ctx.poll()) |ev| switch (ev) {
            .close => self.win.setShouldClose(true),
            .key => |k| if (k.key == .escape and k.action == .press) self.win.setShouldClose(true),
            .framebuffer_resize => |r| {
                self.width = r.width;
                self.height = r.height;
                self.resized = true;
            },
            else => {},
        };
        return !self.win.shouldClose();
    }

    /// Show what was drawn. Double buffering is not optional here: a single
    /// buffered window shows every triangle as it lands.
    pub fn present(self: *Window) void {
        self.win.swapBuffers() catch {};
    }

    /// Whether the window changed size since this was last asked. Reading it
    /// clears it, because the answer is a thing to act on once.
    pub fn takeResize(self: *Window) bool {
        defer self.resized = false;
        return self.resized;
    }

    /// True while the window has no area to draw into, which is what being
    /// minimised looks like.
    pub fn minimised(self: Window) bool {
        return self.width == 0 or self.height == 0;
    }

    pub fn close(self: *Window) void {
        self.win.destroy();
        self.ctx.deinit();
        std.heap.smp_allocator.destroy(self.ctx);
        self.* = undefined;
    }
};

/// Open a hidden test window, or skip the test on a machine that cannot.
pub fn openForTest(width: u32, height: u32) !Window {
    return Window.open(.{
        .title = "fluxion-gl test",
        .width = width,
        .height = height,
        .visible = false,
    }) catch |err| if (Window.isAbsent(err)) error.SkipZigTest else err;
}

test "a window that has just been opened is not already closing" {
    var window = try openForTest(64, 64);
    defer window.close();

    try std.testing.expect(window.pump());
    try std.testing.expect(window.pump());

    // At least what was asked for, and possibly more: a window manager will
    // not make a window narrower than its own title bar buttons, and a
    // high-DPI display hands back more pixels than were asked for.
    try std.testing.expect(window.width >= 64);
    try std.testing.expect(window.height >= 64);
}

test "a hidden window still has a context, and the table fills" {
    var window = try openForTest(64, 64);
    defer window.close();

    var api: opengl.Gl = undefined;
    const status = api.tryLoad(window.resolver());

    // Whatever this driver is, a 3.3 context has all of 3.3 in it.
    try std.testing.expect(status.ok());
    try std.testing.expectEqual(@as(usize, 0), status.short);

    const version = try api.version();
    try std.testing.expect(version.atLeast(3, 3));
    try std.testing.expectEqual(opengl.version.Api.gl, version.api);

    // And the commands the extension mechanism refuses are there too, which
    // is the platform window looking in both places on the loader's behalf.
    api.clearColor(0, 0, 0, 1);
    api.clear(opengl.enums.color_buffer_bit);
    try std.testing.expectEqual(null, api.checkError());
}
