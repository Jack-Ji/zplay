const std = @import("std");
const assert = std.debug.assert;
const zp = @import("../../zplay.zig");
const gfx = zp.graphics;
const Context = gfx.gpu.Context;
const VertexArray = gfx.gpu.VertexArray;
const drawcall = gfx.gpu.drawcall;
const ShaderProgram = gfx.gpu.ShaderProgram;
const Material = gfx.Material;
const Renderer = gfx.Renderer;
const alg = zp.deps.alg;
const Vec2 = alg.Vec2;
const Vec3 = alg.Vec3;
const Vec4 = alg.Vec4;
const Mat4 = alg.Mat4;
const Self = @This();

/// number of floats per vertex
pub const float_num_of_vertex_attrib = 8;

const vs_body =
    \\layout (location = 0) in vec3 a_pos;
    \\layout (location = 1) in vec3 a_color;
    \\layout (location = 2) in vec2 a_tex;
    \\
    \\uniform mat4 u_project;
    \\
    \\out vec3 v_color;
    \\out vec2 v_tex;
    \\
    \\void main()
    \\{
    \\    gl_Position = u_project * vec4(a_pos, 1.0);
    \\    v_color = a_color;
    \\    v_tex = a_tex;
    \\}
;

const fs_body =
    \\out vec4 frag_color;
    \\
    \\in vec3 v_color;
    \\in vec2 v_tex;
    \\
    \\uniform sampler2D u_texture;
    \\
    \\void main()
    \\{
    \\    frag_color = vec4(v_color, texture(u_texture, v_tex).r);
    \\}
;

const vs = ShaderProgram.shader_head ++ vs_body;
const fs = ShaderProgram.shader_head ++ fs_body;

/// shader programs
program: ShaderProgram = undefined,

/// create a simple renderer
pub fn init() Self {
    var self = Self{};
    self.program = ShaderProgram.init(vs, fs, null);
    return self;
}

/// get vertex array ready for rendering font
pub fn setupVertexArray(va: VertexArray) void {
    assert(va.vbo_num > 0);
    va.use();
    defer va.disuse();
    va.setAttribute(0, 0, 3, f32, false, 8 * @sizeOf(f32), 0);
    va.setAttribute(0, 1, 3, f32, false, 8 * @sizeOf(f32), 3 * @sizeOf(f32));
    va.setAttribute(0, 2, 2, f32, false, 8 * @sizeOf(f32), 6 * @sizeOf(f32));
}

/// free resources
pub fn deinit(self: *Self) void {
    self.program.deinit();
}

/// get renderer instance
pub fn renderer(self: *Self) Renderer {
    return Renderer.init(self, draw);
}

/// generic rendering implementation
pub fn draw(self: *Self, ctx: *Context, input: Renderer.Input) anyerror!void {
    var old_polygon_mode = ctx.polygon_mode;
    var old_depth_test = ctx.isCapabilityEnabled(.depth_test);
    var old_stencil_test = ctx.isCapabilityEnabled(.stencil_test);
    var old_blend = ctx.isCapabilityEnabled(.blend);
    const old_blend_option = ctx.blend_option;
    ctx.setPolygonMode(.fill);
    ctx.toggleCapability(.depth_test, false);
    ctx.toggleCapability(.stencil_test, false);
    ctx.toggleCapability(.blend, true);
    ctx.setBlendOption(.{});
    defer ctx.setPolygonMode(old_polygon_mode);
    defer ctx.toggleCapability(.depth_test, old_depth_test);
    defer ctx.toggleCapability(.stencil_test, old_stencil_test);
    defer ctx.toggleCapability(.blend, old_blend);
    defer {
        if (old_blend) ctx.setBlendOption(old_blend_option);
    }

    if (input.vds == null or input.vds.?.items.len == 0) return;
    self.program.use();
    defer self.program.disuse();

    // apply common uniform vars
    self.program.setUniformByName("u_project", if (input.camera) |c|
        c.getProjectMatrix()
    else
        Mat4.orthographic(
            0,
            @intToFloat(f32, ctx.viewport.w),
            @intToFloat(f32, ctx.viewport.h),
            0,
            -1,
            1,
        ));

    // render vertex data one by one
    var current_material: *const Material = undefined;
    for (input.vds.?.items) |vd| {
        if (!vd.valid) continue;
        if (vd.count == 0) continue;
        vd.vertex_array.use();
        defer vd.vertex_array.disuse();

        // apply material
        var material = vd.material orelse input.material;
        if (material) |mr| {
            if (mr != current_material) {
                current_material = mr;
                _ = current_material.allocTextureUnit(0);
                switch (mr.data) {
                    .single_texture => |tex| {
                        self.program.setUniformByName("u_texture", tex.getTextureUnit());
                    },
                    else => {
                        std.debug.panic("unsupported material type", .{});
                    },
                }
            }
        }

        // send draw command
        drawcall.drawBuffer(vd.primitive, vd.offset, vd.count);
    }
}
