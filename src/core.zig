const std = @import("std");
const zp = @import("zplay.zig");
const GraphicsContext = zp.graphics.gpu.Context;
const console = zp.graphics.font.console;
const audio = zp.audio;
const sdl = zp.deps.sdl;
const log = std.log.scoped(.zplay);

var perf_counter_freq: f64 = undefined;

/// application context
pub const Context = struct {
    /// default allocator
    allocator: std.mem.Allocator = undefined,

    /// internal window
    window: sdl.Window,

    /// window title
    title: [:0]u8 = undefined,

    /// graphics context
    graphics: GraphicsContext = undefined,

    /// audio engine
    audio: *audio.Engine = undefined,

    /// quit switch
    quit: bool = false,

    /// resizable mode
    resizable: bool = undefined,

    /// fullscreen mode
    fullscreen: bool = undefined,

    /// relative mouse mode
    relative_mouse: bool = undefined,

    /// number of seconds since launch/last-frame
    tick: f64 = 0,
    delta_tick: f32 = 0,
    last_perf_counter: u64 = 0,

    /// frames stats
    fps: f32 = 0,
    average_cpu_time: f32 = 0,
    fps_refresh_time: f64 = 0,
    frame_counter: u32 = 0,

    /// text buffer for rendering console font
    text_buf: [512]u8 = undefined,

    /// update frame stats
    pub fn updateStats(self: *Context) bool {
        const counter = sdl.c.SDL_GetPerformanceCounter();
        self.delta_tick = @floatCast(
            f32,
            @intToFloat(f64, counter - self.last_perf_counter) / perf_counter_freq,
        );
        self.last_perf_counter = counter;
        self.tick += self.delta_tick;
        self.frame_counter += 1;
        if ((self.tick - self.fps_refresh_time) >= 1.0) {
            const t = self.tick - self.fps_refresh_time;
            self.fps = @floatCast(
                f32,
                @intToFloat(f64, self.frame_counter) / t,
            );
            self.average_cpu_time = (1.0 / self.fps) * 1000.0;
            self.fps_refresh_time = self.tick;
            self.frame_counter = 0;
            return true;
        }
        return false;
    }

    /// kill app
    pub fn kill(self: *Context) void {
        self.quit = true;
    }

    /// poll event
    pub fn pollEvent(self: *Context) ?sdl.Event {
        _ = self;
        return sdl.pollEvent();
    }

    /// set title of window
    pub fn setTitle(self: *Context, text: []const u8) !void {
        self.allocator.free(self.title);
        self.title = try self.allocator.dupeZ(u8, text);
        sdl.c.SDL_SetWindowTitle(self.window.ptr, self.title.ptr);
    }

    /// toggle resizable
    pub fn toggleResizable(self: *Context, on_off: ?bool) void {
        if (on_off) |state| {
            self.resizable = state;
        } else {
            self.resizable = !self.resizable;
        }
        _ = sdl.c.SDL_SetWindowResizable(
            self.window.ptr,
            if (self.resizable) sdl.c.SDL_TRUE else sdl.c.SDL_FALSE,
        );
    }

    /// toggle fullscreen
    pub fn toggleFullscreeen(self: *Context, on_off: ?bool) void {
        if (on_off) |state| {
            self.fullscreen = state;
        } else {
            self.fullscreen = !self.fullscreen;
        }
        _ = sdl.c.SDL_SetWindowFullscreen(
            self.window.ptr,
            if (self.fullscreen) sdl.c.SDL_WINDOW_FULLSCREEN_DESKTOP else 0,
        );
    }

    /// toggle relative mouse mode
    pub fn toggleRelativeMouseMode(self: *Context, on_off: ?bool) void {
        if (on_off) |state| {
            self.relative_mouse = state;
        } else {
            self.relative_mouse = !self.relative_mouse;
        }
        _ = sdl.c.SDL_SetRelativeMouseMode(
            if (self.relative_mouse) sdl.c.SDL_TRUE else sdl.c.SDL_FALSE,
        );
    }

    /// get position of window
    pub fn getPosition(self: Context) struct { x: u32, y: u32 } {
        var x: u32 = undefined;
        var y: u32 = undefined;
        sdl.c.SDL_GetWindowPosition(
            self.window.ptr,
            @ptrCast(*c_int, &x),
            @ptrCast(*c_int, &y),
        );
        return .{ .x = x, .y = y };
    }

    /// get size of window
    pub fn getWindowSize(self: Context) struct { w: u32, h: u32 } {
        var w: u32 = undefined;
        var h: u32 = undefined;
        sdl.c.SDL_GetWindowSize(
            self.window.ptr,
            @ptrCast(*c_int, &w),
            @ptrCast(*c_int, &h),
        );
        return .{ .w = w, .h = h };
    }

    /// get pixel ratio
    pub fn getPixelRatio(self: Context) f32 {
        const wsize = self.getWindowSize();
        const fsize = self.graphics.getDrawableSize();
        return @intToFloat(f32, fsize.w) / @intToFloat(f32, wsize.w);
    }

    /// get key status
    pub fn isKeyPressed(self: Context, key: sdl.Scancode) bool {
        _ = self;
        const state = sdl.c.SDL_GetKeyboardState(null);
        return state[@enumToInt(key)] == 1;
    }

    /// get mouse state
    pub fn getMouseState(self: Context) sdl.MouseState {
        _ = self;
        return sdl.getMouseState();
    }

    /// move mouse to given position (relative to window)
    pub fn setMousePosition(self: Context, xrel: f32, yrel: f32) void {
        var w: i32 = undefined;
        var h: i32 = undefined;
        sdl.c.SDL_GetWindowSize(self.window.ptr, &w, &h);
        sdl.c.SDL_WarpMouseInWindow(
            self.window.ptr,
            @floatToInt(i32, @intToFloat(f32, w) * xrel),
            @floatToInt(i32, @intToFloat(f32, h) * yrel),
        );
    }

    /// convenient text drawing
    pub fn drawText(
        self: *Context,
        comptime fmt: []const u8,
        args: anytype,
        opt: console.DrawOption,
    ) console.DrawRect {
        const text = std.fmt.bufPrint(&self.text_buf, fmt, args) catch unreachable;
        return console.drawText(text, opt) catch unreachable;
    }
};

/// application configurations
pub const Game = struct {
    /// custom memory allocator
    allocator: ?std.mem.Allocator = null,

    /// default memory allocator settings
    enable_mem_leak_checks: bool = false,
    enable_mem_detail_logs: bool = false,

    /// called once before rendering loop starts
    initFn: fn (ctx: *Context) anyerror!void,

    /// called every frame
    loopFn: fn (ctx: *Context) anyerror!void,

    /// called before life ends
    quitFn: fn (ctx: *Context) void,

    /// window's title
    title: [:0]const u8 = "zplay",

    /// position of window
    pos_x: sdl.WindowPosition = .default,
    pos_y: sdl.WindowPosition = .default,

    /// width/height of window
    width: u32 = 800,
    height: u32 = 600,

    /// mimimum size of window
    min_size: ?struct { w: u32, h: u32 } = null,

    /// maximumsize of window
    max_size: ?struct { w: u32, h: u32 } = null,

    // resizable switch
    enable_resizable: bool = false,

    /// display switch
    enable_fullscreen: bool = false,

    /// borderless window
    enable_borderless: bool = false,

    /// minimize window
    enable_minimized: bool = false,

    /// maximize window
    enable_maximized: bool = false,

    /// relative mouse mode switch
    enable_relative_mouse_mode: bool = false,

    /// depth-testing capability
    enable_depth_test: bool = false,

    /// face-culling capability
    enable_face_culling: bool = false,

    /// stencil-testing capability
    enable_stencil_test: bool = false,

    /// blending capability
    enable_color_blend: bool = true,

    // vsync switch
    enable_vsync: bool = true,

    /// enable MSAA
    enable_msaa: bool = false,

    /// enable high resolution depth buffer
    enable_highres_depth: bool = false,

    /// enable console module
    enable_console: bool = false,
    console_font_size: u32 = 16,

    /// display framestat on title
    enable_framestat_display: bool = true,
};

/// entrance point, never return until application is killed
pub fn run(comptime g: Game) !void {
    try sdl.init(sdl.InitFlags.everything);
    defer sdl.quit();

    // prepare graphics params
    try GraphicsContext.prepare(g);

    // create window
    _ = sdl.c.SDL_SetHint("SDL_IME_SHOW_UI", "1");
    var flags = sdl.WindowFlags{
        .context = .opengl,
        .allow_high_dpi = true,
        .mouse_capture = true,
        .mouse_focus = true,
    };
    if (g.enable_borderless) {
        flags.borderless = true;
    }
    if (g.enable_minimized) {
        flags.dim = .minimized;
    }
    if (g.enable_maximized) {
        flags.dim = .maximized;
    }
    var ctx: Context = .{
        .window = try sdl.createWindow(
            g.title,
            g.pos_x,
            g.pos_y,
            g.width,
            g.height,
            flags,
        ),
    };
    const AllocatorType = std.heap.GeneralPurposeAllocator(.{
        .safety = if (g.enable_mem_leak_checks) true else false,
        .verbose_log = if (g.enable_mem_detail_logs) true else false,
        .enable_memory_limit = true,
    });
    var gpa: ?AllocatorType = null;
    if (g.allocator) |a| {
        ctx.allocator = a;
    } else {
        gpa = AllocatorType{};
        ctx.allocator = gpa.?.allocator();
    }
    defer {
        if (gpa) |*a| {
            if (a.deinit()) {
                @panic("memory leaks happened!");
            }
        }
        ctx.window.destroy();
    }

    // windows title
    ctx.title = try ctx.allocator.dupeZ(u8, g.title[0..]);
    defer ctx.allocator.free(ctx.title);

    // windows size thresholds
    if (g.min_size) |size| {
        sdl.c.SDL_SetWindowMinimumSize(
            ctx.window.ptr,
            @intCast(c_int, size.w),
            @intCast(c_int, size.h),
        );
    }
    if (g.max_size) |size| {
        sdl.c.SDL_SetWindowMaximumSize(
            ctx.window.ptr,
            @intCast(c_int, size.w),
            @intCast(c_int, size.h),
        );
    }

    // allocate graphics context
    ctx.graphics = try GraphicsContext.init(ctx.window, g);
    defer ctx.graphics.deinit();
    ctx.graphics.setVsyncMode(g.enable_vsync);

    // allocate audio engine
    ctx.audio = try audio.Engine.init(ctx.allocator, .{});
    defer ctx.audio.deinit();

    // apply window options, still changable through Context's methods
    ctx.toggleResizable(g.enable_resizable);
    ctx.toggleFullscreeen(g.enable_fullscreen);
    ctx.toggleRelativeMouseMode(g.enable_relative_mouse_mode);

    // init console
    if (g.enable_console) {
        console.init(std.heap.c_allocator, g.console_font_size);
    }

    // init before loop
    try g.initFn(&ctx);
    defer g.quitFn(&ctx);

    // game loop
    perf_counter_freq = @intToFloat(f64, sdl.c.SDL_GetPerformanceFrequency());
    ctx.last_perf_counter = sdl.c.SDL_GetPerformanceCounter();
    while (!ctx.quit) {
        // clear console text
        if (g.enable_console) {
            console.clear();
        }

        // main loop
        g.loopFn(&ctx) catch |e| {
            log.err("got error in loop: {}", .{e});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
                break;
            }
        };

        // render console text
        if (g.enable_console) {
            console.submitAndRender(&ctx.graphics);
        }

        // update frame stats
        if (ctx.updateStats() and g.enable_framestat_display) {
            var buf: [128]u8 = undefined;
            _ = std.fmt.bufPrintZ(
                &buf,
                "{s} | FPS:{d:.1} AVG-CPU:{d:.1}ms VSYNC:{s} MEM:{:.3}",
                .{
                    ctx.title,
                    ctx.fps,
                    ctx.average_cpu_time,
                    if (g.enable_vsync) "ON" else "OFF",
                    std.fmt.fmtIntSizeBin(if (gpa) |a| a.total_requested_bytes else 0),
                },
            ) catch unreachable;
            sdl.c.SDL_SetWindowTitle(ctx.window.ptr, &buf);
        }

        // swap buffers
        ctx.graphics.swap();
    }
}
