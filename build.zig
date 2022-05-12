const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{
        .default_target = .{
            // prefer compatibility over performance here
            // make your own choice
            .cpu_model = .baseline,
        },
    });

    const graphics_api = b.option(GraphicsApi, "graphics-api", "graphics api") orelse .gl33;

    const example_assets_install = b.addInstallDirectory(.{
        .source_dir = "examples/assets",
        .install_dir = .bin,
        .install_subdir = "assets",
    });
    var examples = [_]struct { name: []const u8, opt: BuildOptions }{
        .{ .name = "simple_window", .opt = .{ .graphics_api = graphics_api } },
        .{ .name = "font", .opt = .{ .graphics_api = graphics_api } },
        .{ .name = "single_triangle", .opt = .{ .graphics_api = graphics_api } },
        .{ .name = "cubes", .opt = .{ .graphics_api = .gl33, .link_imgui = true } },
        .{ .name = "phong_lighting", .opt = .{ .graphics_api = graphics_api, .link_imgui = true } },
        .{ .name = "imgui_demo", .opt = .{ .graphics_api = graphics_api, .link_imgui = true } },
        .{ .name = "imgui_fontawesome", .opt = .{ .graphics_api = graphics_api, .link_imgui = true } },
        .{ .name = "imgui_ttf", .opt = .{ .graphics_api = .gl33, .link_imgui = true } },
        .{ .name = "vector_graphics", .opt = .{ .graphics_api = graphics_api, .link_imgui = true, .link_vg = true } },
        .{ .name = "vg_benchmark", .opt = .{ .graphics_api = graphics_api, .link_imgui = true, .link_vg = true } },
        .{ .name = "mesh_generation", .opt = .{ .graphics_api = graphics_api, .link_imgui = true } },
        .{ .name = "gltf_demo", .opt = .{ .graphics_api = graphics_api, .link_imgui = true } },
        .{ .name = "environment_mapping", .opt = .{ .graphics_api = graphics_api, .link_imgui = true } },
        .{ .name = "post_processing", .opt = .{ .graphics_api = graphics_api, .link_imgui = true } },
        .{ .name = "rasterization", .opt = .{ .graphics_api = .gl33, .link_imgui = true } },
        .{ .name = "bullet_test", .opt = .{ .graphics_api = graphics_api, .link_imgui = true, .link_bullet = true } },
        .{ .name = "chipmunk_test", .opt = .{ .graphics_api = graphics_api, .link_imgui = true, .link_chipmunk = true } },
        .{ .name = "file_dialog", .opt = .{ .graphics_api = graphics_api, .link_imgui = true, .link_nfd = true } },
        .{ .name = "cube_cross", .opt = .{ .graphics_api = graphics_api, .link_imgui = true } },
        .{ .name = "sprite_sheet", .opt = .{ .graphics_api = graphics_api } },
        .{ .name = "sprite_benchmark", .opt = .{ .graphics_api = graphics_api } },
        .{ .name = "sound_play", .opt = .{ .graphics_api = graphics_api } },
        .{ .name = "particle_2d", .opt = .{ .graphics_api = graphics_api, .link_imgui = true } },
    };
    const build_examples = b.step("build_examples", "compile and install all examples");
    for (examples) |demo| {
        const exe = b.addExecutable(
            demo.name,
            std.fmt.allocPrint(b.allocator, "examples{s}{s}.zig", .{ std.fs.path.sep_str, demo.name }) catch unreachable,
        );
        exe.setBuildMode(mode);
        exe.setTarget(target);
        link(exe, demo.opt);
        const install_cmd = b.addInstallArtifact(exe);
        const run_cmd = exe.run();
        run_cmd.step.dependOn(&install_cmd.step);
        run_cmd.step.dependOn(&example_assets_install.step);
        run_cmd.cwd = "zig-out" ++ std.fs.path.sep_str ++ "bin";
        run_cmd.cwd = std.fs.path.join(b.allocator, &[_][]const u8{ "zig-out", "bin" }) catch unreachable;
        const run_step = b.step(
            demo.name,
            std.fmt.allocPrint(b.allocator, "run example {s}", .{demo.name}) catch unreachable,
        );
        run_step.dependOn(&run_cmd.step);
        build_examples.dependOn(&install_cmd.step);
    }
}

pub const BuildOptions = struct {
    graphics_api: GraphicsApi = .gl33,
    link_nfd: bool = false,
    link_imgui: bool = false,
    link_vg: bool = false,
    link_bullet: bool = false,
    link_chipmunk: bool = false,
};

pub const GraphicsApi = enum {
    gl33,
    gles3,
};

/// link zplay framework to executable
pub fn link(exe: *std.build.LibExeObjStep, opt: BuildOptions) void {
    const root_path = comptime rootPath();

    // init build options
    var build_options = exe.builder.addOptions();
    build_options.addOption(GraphicsApi, "graphics_api", opt.graphics_api);

    // link dependencies
    @import("build/sdl.zig").link(exe, root_path);
    @import("build/opengl.zig").link(exe, root_path);
    @import("build/miniaudio.zig").link(exe, root_path);
    @import("build/stb.zig").link(exe, root_path);
    @import("build/gltf.zig").link(exe, root_path);
    if (opt.link_nfd) @import("build/nfd.zig").link(exe, root_path);
    if (opt.link_imgui) @import("build/imgui.zig").link(
        exe,
        opt.graphics_api,
        root_path,
    );
    if (opt.link_vg) {
        @import("build/nanovg.zig").link(exe, opt.graphics_api, root_path);
        @import("build/nanosvg.zig").link(exe, root_path);
    }
    if (opt.link_bullet) @import("build/bullet.zig").link(exe, root_path);
    if (opt.link_chipmunk) @import("build/chipmunk.zig").link(exe, root_path);

    // use zplay
    const sdl = @import("./src/deps/sdl/Sdk.zig").init(exe.builder);
    exe.addPackage(.{
        .name = "zplay",
        .path = .{ .path = root_path ++ "/src/zplay.zig" },
        .dependencies = &[_]std.build.Pkg{
            sdl.getWrapperPackage("sdl"),
            build_options.getPackage("zplay_build_options"),
        },
    });
}

/// root path
fn rootPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
