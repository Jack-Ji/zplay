const std = @import("std");
const zp = @import("zplay");
const alg = zp.deps.alg;
const Vec3 = alg.Vec3;
const Mat4 = alg.Mat4;
const gfx = zp.graphics;
const Renderer = gfx.Renderer;
const Material = gfx.Material;
const TextureDisplay = gfx.post_processing.TextureDisplay;
const Sprite = gfx.@"2d".Sprite;
const SpriteSheet = gfx.@"2d".SpriteSheet;
const SpriteBatch = gfx.@"2d".SpriteBatch;
const SpriteRenderer = gfx.@"2d".SpriteRenderer;
const Camera = gfx.@"2d".Camera;
const console = gfx.font.console;

var sprite_sheet: *SpriteSheet = undefined;
var custom_effect: SpriteRenderer = undefined;
var tex_display: TextureDisplay = undefined;
var sprite: Sprite = undefined;
var sprite_batch: *SpriteBatch = undefined;
var camera: *Camera = undefined;

fn init(ctx: *zp.Context) anyerror!void {
    std.log.info("game init", .{});

    const size = ctx.graphics.getDrawableSize();

    // create sprite sheet
    sprite_sheet = try SpriteSheet.fromPicturesInDir(
        ctx.allocator,
        "assets/images",
        size.w,
        size.h,
        1,
        .{},
    );
    //sprite_sheet = try SpriteSheet.fromSheetFiles(
    //    ctx.allocator,
    //    "sheet",
    //);
    custom_effect = SpriteRenderer.init(gfx.gpu.ShaderProgram.shader_head ++
        \\out vec4 frag_color;
        \\
        \\in vec3 v_pos;
        \\in vec4 v_color;
        \\in vec2 v_tex;
        \\
        \\uniform sampler2D u_texture;
        \\
        \\void main()
        \\{
        \\    frag_color = texture(u_texture, v_tex);
        \\    frag_color.gb = frag_color.rr;
        \\}
    );
    sprite = try sprite_sheet.createSprite("ogre");
    sprite_batch = try SpriteBatch.init(
        ctx.allocator,
        &ctx.graphics,
        10,
        1000,
    );
    camera = try Camera.fromViewport(
        ctx.allocator,
        ctx.graphics.viewport,
    );
    sprite_batch.render_data.camera = camera.getCamera();

    // create renderer
    tex_display = try TextureDisplay.init(ctx.allocator);
}

fn loop(ctx: *zp.Context) anyerror!void {
    while (ctx.pollEvent()) |e| {
        switch (e) {
            .key_up => |key| {
                switch (key.scancode) {
                    .escape => ctx.kill(),
                    .f2 => try sprite_sheet.saveToFiles("sheet"),
                    .left => camera.move(-10, 0, .{}),
                    .right => camera.move(10, 0, .{}),
                    .up => camera.move(0, -10, .{}),
                    .down => camera.move(0, 10, .{}),
                    .z => camera.setZoom(std.math.min(2, camera.zoom + 0.1)),
                    .x => camera.setZoom(std.math.max(0.1, camera.zoom - 0.1)),
                    else => {},
                }
            },
            .quit => ctx.kill(),
            else => {},
        }
    }

    ctx.graphics.clear(true, true, false, [_]f32{ 0.3, 0.3, 0.3, 1.0 });
    try tex_display.draw(&ctx.graphics, .{
        .material = &Material.init(
            .{
                .single_texture = sprite_sheet.tex,
            },
        ),
        .custom = &Mat4.fromScale(Vec3.new(0.5, 0.5, 1)).translate(Vec3.new(0.5, 0.5, 0)),
    });

    sprite_batch.begin(.{ .depth_sort = .back_to_forth });
    try sprite_batch.drawSprite(sprite, .{
        .pos = .{ .x = 400, .y = 300 },
        .scale_w = 2,
        .scale_h = 2,
        .rotate_degree = @floatCast(f32, ctx.tick) * 30,
    });
    try sprite_batch.drawSprite(sprite, .{
        .pos = .{ .x = 400, .y = 300 },
        .anchor_point = .{ .x = 0.5, .y = 0.5 },
        .rotate_degree = @floatCast(f32, ctx.tick) * 30,
        .scale_w = 4 + 2 * @cos(@floatCast(f32, ctx.tick)),
        .scale_h = 4 + 2 * @sin(@floatCast(f32, ctx.tick)),
        .color = [_]f32{ 1, 0, 0, 1 },
        .depth = 0.6,
    });
    try sprite_batch.end();

    sprite_batch.begin(.{ .depth_sort = .back_to_forth, .custom_renderer = custom_effect });
    try sprite_batch.drawSprite(sprite, .{
        .pos = .{ .x = 500, .y = 400 },
        .scale_w = 2,
        .scale_h = 2,
        .rotate_degree = @floatCast(f32, ctx.tick) * 30,
    });
    try sprite_batch.drawSprite(sprite, .{
        .pos = .{ .x = 500, .y = 400 },
        .anchor_point = .{ .x = 0.5, .y = 0.5 },
        .rotate_degree = @floatCast(f32, ctx.tick) * 30,
        .scale_w = 4 + 2 * @cos(@floatCast(f32, ctx.tick)),
        .scale_h = 4 + 2 * @sin(@floatCast(f32, ctx.tick)),
        .color = [_]f32{ 1, 0, 0, 1 },
        .depth = 0.6,
    });
    try sprite_batch.end();

    // draw fps
    var draw_opt = console.DrawOption{
        .color = [3]f32{ 1, 1, 1 },
    };
    var rect = ctx.drawText("fps: {d:.1}", .{ctx.fps}, draw_opt);
    draw_opt.ypos = rect.next_line_ypos;
    rect = ctx.drawText(
        "camera pos (up/down/left/right): {d:.0},{d:.0}",
        .{ camera.pos_x, camera.pos_y },
        draw_opt,
    );
    draw_opt.ypos = rect.next_line_ypos;
    rect = ctx.drawText(
        "zoom (z/x): {d:.1}",
        .{camera.zoom},
        draw_opt,
    );
    draw_opt.ypos = rect.next_line_ypos;
    rect = ctx.drawText(
        "frustrum: left({d:.0}) right({d:.0}) bottom({d:.0}) top({d:.0})",
        .{
            camera.internal_camera.frustrum.orthographic.left,
            camera.internal_camera.frustrum.orthographic.right,
            camera.internal_camera.frustrum.orthographic.bottom,
            camera.internal_camera.frustrum.orthographic.top,
        },
        draw_opt,
    );
}

fn quit(ctx: *zp.Context) void {
    _ = ctx;
    std.log.info("game quit", .{});
    camera.deinit();
    sprite_sheet.deinit();
    sprite_batch.deinit();
}

pub fn main() anyerror!void {
    try zp.run(.{
        .initFn = init,
        .loopFn = loop,
        .quitFn = quit,
        .enable_console = true,
        .enable_depth_test = false,
    });
}
