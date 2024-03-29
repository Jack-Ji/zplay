const std = @import("std");
const assert = std.debug.assert;
const zp = @import("../../zplay.zig");
const sdl = zp.deps.sdl;
const sdl_impl = @import("sdl_impl.zig");
pub const c = @import("c.zig");

pub const Error = error{
    InitOpenGLFailed,
    InitPlotExtFailed,
    InitNodesExtFailed,
};

/// export friendly api
pub usingnamespace @import("api.zig");

/// icon font: font-awesome
pub const fontawesome = @import("fonts/fontawesome.zig");

/// export 3rd-party extensions
pub const ext = @import("ext/ext.zig");

extern fn _ImGui_ImplOpenGL3_Init(glsl_version: [*c]u8) bool;
extern fn _ImGui_ImplOpenGL3_Shutdown() void;
extern fn _ImGui_ImplOpenGL3_NewFrame() void;
extern fn _ImGui_ImplOpenGL3_RenderDrawData(draw_data: *c.ImDrawData) void;

/// internal static vars
var initialized = false;
var plot_ctx: ?*ext.plot.ImPlotContext = undefined;
var nodes_ctx: ?*ext.nodes.ImNodesContext = undefined;

/// initialize sdl2 and opengl3 backend
pub fn init(ctx: *zp.Context) !void {
    _ = c.igCreateContext(null);
    try sdl_impl.init(ctx);
    if (!_ImGui_ImplOpenGL3_Init(null)) {
        return error.InitOpenGLFailed;
    }

    plot_ctx = ext.plot.createContext();
    if (plot_ctx == null) {
        return error.InitPlotExtFailed;
    }

    nodes_ctx = ext.nodes.createContext();
    if (nodes_ctx == null) {
        return error.InitNodesExtFailed;
    }

    const pixel_ratio = ctx.getPixelRatio();
    var style = c.igGetStyle();
    assert(style != null);
    c.ImGuiStyle_ScaleAllSizes(style, pixel_ratio);
    initialized = true;
}

/// release allocated resources
pub fn deinit() void {
    if (!initialized) {
        std.debug.panic("cimgui isn't initialized!", .{});
    }
    ext.nodes.destroyContext(nodes_ctx.?);
    ext.plot.destroyContext(plot_ctx.?);
    sdl_impl.deinit();
    _ImGui_ImplOpenGL3_Shutdown();
    initialized = false;
}

/// process i/o event
pub fn processEvent(e: sdl.Event) bool {
    assert(initialized);
    return sdl_impl.processEvent(e);
}

/// begin frame
pub fn beginFrame() void {
    assert(initialized);
    sdl_impl.newFrame();
    _ImGui_ImplOpenGL3_NewFrame();
    c.igNewFrame();
}

/// end frame
pub fn endFrame() void {
    assert(initialized);
    c.igRender();
    _ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
}

/// load font awesome
pub fn loadFontAwesome(size: f32, regular: bool, monospaced: bool) !*c.ImFont {
    assert(initialized);
    var font_atlas = c.igGetIO().*.Fonts;
    _ = c.ImFontAtlas_AddFontDefault(
        font_atlas,
        null,
    );

    var ranges = [3]c.ImWchar{
        fontawesome.ICON_MIN_FA,
        fontawesome.ICON_MAX_FA,
        0,
    };
    var cfg = c.ImFontConfig_ImFontConfig();
    defer c.ImFontConfig_destroy(cfg);
    cfg.*.PixelSnapH = true;
    cfg.*.MergeMode = true;
    if (monospaced) {
        cfg.*.GlyphMinAdvanceX = size;
    }
    const font = c.ImFontAtlas_AddFontFromFileTTF(
        font_atlas,
        if (regular)
            fontawesome.FONT_ICON_FILE_NAME_FAR
        else
            fontawesome.FONT_ICON_FILE_NAME_FAS,
        size,
        cfg,
        &ranges,
    );
    if (font == null) {
        std.debug.panic("load font awesome failed!", .{});
    }
    if (!c.ImFontAtlas_Build(font_atlas)) {
        std.debug.panic("build font atlas failed!", .{});
    }
    return font;
}

/// load custom font
pub fn loadTTF(
    path: [:0]const u8,
    size: f32,
    addional_ranges: ?[*c]const c.ImWchar,
) !*c.ImFont {
    assert(initialized);
    var font_atlas = c.igGetIO().*.Fonts;

    var default_ranges = c.ImFontAtlas_GetGlyphRangesDefault(font_atlas);
    var font = c.ImFontAtlas_AddFontFromFileTTF(
        font_atlas,
        path.ptr,
        size,
        null,
        default_ranges,
    );
    if (font == null) {
        std.debug.panic("load font({s}) failed!", .{path});
    }

    if (addional_ranges) |ranges| {
        var cfg = c.ImFontConfig_ImFontConfig();
        defer c.ImFontConfig_destroy(cfg);
        cfg.*.MergeMode = true;
        font = c.ImFontAtlas_AddFontFromFileTTF(
            font_atlas,
            path.ptr,
            size,
            cfg,
            ranges,
        );
        if (font == null) {
            std.debug.panic("load font({s}) failed!", .{path});
        }
    }

    if (!c.ImFontAtlas_Build(font_atlas)) {
        std.debug.panic("build font atlas failed!", .{});
    }
    return font;
}

/// determine whether next character in given buffer is renderable
pub fn isCharRenderable(buf: []const u8) bool {
    var char: c_uint = undefined;
    _ = c.igImTextCharFromUtf8(&char, buf.ptr, buf.ptr + buf.len);
    if (char == 0) {
        return false;
    }
    return c.ImFont_FindGlyphNoFallback(
        c.igGetFont(),
        @intCast(c.ImWchar, char),
    ) != null;
}
