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
        .gl33 => flags.append("-DNANOVG_GL3_IMPLEMENTATION") catch unreachable,
        .gles3 => flags.append("-DNANOVG_GLES3_IMPLEMENTATION") catch unreachable,
    }

    var lib = exe.builder.addStaticLibrary("nanovg", null);
    lib.setBuildMode(exe.build_mode);
    lib.setTarget(exe.target);
    lib.linkLibC();
    lib.addIncludePath(root_path ++ "/src/deps/gl/c/include");
    lib.addIncludePath(root_path ++ "/src/deps/nanovg/c");
    lib.addCSourceFiles(&.{
        root_path ++ "/src/deps/nanovg/c/nanovg.c",
        root_path ++ "/src/deps/nanovg/c/nanovg_gl3_impl.c",
    }, flags.items);
    exe.linkLibrary(lib);
}
