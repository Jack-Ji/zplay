const std = @import("std");
const assert = std.debug.assert;
const zp = @import("../../zplay.zig");
const gfx = zp.graphics;
const Context = gfx.gpu.Context;
const drawcall = gfx.gpu.drawcall;
const ShaderProgram = gfx.gpu.ShaderProgram;
const VertexArray = gfx.gpu.VertexArray;
const Renderer = gfx.Renderer;
const alg = zp.deps.alg;
const Vec2 = alg.Vec2;
const Vec3 = alg.Vec3;
const Vec4 = alg.Vec4;
const Mat4 = alg.Mat4;
const Self = @This();

const vs = ShaderProgram.shader_head ++
    \\layout (location = 0) in vec3 a_pos;
    \\
    \\uniform mat4 u_view;
    \\uniform mat4 u_project;
    \\
    \\out vec3 v_tex;
    \\
    \\void main()
    \\{
    \\    vec4 pos = u_project * u_view * vec4(a_pos, 1.0);
    \\    gl_Position = pos.xyww;
    \\    v_tex = a_pos;
    \\}
;

const fs = ShaderProgram.shader_head ++
    \\out vec4 frag_color;
    \\
    \\in vec3 v_tex;
    \\
    \\uniform samplerCube u_texture;
    \\
    \\void main()
    \\{
    \\    frag_color = texture(u_texture, v_tex);
    \\}
;

/// lighting program
program: ShaderProgram,

/// unit cube
vertex_array: VertexArray,

/// init skybox
pub fn init(allocator: std.mem.Allocator) Self {
    var self = Self{
        .program = ShaderProgram.init(vs, fs, null),
        .vertex_array = VertexArray.init(allocator, 1),
    };

    self.vertex_array.use();
    defer self.vertex_array.disuse();
    self.vertex_array.vbos[0].allocInitData(
        f32,
        &[_]f32{
            -1.0, 1.0,  -1.0,
            -1.0, -1.0, -1.0,
            1.0,  -1.0, -1.0,
            1.0,  -1.0, -1.0,
            1.0,  1.0,  -1.0,
            -1.0, 1.0,  -1.0,

            -1.0, -1.0, 1.0,
            -1.0, -1.0, -1.0,
            -1.0, 1.0,  -1.0,
            -1.0, 1.0,  -1.0,
            -1.0, 1.0,  1.0,
            -1.0, -1.0, 1.0,

            1.0,  -1.0, -1.0,
            1.0,  -1.0, 1.0,
            1.0,  1.0,  1.0,
            1.0,  1.0,  1.0,
            1.0,  1.0,  -1.0,
            1.0,  -1.0, -1.0,

            -1.0, -1.0, 1.0,
            -1.0, 1.0,  1.0,
            1.0,  1.0,  1.0,
            1.0,  1.0,  1.0,
            1.0,  -1.0, 1.0,
            -1.0, -1.0, 1.0,

            -1.0, 1.0,  -1.0,
            1.0,  1.0,  -1.0,
            1.0,  1.0,  1.0,
            1.0,  1.0,  1.0,
            -1.0, 1.0,  1.0,
            -1.0, 1.0,  -1.0,

            -1.0, -1.0, -1.0,
            -1.0, -1.0, 1.0,
            1.0,  -1.0, -1.0,
            1.0,  -1.0, -1.0,
            -1.0, -1.0, 1.0,
            1.0,  -1.0, 1.0,
        },
        .static_draw,
    );
    self.vertex_array.setAttribute(
        0,
        0,
        3,
        f32,
        false,
        0,
        0,
    );

    return self;
}

/// free resources
pub fn deinit(self: Self) void {
    self.program.deinit();
    self.vertex_array.deinit();
}

/// get renderer instance
pub fn renderer(self: *Self) Renderer {
    return Renderer.init(self, draw);
}

/// generic rendering implementation
pub fn draw(self: *Self, ctx: *Context, input: Renderer.Input) anyerror!void {
    const old_polygon_mode = ctx.polygon_mode;
    ctx.setPolygonMode(.fill);
    defer ctx.setPolygonMode(old_polygon_mode);

    const old_depth_option = ctx.depth_option;
    ctx.setDepthOption(.{ .test_func = .less_or_equal });
    defer ctx.setDepthOption(old_depth_option);

    self.program.use();
    defer self.program.disuse();

    self.vertex_array.use();
    defer self.vertex_array.disuse();

    // apply aterial
    _ = input.material.?.allocTextureUnit(0);

    // set uniforms
    var view = input.camera.?.getViewMatrix();
    view.data[3][0] = 0;
    view.data[3][1] = 0;
    view.data[3][2] = 0;
    self.program.setUniformByName("u_view", view);
    self.program.setUniformByName("u_project", input.camera.?.getProjectMatrix());
    self.program.setUniformByName(
        "u_texture",
        input.material.?.data.single_cubemap.getTextureUnit(),
    );

    // issue draw call
    drawcall.drawBuffer(.triangles, 0, 36);
}
