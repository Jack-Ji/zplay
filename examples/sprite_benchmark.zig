const std = @import("std");
const zp = @import("zplay");
const alg = zp.deps.alg;
const Vec2 = alg.Vec2;
const gfx = zp.graphics;
const SpriteSheet = gfx.@"2d".SpriteSheet;
const Sprite = gfx.@"2d".Sprite;
const SpriteBatch = gfx.@"2d".SpriteBatch;

const Actor = struct {
    sprite: Sprite,
    pos: Sprite.Point,
    velocity: Sprite.Point,
};

var sprite_sheet: *SpriteSheet = undefined;
var sprite_batch: *SpriteBatch = undefined;
var characters: std.ArrayList(Actor) = undefined;
var all_names: std.ArrayList([]const u8) = undefined;
var rand_gen: std.rand.DefaultPrng = undefined;
var delta_tick: f32 = 0;

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
        .{ .accept_jpg = false },
    );
    characters = try std.ArrayList(Actor).initCapacity(
        ctx.allocator,
        1000000,
    );
    sprite_batch = try SpriteBatch.init(
        ctx.allocator,
        &ctx.graphics,
        10,
        1000000,
    );
    all_names = try std.ArrayList([]const u8).initCapacity(
        ctx.allocator,
        10000,
    );
    var it = sprite_sheet.search_tree.iterator();
    while (it.next()) |k| {
        try all_names.append(k.key_ptr.*);
    }
    rand_gen = std.rand.DefaultPrng.init(@intCast(u64, std.time.timestamp()));
}

fn loop(ctx: *zp.Context) anyerror!void {
    delta_tick = (delta_tick + ctx.delta_tick) / 2;

    while (ctx.pollEvent()) |e| {
        switch (e) {
            .key_up => |key| {
                switch (key.scancode) {
                    .escape => ctx.kill(),
                    else => {},
                }
            },
            .mouse_button_up => |click| {
                if (click.button != .left) {
                    continue;
                }
                var rd = rand_gen.random();
                const pos = Sprite.Point{
                    .x = @intToFloat(f32, click.x),
                    .y = @intToFloat(f32, click.y),
                };
                var i: u32 = 0;
                while (i < 1000) : (i += 1) {
                    const index = rd.uintLessThan(usize, all_names.items.len);
                    const angle = rd.float(f32) * 2 * std.math.pi;
                    const name = all_names.items[index];
                    try characters.append(.{
                        .sprite = try sprite_sheet.createSprite(name),
                        .pos = pos,
                        .velocity = .{
                            .x = 5 * @cos(angle),
                            .y = 5 * @sin(angle),
                        },
                    });
                }
            },
            .quit => ctx.kill(),
            else => {},
        }
    }

    const size = ctx.graphics.getDrawableSize();
    for (characters.items) |*c| {
        const curpos = c.pos;
        if (curpos.x < 0 or curpos.x + c.sprite.width > @intToFloat(f32, size.w))
            c.velocity.x = -c.velocity.x;
        if (curpos.y < 0 or curpos.y + c.sprite.height > @intToFloat(f32, size.h))
            c.velocity.y = -c.velocity.y;
        c.pos.x += c.velocity.x;
        c.pos.y += c.velocity.y;
    }

    ctx.graphics.clear(true, true, false, [_]f32{ 0.3, 0.3, 0.3, 1.0 });
    sprite_batch.begin(.{});
    for (characters.items) |c| {
        try sprite_batch.drawSprite(c.sprite, .{
            .pos = c.pos,
        });
    }
    try sprite_batch.end();

    // draw fps
    const rect = ctx.drawText("fps: {d:.1}", .{ctx.fps}, .{
        .color = .{ 1, 1, 1 },
    });
    _ = ctx.drawText("sprites number: {d}", .{characters.items.len}, .{
        .ypos = rect.next_line_ypos,
        .color = .{ 1, 1, 1 },
    });
}

fn quit(ctx: *zp.Context) void {
    _ = ctx;
    std.log.info("game quit", .{});
    sprite_sheet.deinit();
    sprite_batch.deinit();
}

pub fn main() anyerror!void {
    try zp.run(.{
        .initFn = init,
        .loopFn = loop,
        .quitFn = quit,
        .width = 1600,
        .height = 900,
        .enable_console = true,
    });
}
