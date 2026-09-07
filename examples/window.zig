// SPDX-License-Identifier: BSL-1.0

//! A window with an OpenGL context in it.
//!
//! Nothing here is Fluxion GL, and nothing here is OpenGL either. A context
//! comes from the window system rather than from the API it is a context
//! for - `wglCreateContext` on Windows, `glXCreateContext` on X11,
//! `eglCreateContext` almost everywhere else - so a program that draws needs
//! this before it needs a loader at all. GLFW and SDL do it properly; this is
//! the smallest amount of Win32 that does it at all.
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
//! **The context is made twice.** `wglCreateContextAttribsARB` is the call
//! that makes a 3.3 core context, and it is itself an extension - so it can
//! only be fetched from a context that already exists, and the only context
//! that can be made without it is the old kind. Every Windows program that
//! draws with modern OpenGL creates a context it immediately throws away.
//! The window goes with it, because a window's pixel format may be set once
//! and never again.
//!
//! **`resolver` is where the library comes in.** `wglGetProcAddress` answers
//! null for every command that was in OpenGL 1.1 - `glClear`, `glViewport`,
//! `glDrawArrays`, `glGenTextures` - because those are exported from
//! `opengl32.dll` and Microsoft expected you to link them. `opengl.Chain` asks
//! the context first and the library second, which is the only combination
//! that fills a table on Windows.

const std = @import("std");

const opengl = @import("fluxion_gl");

const Handle = *opaque {};

// -------------------------------------------------------------------------
// The Win32 a context needs
// -------------------------------------------------------------------------

const Rect = extern struct {
    left: i32 = 0,
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,
};

const Point = extern struct {
    x: i32 = 0,
    y: i32 = 0,
};

const Message = extern struct {
    window: ?Handle = null,
    message: u32 = 0,
    wparam: usize = 0,
    lparam: isize = 0,
    time: u32 = 0,
    point: Point = .{},
};

const WindowProc = *const fn (Handle, u32, usize, isize) callconv(.winapi) isize;

const ClassExW = extern struct {
    size: u32,
    style: u32,
    proc: WindowProc,
    class_extra: i32 = 0,
    window_extra: i32 = 0,
    instance: ?Handle,
    icon: ?Handle = null,
    cursor: ?Handle = null,
    background: ?Handle = null,
    menu_name: ?[*:0]const u16 = null,
    class_name: [*:0]const u16,
    small_icon: ?Handle = null,
};

/// What `ChoosePixelFormat` is asked for. Most of it is ignored by every
/// driver written this century; what matters is the flags, the colour depth
/// and the depth buffer.
const PixelFormatDescriptor = extern struct {
    size: u16 = @sizeOf(PixelFormatDescriptor),
    version: u16 = 1,
    flags: u32,
    pixel_type: u8 = 0,
    colour_bits: u8 = 32,
    red_bits: u8 = 0,
    red_shift: u8 = 0,
    green_bits: u8 = 0,
    green_shift: u8 = 0,
    blue_bits: u8 = 0,
    blue_shift: u8 = 0,
    alpha_bits: u8 = 8,
    alpha_shift: u8 = 0,
    accum_bits: u8 = 0,
    accum_red_bits: u8 = 0,
    accum_green_bits: u8 = 0,
    accum_blue_bits: u8 = 0,
    accum_alpha_bits: u8 = 0,
    depth_bits: u8 = 24,
    stencil_bits: u8 = 8,
    aux_buffers: u8 = 0,
    layer_type: u8 = 0,
    reserved: u8 = 0,
    layer_mask: u32 = 0,
    visible_mask: u32 = 0,
    damage_mask: u32 = 0,
};

extern "user32" fn RegisterClassExW(class: *const ClassExW) callconv(.winapi) u16;
extern "user32" fn CreateWindowExW(
    ex_style: u32,
    class_name: [*:0]const u16,
    window_name: [*:0]const u16,
    style: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    parent: ?Handle,
    menu: ?Handle,
    instance: ?Handle,
    param: ?*anyopaque,
) callconv(.winapi) ?Handle;
extern "user32" fn DefWindowProcW(Handle, u32, usize, isize) callconv(.winapi) isize;
extern "user32" fn DestroyWindow(window: Handle) callconv(.winapi) c_int;
extern "user32" fn PostQuitMessage(code: c_int) callconv(.winapi) void;
extern "user32" fn ShowWindow(window: Handle, command: c_int) callconv(.winapi) c_int;
extern "user32" fn SetForegroundWindow(window: Handle) callconv(.winapi) c_int;
extern "user32" fn SetWindowPos(
    window: Handle,
    insert_after: ?Handle,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    flags: u32,
) callconv(.winapi) c_int;
extern "user32" fn PeekMessageW(
    message: *Message,
    window: ?Handle,
    first: u32,
    last: u32,
    remove: u32,
) callconv(.winapi) c_int;
extern "user32" fn TranslateMessage(message: *const Message) callconv(.winapi) c_int;
extern "user32" fn DispatchMessageW(message: *const Message) callconv(.winapi) isize;
extern "user32" fn GetClientRect(window: Handle, rect: *Rect) callconv(.winapi) c_int;
extern "user32" fn AdjustWindowRect(rect: *Rect, style: u32, menu: c_int) callconv(.winapi) c_int;
extern "user32" fn LoadCursorW(instance: ?Handle, name: [*:0]const u16) callconv(.winapi) ?Handle;
extern "user32" fn GetDC(window: ?Handle) callconv(.winapi) ?Handle;
extern "user32" fn ReleaseDC(window: ?Handle, dc: Handle) callconv(.winapi) c_int;
extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) ?Handle;

extern "gdi32" fn ChoosePixelFormat(dc: Handle, wanted: *const PixelFormatDescriptor) callconv(.winapi) c_int;
extern "gdi32" fn SetPixelFormat(dc: Handle, format: c_int, descriptor: *const PixelFormatDescriptor) callconv(.winapi) c_int;
extern "gdi32" fn SwapBuffers(dc: Handle) callconv(.winapi) c_int;

extern "opengl32" fn wglCreateContext(dc: Handle) callconv(.winapi) ?Handle;
extern "opengl32" fn wglMakeCurrent(dc: ?Handle, context: ?Handle) callconv(.winapi) c_int;
extern "opengl32" fn wglDeleteContext(context: Handle) callconv(.winapi) c_int;
extern "opengl32" fn wglGetProcAddress(name: [*:0]const u8) callconv(.winapi) ?opengl.Proc;

const cs_hredraw: u32 = 0x0002;
const cs_vredraw: u32 = 0x0001;
/// `CS_OWNDC`: one device context per window, kept for as long as the window
/// is. A GL context is tied to the DC it was made current on, so handing out
/// a fresh one per paint is a way to lose it.
const cs_owndc: u32 = 0x0020;
/// `WS_OVERLAPPEDWINDOW`: a title bar, a border that resizes, and the three
/// buttons.
const ws_overlappedwindow: u32 = 0x00CF0000;
const ws_visible: u32 = 0x10000000;
const cw_usedefault: i32 = @bitCast(@as(u32, 0x80000000));
const sw_show: c_int = 5;
const pm_remove: u32 = 1;

const swp_nosize: u32 = 0x0001;
const swp_nomove: u32 = 0x0002;
const swp_showwindow: u32 = 0x0040;

const wm_destroy: u32 = 0x0002;
const wm_size: u32 = 0x0005;
const wm_close: u32 = 0x0010;
const wm_quit: u32 = 0x0012;
const wm_keydown: u32 = 0x0100;
const vk_escape: usize = 0x1B;

/// `IDC_ARROW`. A cursor identifier is a small integer pretending to be a
/// string, which is what `MAKEINTRESOURCE` does.
const idc_arrow: [*:0]const u16 = @ptrFromInt(32512);

const pfd_draw_to_window: u32 = 0x00000004;
const pfd_support_opengl: u32 = 0x00000020;
const pfd_double_buffer: u32 = 0x00000001;

/// `WGL_CONTEXT_*`, the attributes `wglCreateContextAttribsARB` takes.
const wgl_context_major_version: c_int = 0x2091;
const wgl_context_minor_version: c_int = 0x2092;
const wgl_context_profile_mask: c_int = 0x9126;
const wgl_context_flags: c_int = 0x2094;
const wgl_context_core_profile_bit: c_int = 0x00000001;
const wgl_context_debug_bit: c_int = 0x00000001;

const CreateContextAttribs = *const fn (dc: Handle, share: ?Handle, attributes: [*]const c_int) callconv(.winapi) ?Handle;
const SwapInterval = *const fn (interval: c_int) callconv(.winapi) c_int;

// -------------------------------------------------------------------------
// The window
// -------------------------------------------------------------------------

/// What the message procedure has to tell the loop.
///
/// It lives here rather than in the window's user data because an example
/// opens one window, and the call that attaches a pointer to a window is
/// named differently on 32-bit Windows - a wrinkle worth avoiding in a file
/// whose subject is OpenGL.
const State = struct {
    closed: bool = false,
    resized: bool = false,
    width: u32 = 0,
    height: u32 = 0,
};

var state: State = .{};

fn windowProc(window: Handle, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    switch (message) {
        wm_close => {
            _ = DestroyWindow(window);
            return 0;
        },
        wm_destroy => {
            state.closed = true;
            PostQuitMessage(0);
            return 0;
        },
        wm_size => {
            // The new client size is packed into the low and high halves of
            // `lparam`. A minimised window reports zero, which is not a
            // viewport anything can draw into, so the loop has to check.
            const packed_size: usize = @bitCast(lparam);
            state.width = @intCast(packed_size & 0xFFFF);
            state.height = @intCast(packed_size >> 16 & 0xFFFF);
            state.resized = true;
            return 0;
        },
        wm_keydown => {
            if (wparam == vk_escape) _ = DestroyWindow(window);
            return 0;
        },
        else => return DefWindowProcW(window, message, wparam, lparam),
    }
}

pub const Window = struct {
    handle: Handle,
    dc: Handle,
    context: Handle,
    width: u32,
    height: u32,
    /// Opened once and kept, because half of a table comes out of it. See
    /// `resolver`.
    opengl32: opengl.Library,

    pub const Error = error{
        WindowFailed,
        PixelFormatFailed,
        ContextFailed,
        /// The driver has no `wglCreateContextAttribsARB`, so the newest
        /// context it can make is the compatibility one from 1997. Windows
        /// itself provides one of those with no graphics driver installed at
        /// all, which is why this is a real answer rather than a crash.
        NoModernContext,
    };

    pub const Options = struct {
        title: []const u8 = "Fluxion GL",
        width: u32 = 960,
        height: u32 = 540,
        /// The version to ask the driver for. It may hand back a newer one -
        /// a core profile is allowed to be forwards compatible - but not an
        /// older one.
        major: c_int = 3,
        minor: c_int = 3,
        /// Off means the window is never shown: the context and its buffers
        /// are real, and nothing appears on screen. That is how `--capture`
        /// runs on a machine somebody is using for something else.
        visible: bool = true,
        /// Ask for a context that reports its own mistakes, which costs
        /// nothing on a driver that has `GL_KHR_debug` and is ignored by one
        /// that has not.
        debug: bool = false,
    };

    /// Open a window whose *client area* - the part GL draws into - is
    /// `width` by `height`, and make a context current on it.
    pub fn open(options: Options) Error!Window {
        state = .{ .width = options.width, .height = options.height };
        makeDpiAware();
        registerClass();

        // The context that exists only to be asked how to make the real one.
        const attribs, const interval = try findModernCalls();

        const handle = try createWindow(options);
        errdefer _ = DestroyWindow(handle);

        const dc = GetDC(handle) orelse return error.WindowFailed;
        try setPixelFormat(dc);

        var attributes = [_]c_int{
            wgl_context_major_version, options.major,
            wgl_context_minor_version, options.minor,
            wgl_context_profile_mask,  wgl_context_core_profile_bit,
            wgl_context_flags,         if (options.debug) wgl_context_debug_bit else 0,
            0,
        };
        const context = attribs(dc, null, &attributes) orelse return error.ContextFailed;
        errdefer _ = wglDeleteContext(context);

        if (wglMakeCurrent(dc, context) == 0) return error.ContextFailed;

        // One frame a refresh. Without it a loop that draws two triangles
        // runs at several thousand frames a second and heats the room.
        if (interval) |set| _ = set(1);

        var self: Window = .{
            .handle = handle,
            .dc = dc,
            .context = context,
            .width = options.width,
            .height = options.height,
            .opengl32 = opengl.openGl() catch return error.ContextFailed,
        };

        // Ask the window rather than trusting the arithmetic: the frame the
        // window manager actually gave may differ.
        var client: Rect = .{};
        if (GetClientRect(handle, &client) != 0) {
            self.width = @intCast(client.right - client.left);
            self.height = @intCast(client.bottom - client.top);
        }
        state.width = self.width;
        state.height = self.height;

        if (options.visible) {
            _ = ShowWindow(handle, sw_show);
            // A window started from a terminal opens behind it as often as
            // not, and a program whose whole output is a window is no use
            // underneath something else. Raising it in the stacking order is
            // nearly always allowed; taking the keyboard as well is not, and
            // neither result is checked, because the window is visible either
            // way and it closes on its own button regardless.
            _ = SetWindowPos(handle, null, 0, 0, 0, 0, swp_nomove | swp_nosize | swp_showwindow);
            _ = SetForegroundWindow(handle);
        }

        return self;
    }

    /// What to hand `load`.
    ///
    /// The context's own `getProcAddress` first, and `opengl32.dll` behind it,
    /// because `wglGetProcAddress` returns null for everything that was in
    /// OpenGL 1.1 - which is to say for `glClear` and most of what a frame
    /// calls. This is `library.Chain`, and this is what it is for.
    pub fn resolver(self: *Window) opengl.Chain {
        return .{ .context = wglGetProcAddress, .library = &self.opengl32 };
    }

    /// Drain everything in the queue and answer whether the window is still
    /// there. This does not wait: a program that draws every frame must not
    /// block on a message that may never arrive.
    pub fn pump(self: *Window) bool {
        var message: Message = .{};
        while (PeekMessageW(&message, null, 0, 0, pm_remove) != 0) {
            if (message.message == wm_quit) state.closed = true;
            _ = TranslateMessage(&message);
            _ = DispatchMessageW(&message);
        }
        self.width = state.width;
        self.height = state.height;
        return !state.closed;
    }

    /// Show what was drawn. Double buffering is not optional here: a single
    /// buffered window shows every triangle as it lands.
    pub fn present(self: *Window) void {
        _ = SwapBuffers(self.dc);
    }

    /// Whether the window changed size since this was last asked. Reading it
    /// clears it, because the answer is a thing to act on once.
    pub fn takeResize(_: *Window) bool {
        defer state.resized = false;
        return state.resized;
    }

    /// True while the window has no area to draw into, which is what being
    /// minimised looks like.
    pub fn minimised(self: Window) bool {
        return self.width == 0 or self.height == 0;
    }

    pub fn close(self: *Window) void {
        _ = wglMakeCurrent(null, null);
        _ = wglDeleteContext(self.context);
        _ = ReleaseDC(self.handle, self.dc);
        if (!state.closed) _ = DestroyWindow(self.handle);
        self.opengl32.close();
        self.* = undefined;
    }
};

// -------------------------------------------------------------------------
// The parts of opening one that are worth their own name
// -------------------------------------------------------------------------

fn registerClass() void {
    const class: ClassExW = .{
        .size = @sizeOf(ClassExW),
        .style = cs_hredraw | cs_vredraw | cs_owndc,
        .proc = windowProc,
        .instance = GetModuleHandleW(null),
        .cursor = LoadCursorW(null, idc_arrow),
        .class_name = class_name,
    };
    // Registering twice in one process is an error, and harmless: the class
    // from the first time is still there.
    _ = RegisterClassExW(&class);

    // The bootstrap window gets a class of its own, whose procedure is the
    // default one and nothing else. It matters: the window below is created
    // and destroyed before the real one exists, and if its `WM_DESTROY` went
    // to `windowProc` it would set `closed` and post a quit message - so the
    // program would open a window, see the queued quit on its first `pump`,
    // and close again without drawing a frame.
    const bootstrap: ClassExW = .{
        .size = @sizeOf(ClassExW),
        .style = cs_owndc,
        .proc = DefWindowProcW,
        .instance = GetModuleHandleW(null),
        .class_name = bootstrap_class_name,
    };
    _ = RegisterClassExW(&bootstrap);
}

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("fluxion-gl-example");
const bootstrap_class_name = std.unicode.utf8ToUtf16LeStringLiteral("fluxion-gl-bootstrap");

fn createWindow(options: Window.Options) Window.Error!Handle {
    var frame: Rect = .{
        .right = @intCast(options.width),
        .bottom = @intCast(options.height),
    };
    _ = AdjustWindowRect(&frame, ws_overlappedwindow, 0);

    var title: [128]u16 = undefined;
    const written = std.unicode.utf8ToUtf16Le(&title, options.title) catch 0;
    title[@min(written, title.len - 1)] = 0;

    return CreateWindowExW(
        0,
        class_name,
        title[0..@min(written, title.len - 1) :0],
        ws_overlappedwindow | if (options.visible) ws_visible else 0,
        cw_usedefault,
        cw_usedefault,
        frame.right - frame.left,
        frame.bottom - frame.top,
        null,
        null,
        GetModuleHandleW(null),
        null,
    ) orelse error.WindowFailed;
}

fn setPixelFormat(dc: Handle) Window.Error!void {
    const wanted: PixelFormatDescriptor = .{
        .flags = pfd_draw_to_window | pfd_support_opengl | pfd_double_buffer,
    };
    const format = ChoosePixelFormat(dc, &wanted);
    if (format == 0) return error.PixelFormatFailed;
    if (SetPixelFormat(dc, format, &wanted) == 0) return error.PixelFormatFailed;
}

/// Make a context, ask it how to make a better one, and throw it away.
///
/// The window goes too: a pixel format can be set on a window once, and the
/// format that suits a dummy context is not necessarily the one the real
/// window wants. Two windows is the price of the bootstrap, and every program
/// on Windows that draws with modern OpenGL pays it.
fn findModernCalls() Window.Error!struct { CreateContextAttribs, ?SwapInterval } {
    const dummy = CreateWindowExW(
        0,
        bootstrap_class_name,
        std.unicode.utf8ToUtf16LeStringLiteral("fluxion-gl-bootstrap"),
        ws_overlappedwindow,
        cw_usedefault,
        cw_usedefault,
        64,
        64,
        null,
        null,
        GetModuleHandleW(null),
        null,
    ) orelse return error.WindowFailed;
    defer _ = DestroyWindow(dummy);

    const dc = GetDC(dummy) orelse return error.WindowFailed;
    defer _ = ReleaseDC(dummy, dc);

    try setPixelFormat(dc);

    const context = wglCreateContext(dc) orelse return error.ContextFailed;
    defer _ = wglDeleteContext(context);

    if (wglMakeCurrent(dc, context) == 0) return error.ContextFailed;
    defer _ = wglMakeCurrent(null, null);

    // These two are `wgl` names rather than `gl` ones, and they come from the
    // same place by the same rules - which is why `loader.Options.prefix`
    // exists.
    const attribs = wglGetProcAddress("wglCreateContextAttribsARB") orelse return error.NoModernContext;
    const interval = wglGetProcAddress("wglSwapIntervalEXT");

    return .{
        @ptrCast(attribs),
        if (interval) |raw| @as(SwapInterval, @ptrCast(raw)) else null,
    };
}

/// Tell Windows this program draws at the monitor's real resolution.
///
/// Without it a window on a high-resolution display is rendered at a third of
/// the pixels and scaled up, which looks exactly like a bug in the renderer.
/// The call arrived in Windows 10 1703, so it is fetched by name and skipped
/// where it is not there - which is the argument of the library this example
/// belongs to, applied to something that is not OpenGL at all.
fn makeDpiAware() void {
    var user32 = opengl.Library.open("user32.dll") catch return;
    defer user32.close();

    const raw = user32.get("SetProcessDpiAwarenessContext") orelse return;
    const set: *const fn (?*anyopaque) callconv(.winapi) c_int = @ptrCast(raw);

    // `DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2` is the handle -4, which is
    // a sentinel and not a pointer to anything.
    _ = set(@ptrFromInt(@as(usize, @bitCast(@as(isize, -4)))));
}

test "the structs are the size Windows writes into" {
    // `PeekMessage` writes into this, so it being too small is stack
    // corruption rather than a wrong answer.
    const expected: usize = if (@sizeOf(usize) == 8) 48 else 28;
    try std.testing.expectEqual(expected, @sizeOf(Message));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Rect));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(PixelFormatDescriptor));
}

test "a window that has just been opened is not already closing" {
    // The bootstrap window is created and destroyed inside `open`, and if its
    // messages reached `windowProc` the first `pump` would report a window
    // that has gone - so the program would open one, draw nothing, and exit
    // saying it had rendered no frames. It did, once.
    var window = Window.open(.{ .width = 64, .height = 64, .visible = false }) catch |err| switch (err) {
        error.NoModernContext, error.ContextFailed, error.PixelFormatFailed => return error.SkipZigTest,
        else => return err,
    };
    defer window.close();

    try std.testing.expect(window.pump());
    try std.testing.expect(window.pump());

    // At least what was asked for, and possibly more: Windows will not make a
    // window narrower than its own title bar buttons, which is why `open`
    // reads the size back rather than trusting the arithmetic.
    try std.testing.expect(window.width >= 64);
    try std.testing.expect(window.height >= 64);
}

test "a hidden window still has a context, and the table fills" {
    var window = Window.open(.{
        .title = "fluxion-gl test",
        .width = 64,
        .height = 64,
        .visible = false,
    }) catch |err| switch (err) {
        // A machine with no OpenGL is a machine this example cannot run on,
        // and not a failing test.
        error.NoModernContext, error.ContextFailed, error.PixelFormatFailed => return error.SkipZigTest,
        else => return err,
    };
    defer window.close();

    var api: opengl.Gl = undefined;
    const status = api.tryLoad(window.resolver());

    // Whatever this driver is, a 3.3 context has all of 3.3 in it.
    try std.testing.expect(status.ok());
    try std.testing.expectEqual(@as(usize, 0), status.short);

    const version = try api.version();
    try std.testing.expect(version.atLeast(3, 3));
    try std.testing.expectEqual(opengl.version.Api.gl, version.api);

    // And the commands `wglGetProcAddress` refuses are there too, which is
    // the whole reason `resolver` chains two things together.
    api.clearColor(0, 0, 0, 1);
    api.clear(opengl.enums.color_buffer_bit);
    try std.testing.expectEqual(null, api.checkError());
}
