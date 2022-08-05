const std = @import("std");
const assert = std.debug.assert;
const Mesh = @import("Mesh.zig");
const zp = @import("../../zplay.zig");
const gfx = zp.graphics;
const Texture = gfx.gpu.Texture;
const Renderer = gfx.Renderer;
const Material = gfx.Material;
const gltf = zp.deps.gltf;
const alg = zp.deps.alg;
const Vec2 = alg.Vec2;
const Vec3 = alg.Vec3;
const Vec4 = alg.Vec4;
const Mat4 = alg.Mat4;
const Quat = alg.Quat;
const Self = @This();

pub const Error = error{
    NoRootNode,
};

/// memory allocator
allocator: std.mem.Allocator,

/// meshes
meshes: std.ArrayList(Mesh),
transforms: std.ArrayList(Mat4),

/// materials
materials: std.ArrayList(Material),
material_indices: std.ArrayList(u32),

/// loaded textures
textures: std.ArrayList(*Texture),

/// init model with mesh/transform/material, data's ownship is taken
pub fn init(
    allocator: std.mem.Allocator,
    mesh: Mesh,
    transform: Mat4,
    material: Material,
    textures: []*Texture,
) !*Self {
    var self = try allocator.create(Self);
    self.allocator = allocator;
    self.meshes = try std.ArrayList(Mesh).initCapacity(allocator, 1);
    self.transforms = try std.ArrayList(Mat4).initCapacity(allocator, 1);
    self.materials = try std.ArrayList(Material).initCapacity(allocator, 1);
    self.material_indices = try std.ArrayList(u32).initCapacity(allocator, 1);
    self.textures = try std.ArrayList(*Texture).initCapacity(allocator, textures.len);
    self.meshes.appendAssumeCapacity(mesh);
    self.transforms.appendAssumeCapacity(transform);
    self.materials.appendAssumeCapacity(material);
    self.material_indices.appendAssumeCapacity(0);
    self.textures.appendSliceAssumeCapacity(textures);
    return self;
}

/// init model with gltf file
/// WARNING: Model won't deallocate default texture,
///          cause it might be used somewhere else,
///          user's code knows better what to do with it.
pub fn fromGLTF(
    allocator: std.mem.Allocator,
    filename: [:0]const u8,
    merge_meshes: bool,
    default_texture: ?*Texture,
) !*Self {
    var data: *gltf.Data = try gltf.loadFile(filename, null);
    defer gltf.free(data);

    var self = try allocator.create(Self);
    self.allocator = allocator;
    self.meshes = try std.ArrayList(Mesh).initCapacity(allocator, 1);
    self.transforms = try std.ArrayList(Mat4).initCapacity(allocator, 1);
    self.materials = try std.ArrayList(Material).initCapacity(allocator, 1);
    self.material_indices = try std.ArrayList(u32).initCapacity(allocator, 1);
    self.textures = try std.ArrayList(*Texture).initCapacity(allocator, 1);

    // load vertex attributes
    assert(data.scenes_count > 0);
    assert(data.scene.*.nodes_count > 0);
    var root_node: ?*gltf.Node = blk: {
        var i: u32 = 0;
        while (i < data.scene.*.nodes_count) : (i += 1) {
            const node = @ptrCast(*gltf.Node, data.scene.*.nodes[i]);
            if (node.mesh != null) {
                break :blk node;
            }
        }

        // return first node by default
        break :blk @ptrCast(*gltf.Node, data.scene.*.nodes[0]);
    };
    if (root_node == null) {
        return error.NoRootNode;
    }
    self.parseNode(
        allocator,
        data,
        root_node.?,
        Mat4.identity(),
        merge_meshes,
    );

    // load images
    var i: u32 = 0;
    while (i < data.images_count) : (i += 1) {
        var image = @ptrCast(*gltf.Image, &data.images[i]);
        if (image.buffer_view != null) {
            var buffer_data = @ptrCast([*]const u8, image.buffer_view.*.buffer.*.data.?);
            var image_data = buffer_data + image.buffer_view.*.offset;
            self.textures.append(try Texture.init2DFromFileData(
                allocator,
                image_data[0..image.buffer_view.*.size],
                false,
                .{},
            )) catch unreachable;
        } else {
            var buf: [64]u8 = undefined;
            const dirname = std.fs.path.dirname(filename).?;
            const image_path = std.fmt.bufPrintZ(
                &buf,
                "{s}{s}{s}",
                .{ dirname, std.fs.path.sep_str, image.uri },
            ) catch unreachable;
            self.textures.append(try Texture.init2DFromFilePath(
                allocator,
                image_path,
                false,
                .{},
            )) catch unreachable;
        }
    }

    // default pixel data
    if (default_texture == null) {
        self.textures.append(try Texture.init2DFromPixels(
            allocator,
            &.{ 255, 255, 255, 255 },
            .rgba,
            1,
            1,
            .{},
        )) catch unreachable;
    }

    // load materials
    var default_tex = if (default_texture) |tex| tex else self.textures.items[0];
    self.materials.append(Material.init(.{
        .phong = .{
            .diffuse_map = default_tex,
            .specular_map = default_tex,
            .shiness = 32,
        },
    })) catch unreachable;
    i = 0;
    MATERIAL_LOOP: while (i < data.materials_count) : (i += 1) {
        var material = &data.materials[i];
        assert(material.has_pbr_metallic_roughness > 0);

        // TODO PBR materials
        const pbrm = material.pbr_metallic_roughness;
        const base_color_texture = pbrm.base_color_texture;

        var image_idx: u32 = 0;
        while (image_idx < data.images_count) : (image_idx += 1) {
            const image = &data.images[image_idx];
            if (base_color_texture.texture != null and
                base_color_texture.texture.*.image.*.uri == image.uri)
            {
                self.materials.append(Material.init(.{
                    .single_texture = self.textures.items[image_idx],
                })) catch unreachable;
                continue :MATERIAL_LOOP;
            }
        }

        const base_color = pbrm.base_color_factor;
        self.textures.append(try Texture.init2DFromPixels(
            allocator,
            &.{
                @floatToInt(u8, base_color[0] * 255),
                @floatToInt(u8, base_color[1] * 255),
                @floatToInt(u8, base_color[2] * 255),
                @floatToInt(u8, base_color[3] * 255),
            },
            .rgba,
            1,
            1,
            .{},
        )) catch unreachable;
        self.materials.append(Material.init(.{
            .single_texture = self.textures.items[self.textures.items.len - 1],
        })) catch unreachable;
    }

    // TODO load skins
    // TODO load animations

    // setup meshes' vertex buffer
    for (self.meshes.items) |*m| {
        m.setup(allocator);
    }
    return self;
}

/// deallocate resources
pub fn deinit(self: *Self) void {
    for (self.meshes.items) |m| {
        m.deinit();
    }
    self.meshes.deinit();
    self.transforms.deinit();
    self.materials.deinit();
    self.material_indices.deinit();
    for (self.textures.items) |t| {
        t.deinit();
    }
    self.textures.deinit();
    self.allocator.destroy(self);
}

fn parseNode(
    self: *Self,
    allocator: std.mem.Allocator,
    data: *gltf.Data,
    node: *gltf.Node,
    parent_transform: Mat4,
    merge_meshes: bool,
) void {
    // load transform matrix
    var transform = Mat4.identity();
    if (node.has_matrix > 0) {
        transform = Mat4.fromSlice(&node.matrix).mul(transform);
    } else {
        if (node.has_scale > 0) {
            transform = Mat4.fromScale(Vec3.fromSlice(&node.scale)).mul(transform);
        }
        if (node.has_rotation > 0) {
            var quat = Quat.new(
                node.rotation[3],
                node.rotation[0],
                node.rotation[1],
                node.rotation[2],
            );
            transform = quat.toMat4().mul(transform);
        }
        if (node.has_translation > 0) {
            transform = Mat4.fromTranslate(Vec3.fromSlice(&node.translation)).mul(transform);
        }
    }
    transform = parent_transform.mul(transform);

    // load meshes
    if (node.mesh != null) {
        var i: u32 = 0;
        while (i < node.mesh.*.primitives_count) : (i += 1) {
            const primitive = @ptrCast(*gltf.Primitive, &node.mesh.*.primitives[i]);
            const primtype = gltf.getPrimitiveType(primitive);

            // get material index
            const material_index = blk: {
                var index: u32 = 0;
                while (index < data.materials_count) : (index += 1) {
                    const material = @ptrCast([*c]gltf.Material, &data.materials[index]);
                    if (material == primitive.material) {
                        break :blk index + 1;
                    }
                }
                break :blk 0;
            };

            var mergable_mesh: ?*Mesh = null;
            if (merge_meshes) {
                // TODO: there maybe more conditions
                // find mergable mesh, following conditions must be met:
                // 1. same primitive type
                // 2. same transform matrix
                // 3. same material
                mergable_mesh = for (self.meshes.items) |*m, idx| {
                    if (m.primitive_type == primtype and
                        self.transforms.items[idx].eql(transform) and
                        self.material_indices.items[idx] == material_index)
                    {
                        break m;
                    }
                } else null;
            }

            if (mergable_mesh) |m| {
                // merge into existing mesh
                gltf.appendMeshPrimitive(
                    primitive,
                    &m.indices,
                    &m.positions,
                    &m.normals.?,
                    &m.texcoords.?,
                    null,
                );
            } else {
                // allocate new mesh
                var positions = std.ArrayList(f32).init(allocator);
                var indices = std.ArrayList(u32).init(allocator);
                var normals = std.ArrayList(f32).init(allocator);
                var texcoords = std.ArrayList(f32).init(allocator);
                gltf.appendMeshPrimitive(
                    primitive,
                    &indices,
                    &positions,
                    &normals,
                    &texcoords,
                    null,
                );
                self.meshes.append(Mesh.fromArrays(
                    primtype,
                    indices,
                    positions,
                    normals,
                    texcoords,
                    null,
                    null,
                    true,
                )) catch unreachable;
                self.transforms.append(transform) catch unreachable;
                self.material_indices.append(material_index) catch unreachable;
            }
        }
    }

    // parse node's children
    var i: u32 = 0;
    while (i < node.children_count) : (i += 1) {
        self.parseNode(
            allocator,
            data,
            @ptrCast(*gltf.Node, node.children[i]),
            transform,
            merge_meshes,
        );
    }
}

/// allocate texture units for materials
pub fn allocTextureUnit(self: Self, start_unit: i32) i32 {
    var unit: i32 = start_unit;
    for (self.materials.items) |mr| {
        unit = mr.allocTextureUnit(unit);
    }
    return unit;
}

/// range of mesh in vds
pub const MeshRange = struct {
    begin: u32,
    end: u32,
};

/// allocate render data, return vds range
pub fn appendVertexData(
    self: Self,
    input: *Renderer.Input,
    transform: Mat4,
    material: ?*Material,
) !MeshRange {
    const begin = @intCast(u32, input.vds.?.items.len);
    for (self.meshes.items) |m, i| {
        // add vertex data of mesh #i
        try input.vds.?.append(m.getVertexData(
            if (material) |mr| mr else &self.materials.items[self.material_indices.items[i]],
            Renderer.LocalTransform{
                .single = transform.mul(self.transforms.items[i]),
            },
        ));
    }

    return MeshRange{
        .begin = begin,
        .end = @intCast(u32, input.vds.?.items.len),
    };
}

/// append render data for instanced rendering, return vds range
/// WARNING: user code is responssible for releasing InstanceTransformArray
pub fn appendVertexDataInstanced(
    self: Self,
    allocator: std.mem.Allocator,
    input: *Renderer.Input,
    transforms: []Mat4,
    material: ?*Material,
) !MeshRange {
    assert(transforms.len > 0);
    var temp = try std.ArrayList(Mat4).initCapacity(allocator, transforms.len);
    defer temp.deinit();

    const begin = @intCast(u32, input.vds.?.items.len);
    for (self.meshes.items) |m, i| {
        // compose transform array for mesh #i
        for (temp.items) |_, j| {
            temp.items[j] = transforms[j].mul(self.transforms.items[i]);
        }
        var trs = Renderer.InstanceTransformArray.init(allocator) catch unreachable;
        trs.updateTransforms(temp.items) catch unreachable;

        // add vertex data of mesh #i
        try input.vds.?.append(m.getVertexData(
            if (material) |mr| mr else &self.materials.items[self.material_indices.items[i]],
            Renderer.LocalTransform{ .instanced = trs },
        ));
    }

    return MeshRange{
        .begin = begin,
        .end = @intCast(u32, input.vds.?.items.len),
    };
}

/// properly fill transforms
pub fn fillTransforms(
    self: Self,
    vds: []Renderer.Input.VertexData,
    transform: Mat4,
) void {
    assert(vds.len == self.meshes.items.len);
    for (self.meshes.items) |_, i| {
        vds[i].transform.single = transform.mul(self.transforms.items[i]);
    }
}

/// properly fill instanced transform arrays
pub fn fillInstanceTransformArray(
    self: Self,
    vds: []Renderer.Input.VertexData,
    transforms: []Mat4,
    temp: ?[]Mat4,
) !void {
    assert(vds.len == self.meshes.items.len);
    var ms = temp orelse try std.heap.c_allocator.alloc(Mat4, transforms.len);
    assert(transforms.len == ms.len);
    defer if (temp == null) std.heap.c_allocator.free(ms);

    for (self.meshes.items) |_, i| {
        for (transforms) |tr, j| {
            ms[j] = tr.mul(self.transforms.items[i]);
        }
        try vds[i].transform.instanced.updateTransforms(ms);
    }
}
