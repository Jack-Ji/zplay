const std = @import("std");
const GraphicsApi = @import("../build.zig").GraphicsApi;

pub fn link(
    exe: *std.build.LibExeObjStep,
    graphics_api: GraphicsApi,
    comptime root_path: []const u8,
) void {
    var flags = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer flags.deinit();
    flags.append("-Wno-return-type-c-linkage") catch unreachable;
    flags.append("-fno-sanitize=undefined") catch unreachable;
    switch (graphics_api) {
        .gl33 => {},
        .gles3 => flags.append("-DIMGUI_IMPL_OPENGL_ES3") catch unreachable,
    }

    var lib = exe.builder.addStaticLibrary("imgui", null);
    lib.setBuildMode(exe.build_mode);
    lib.setTarget(exe.target);
    lib.linkLibC();
    lib.linkLibCpp();
    if (exe.target.isWindows()) {
        lib.linkSystemLibrary("winmm");
        lib.linkSystemLibrary("user32");
        lib.linkSystemLibrary("imm32");
        lib.linkSystemLibrary("gdi32");
    }
    lib.addIncludePath(root_path ++ "/src/deps/gl/c/include");
    lib.addIncludePath(root_path ++ "/src/deps/imgui/c");
    lib.addCSourceFiles(&.{
        root_path ++ "/src/deps/imgui/c/imgui.cpp",
        root_path ++ "/src/deps/imgui/c/imgui_demo.cpp",
        root_path ++ "/src/deps/imgui/c/imgui_draw.cpp",
        root_path ++ "/src/deps/imgui/c/imgui_tables.cpp",
        root_path ++ "/src/deps/imgui/c/imgui_widgets.cpp",
        root_path ++ "/src/deps/imgui/c/cimgui.cpp",
        root_path ++ "/src/deps/imgui/c/imgui_impl_opengl3.cpp",
        root_path ++ "/src/deps/imgui/c/imgui_impl_opengl3_wrapper.cpp",
    }, flags.items);
    lib.addCSourceFiles(&.{
        root_path ++ "/src/deps/imgui/ext/implot/c/implot.cpp",
        root_path ++ "/src/deps/imgui/ext/implot/c/implot_items.cpp",
        root_path ++ "/src/deps/imgui/ext/implot/c/implot_demo.cpp",
        root_path ++ "/src/deps/imgui/ext/implot/c/cimplot.cpp",
    }, flags.items);
    lib.addCSourceFiles(&.{
        root_path ++ "/src/deps/imgui/ext/imnodes/c/imnodes.cpp",
        root_path ++ "/src/deps/imgui/ext/imnodes/c/cimnodes.cpp",
    }, flags.items);
    exe.linkLibrary(lib);
}
