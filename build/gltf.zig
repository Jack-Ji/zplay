const std = @import("std");

pub fn link(
    exe: *std.build.LibExeObjStep,
    comptime root_path: []const u8,
) void {
    var flags = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer flags.deinit();
    flags.append("-Wno-return-type-c-linkage") catch unreachable;

    var lib = exe.builder.addStaticLibrary("gltf", null);
    lib.setBuildMode(exe.build_mode);
    lib.setTarget(exe.target);
    lib.linkLibC();
    lib.addIncludePath(root_path ++ "/src/deps/gltf/c");
    lib.addCSourceFile(
        root_path ++ "/src/deps/gltf/c/cgltf_wrapper.c",
        flags.items,
    );
    exe.linkLibrary(lib);
}
