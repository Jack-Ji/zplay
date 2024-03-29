const std = @import("std");

pub fn link(
    exe: *std.build.LibExeObjStep,
    comptime root_path: []const u8,
) void {
    var flags = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer flags.deinit();
    flags.append("-Wno-return-type-c-linkage") catch unreachable;
    flags.append("-fno-sanitize=undefined") catch unreachable;

    var lib = exe.builder.addStaticLibrary("nfd", null);
    lib.setBuildMode(exe.build_mode);
    lib.setTarget(exe.target);
    lib.linkLibC();
    if (exe.target.isDarwin()) {
        lib.linkFramework("AppKit");
    } else if (exe.target.isWindows()) {
        lib.linkSystemLibrary("shell32");
        lib.linkSystemLibrary("ole32");
        lib.linkSystemLibrary("uuid"); // needed by MinGW
    } else {
        lib.linkSystemLibrary("atk-1.0");
        lib.linkSystemLibrary("gdk-3");
        lib.linkSystemLibrary("gtk-3");
        lib.linkSystemLibrary("glib-2.0");
        lib.linkSystemLibrary("gobject-2.0");
    }
    lib.addIncludePath(root_path ++ "/src/deps/nfd/c/include");
    lib.addCSourceFile(
        root_path ++ "/src/deps/nfd/c/nfd_common.c",
        flags.items,
    );
    if (exe.target.isDarwin()) {
        lib.addCSourceFile(
            root_path ++ "/src/deps/nfd/c/nfd_cocoa.m",
            flags.items,
        );
    } else if (exe.target.isWindows()) {
        lib.addCSourceFile(
            root_path ++ "/src/deps/nfd/c/nfd_win.cpp",
            flags.items,
        );
    } else {
        lib.addCSourceFile(
            root_path ++ "/src/deps/nfd/c/nfd_gtk.c",
            flags.items,
        );
    }
    exe.linkLibrary(lib);
}
