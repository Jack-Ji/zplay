const std = @import("std");
const zp = @import("zplay");
const dig = zp.deps.dig;
const alg = zp.deps.alg;
const Vec2 = alg.Vec2;
const Vec3 = alg.Vec3;
const Vec4 = alg.Vec4;
const Mat4 = alg.Mat4;
const gfx = zp.graphics;
const GraphicsContext = gfx.gpu.Context;
const Texture = gfx.gpu.Texture;
const Material = gfx.Material;
const Renderer = gfx.Renderer;
const Camera = gfx.Camera;
const RenderPipeline = gfx.RenderPipeline;
const Model = gfx.@"3d".Model;
const SimpleRenderer = gfx.@"3d".SimpleRenderer;
const SkyboxRenderer = gfx.@"3d".SkyboxRenderer;

var camera: Camera = undefined;
var skybox: SkyboxRenderer = undefined;
var skybox_material: Material = undefined;
var simple_renderer: SimpleRenderer = undefined;
var wireframe_mode = false;
var merge_meshes = true;
var vsync_mode = false;
var dog: *Model = undefined;
var dog_meshes: Model.MeshRange = undefined;
var girl: *Model = undefined;
var girl_meshes: Model.MeshRange = undefined;
var helmet: *Model = undefined;
var helmet_meshes: Model.MeshRange = undefined;
var total_vertices: u32 = undefined;
var total_meshes: u32 = undefined;
var face_culling: bool = false;
var render_data_scene: Renderer.Input = undefined;
var render_data_skybox: Renderer.Input = undefined;
var pipline: RenderPipeline = undefined;
var global_tick: f32 = 0;

fn init(ctx: *zp.Context) anyerror!void {
    std.log.info("game init", .{});

    // init imgui
    try dig.init(ctx);

    camera = Camera.fromPositionAndTarget(
        .{
            .perspective = .{
                .fov = 45,
                .aspect_ratio = ctx.graphics.viewport.getAspectRatio(),
                .near = 0.1,
                .far = 100,
            },
        },
        Vec3.new(0, 0, 3),
        Vec3.zero(),
        null,
    );

    skybox = SkyboxRenderer.init(ctx.allocator);
    simple_renderer = SimpleRenderer.init(.{});

    pipline = try RenderPipeline.init(ctx.allocator, &[_]RenderPipeline.RenderPass{
        .{
            .beforeFn = beforeSceneRendering,
            .rd = simple_renderer.renderer(),
            .data = &render_data_scene,
        },
        .{
            .rd = skybox.renderer(),
            .data = &render_data_skybox,
        },
    });

    // load scene
    try loadScene(ctx);
}

fn loop(ctx: *zp.Context) anyerror!void {
    global_tick = @floatCast(f32, ctx.tick);

    while (ctx.pollEvent()) |e| {
        if ((e == .mouse_motion or e == .mouse_button_up or
            e == .mouse_button_down or e == .mouse_wheel) and
            dig.getIO().*.WantCaptureMouse)
        {
            _ = dig.processEvent(e);
            continue;
        }
        switch (e) {
            .key_up => |key| {
                switch (key.scancode) {
                    .escape => ctx.kill(),
                    else => {},
                }
            },
            .mouse_wheel => |me| {
                camera.frustrum.perspective.fov -= @intToFloat(f32, me.delta_y);
                if (camera.frustrum.perspective.fov < 1) {
                    camera.frustrum.perspective.fov = 1;
                }
                if (camera.frustrum.perspective.fov > 45) {
                    camera.frustrum.perspective.fov = 45;
                }
            },
            .quit => ctx.kill(),
            else => {},
        }
    }

    // render the scene
    try pipline.run(&ctx.graphics);

    // settings
    dig.beginFrame();
    {
        dig.setNextWindowPos(
            .{ .x = @intToFloat(f32, ctx.graphics.viewport.w) - 30, .y = 50 },
            .{
                .cond = dig.c.ImGuiCond_Always,
                .pivot = .{ .x = 1, .y = 0 },
            },
        );
        if (dig.begin(
            "control",
            null,
            dig.c.ImGuiWindowFlags_NoMove |
                dig.c.ImGuiWindowFlags_NoResize |
                dig.c.ImGuiWindowFlags_AlwaysAutoResize,
        )) {
            dig.ztext("FPS: {d:.2}", .{dig.getIO().*.Framerate});
            dig.ztext("ms/frame: {d:.2}", .{ctx.delta_tick * 1000});
            dig.ztext("Total Vertices: {d}", .{total_vertices});
            dig.ztext("Total Meshes: {d}", .{total_meshes});
            dig.separator();
            if (dig.checkbox("wireframe", &wireframe_mode)) {
                ctx.graphics.setPolygonMode(if (wireframe_mode) .line else .fill);
            }
            if (dig.checkbox("vsync", &vsync_mode)) {
                ctx.graphics.setVsyncMode(vsync_mode);
            }
            if (dig.checkbox("face culling", &face_culling)) {
                ctx.graphics.toggleCapability(.cull_face, face_culling);
            }
            if (dig.checkbox("merge meshes", &merge_meshes)) {
                try loadScene(ctx);
            }
        }
        dig.end();

        const S = struct {
            const MAX_SIZE = 20000;
            var data = std.ArrayList(f32).init(std.heap.c_allocator);
            var offset: u32 = 0;
            var history: f32 = 10;
            var interval: f32 = 0;
            var count: f32 = 0;
        };
        S.interval += ctx.delta_tick;
        S.count += 1;
        if (S.interval > 0.1) {
            var mpf = S.interval / S.count;
            if (S.data.items.len < S.MAX_SIZE) {
                try S.data.appendSlice(&.{ @floatCast(f32, ctx.tick), mpf });
            } else {
                S.data.items[S.offset] = @floatCast(f32, ctx.tick);
                S.data.items[S.offset + 1] = mpf;
                S.offset = (S.offset + 2) % S.MAX_SIZE;
            }
            S.interval = 0;
            S.count = 0;
        }
        const plot = dig.ext.plot;
        if (dig.begin("monitor", null, 0)) {
            _ = dig.sliderFloat("History", &S.history, 1, 30, .{});
            plot.setNextPlotLimitsX(
                @floatCast(f32, ctx.tick) - S.history,
                @floatCast(f32, ctx.tick),
                dig.c.ImGuiCond_Always,
            );
            plot.setNextPlotLimitsY(0, 0.02, .{});
            if (plot.beginPlot("milliseconds per frame", .{})) {
                if (S.data.items.len > 0) {
                    plot.plotLine_PtrPtr(
                        "line",
                        f32,
                        &S.data.items[0],
                        &S.data.items[1],
                        @intCast(u32, S.data.items.len / 2),
                        .{ .offset = @intCast(c_int, S.offset) },
                    );
                }
                plot.endPlot();
            }
        }
        dig.end();
    }
    dig.endFrame();
}

fn loadScene(ctx: *zp.Context) !void {
    const S = struct {
        var loaded = false;
    };
    if (S.loaded) {
        skybox_material.data.single_cubemap.deinit();
        dog.deinit();
        girl.deinit();
        helmet.deinit();
        render_data_scene.deinit();
    }

    // allocate skybox
    skybox_material = Material.init(.{
        .single_cubemap = try Texture.initCubeFromFilePaths(
            ctx.allocator,
            "assets/skybox/right.jpg",
            "assets/skybox/left.jpg",
            "assets/skybox/top.jpg",
            "assets/skybox/bottom.jpg",
            "assets/skybox/front.jpg",
            "assets/skybox/back.jpg",
            false,
        ),
    });

    // load models
    total_vertices = 0;
    total_meshes = 0;
    dog = try Model.fromGLTF(ctx.allocator, "assets/dog.gltf", merge_meshes, null);
    girl = try Model.fromGLTF(ctx.allocator, "assets/girl.glb", merge_meshes, null);
    helmet = try Model.fromGLTF(ctx.allocator, "assets/SciFiHelmet/SciFiHelmet.gltf", merge_meshes, null);
    for (dog.meshes.items) |m| {
        total_vertices += @intCast(u32, m.positions.items.len);
        total_meshes += 1;
    }
    for (girl.meshes.items) |m| {
        total_vertices += @intCast(u32, m.positions.items.len);
        total_meshes += 1;
    }
    for (helmet.meshes.items) |m| {
        total_vertices += @intCast(u32, m.positions.items.len);
        total_meshes += 1;
    }

    // init scene
    render_data_scene = try Renderer.Input.init(
        ctx.allocator,
        &.{},
        &camera,
        null,
        null,
    );
    render_data_skybox = .{
        .camera = &camera,
        .material = &skybox_material,
    };
    dog_meshes = try dog.appendVertexData(
        &render_data_scene,
        Mat4.identity(),
        null,
    );
    girl_meshes = try girl.appendVertexData(
        &render_data_scene,
        Mat4.identity(),
        null,
    );
    helmet_meshes = try helmet.appendVertexData(
        &render_data_scene,
        Mat4.identity(),
        null,
    );

    S.loaded = true;
}

fn beforeSceneRendering(ctx: *GraphicsContext, custom: ?*anyopaque) void {
    _ = custom;
    dog.fillTransforms(
        render_data_scene.getVertexDataRange(dog_meshes.begin, dog_meshes.end),
        Mat4.fromTranslate(Vec3.new(-2.0, -0.7, 0))
            .scale(Vec3.set(0.7))
            .mul(Mat4.fromRotation(global_tick * 50, Vec3.up())),
    );
    girl.fillTransforms(
        render_data_scene.getVertexDataRange(girl_meshes.begin, girl_meshes.end),
        Mat4.fromTranslate(Vec3.new(2.0, -1.2, 0))
            .scale(Vec3.set(0.7))
            .mul(Mat4.fromRotation(global_tick * 100, Vec3.up())),
    );
    helmet.fillTransforms(
        render_data_scene.getVertexDataRange(helmet_meshes.begin, helmet_meshes.end),
        Mat4.fromTranslate(Vec3.new(0.0, 0, 0))
            .scale(Vec3.set(0.7))
            .mul(Mat4.fromRotation(global_tick * 10, Vec3.up())),
    );
    ctx.clear(true, true, false, [_]f32{ 0.2, 0.3, 0.3, 1.0 });
}

fn quit(ctx: *zp.Context) void {
    _ = ctx;
    std.log.info("game quit", .{});
}

pub fn main() anyerror!void {
    try zp.run(.{
        .initFn = init,
        .loopFn = loop,
        .quitFn = quit,
        .width = 1600,
        .height = 900,
        .enable_vsync = false,
        .enable_depth_test = true,
    });
}
