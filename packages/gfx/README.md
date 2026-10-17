# @hxmc/gfx

A portable GPU layer for hxmc in pure Haxe (`hxmc.gfx`): integer handles,
immutable pipelines, back ends over GL through EGL (Linux, Android: GLES 3.0
on the activity's window), Metal (macOS),
Direct3D 11 (Windows), WebGPU and WebGL2 (the browser). See
`examples/Triangle.hx` (the least a program needs), `examples/Cube.hx`
(textures, depth, uniforms, blending, indices), `examples/Instances.hx`
(instanced draws) and the design notes and what is left in
docs/plans/graphics.md.

## API

Resources are made up front from descriptors (allocating there is fine);
a frame records passes through the device's one `Encoder` and allocates
nothing in the layer.

```haxe
var device = Device.create(window.surface);          // or Surface.headless(w, h)
var vb = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
var ib = device.createBuffer({size: indices.length, usage: Index, data: indices});
device.writeBuffer(vb, 0, newBytes);                  // later updates
var tex = device.createTexture({width: 64, height: 64, format: RGBA8, data: texels});
device.writeTexture(tex, texels);                     // all of it, or a region: (tex, bytes, x, y, w, h)
device.destroyTexture(tex);                           // (and destroyBuffer)
var smp = device.createSampler({filter: Linear, wrap: Repeat});
var pipeline = device.createPipeline(CubeShader.pipeline({
	cull: Back, depthCompare: Less, depthWrite: true, blend: Opaque // or Alpha, Additive, Premultiplied
}));

var enc = device.beginFrame();                        // null: no frame now (a hidden window)
enc.beginPass({colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}], depth: {load: Clear}});
enc.setPipeline(pipeline);
CubeShader.writeCubeCamera({mvp: mvp, model: model}, bytes); // a uniform block's std140 bytes
enc.setUniforms(0, bytes);                            // its slot: into the frame's uniform ring
enc.setTexture(1, tex, smp);
enc.setVertexBuffer(0, vb);
enc.setIndexBuffer(ib, UInt16);                       // or UInt32
enc.drawIndexed(36);                                  // or draw(vertices)
enc.endPass();
device.endFrame();                                    // submit and present
```

Slots: a shader's uniform blocks and textures (its parameters after the
stage's input) are numbered 0, 1, ... in order of appearance, the vertex
stage's first; the generated `uniforms` and `textures` lists give each
one's `binding`. `setUniforms` copies the block into the frame's uniform
ring (`Encoder.UNIFORM_RING` bytes a frame, 256-byte aligned blocks; one
ring per frame in flight; Metal: `setVertexBytes`, at most 4 KB a block).
The device has a depth buffer of the target's size; `PassDesc.depth`
clears or keeps it. `Device.readPixels` reads the frame back (tests,
screenshots; on WebGPU, `readPixels` in `imports.mjs`, asynchronously).

Instancing: a vertex buffer slot whose layout has `step: Instance` advances
once per instance instead of once per vertex (GL's and WebGL2's attribute
divisor 1, D3D11's per-instance input slots, Metal's per-instance step
function, WebGPU's `stepMode: 'instance'`); `draw` and `drawIndexed` take
the instance count, and `drawIndexed`'s base vertex moves the per-vertex
buffers only. A shader reads both kinds of attributes from its one input
struct; the pipeline's layout says which buffer each location comes from:

```haxe
var d = InstancesShader.pipeline();
d.layout = [
	{stride: 8, attributes: [{location: 0, format: Float2, offset: 0}]},  // the shape's corners
	{stride: 28, step: Instance, attributes: [                             // each instance's
		{location: 1, format: Float2, offset: 0}, {location: 2, format: Float1, offset: 8},
		{location: 3, format: Float1, offset: 12}, {location: 4, format: Float3, offset: 16}
	]}
];
var pipeline = device.createPipeline(d);
...
enc.setVertexBuffer(0, shapes);
enc.setVertexBuffer(1, instances, first * 28);       // the instances from first
enc.drawIndexed(6, count);                            // count instances of the quad
```

Conventions, the same on every back end: clip space y up and z from 0
(near) to w (far), counter-clockwise front faces; the fragment position in
pixels from the target's top left; a texture's first row is its top
(v = 0); `readPixels` rows top to bottom. `Mat4.perspective` and
`Mat4.orthographic` project into that clip space. The GLSL the shader macro
emits makes GL match (its clip z and `gl_FragCoord.y` differ).

## Shaders

Shaders are Haxe (`hxmc.gfx.shader`): static functions of a class that
implements `Shaders`, on the math types (`Vec2`, `Vec3`, `Vec4`, `Mat4`,
swizzles, operators, `ShaderMath`'s builtins), `@:structInit` classes of
them and `Texture2D` parameters. They run on the CPU as they are; a macro
compiles the `@:vertex` and `@:fragment` stages to GLSL ES 3.00, WGSL, MSL
and HLSL (the target's only), with the vertex layout, the uniform blocks'
layout, the slots and the CPU writers:

```haxe
@:structInit @:publicFields class Vertex { var pos:Vec2; var uv:Vec2; }
@:structInit @:publicFields class Varyings { @:position var pos:Vec4; var uv:Vec2; }
@:structInit @:publicFields class Tint { var color:Vec4; }

class SpriteShader implements Shaders {
	@:vertex static function vs(v:Vertex):Varyings
		return {pos: vec4(v.pos, 0, 1), uv: v.uv};
	@:fragment static function fs(i:Varyings, tint:Tint, image:Texture2D):Vec4
		return sample(image, i.uv) * tint.color;   // slots: tint 0, image 1
}

var pipeline = device.createPipeline(SpriteShader.pipeline({blend: Alpha}));
var bytes = SpriteShader.vertexBytes([{pos: vec2(0, 0.6), uv: vec2(0.5, 0)}, ...]);
```

`src/hxmc/gfx/shader/Shaders.hx` lists the generated members; the tests are
`test/ShaderTest.hx` (`make gfx-shader-check`) and GfxTest and WebTest,
the examples' frames against `test/triangle.png` and `test/cube.png` on
each back end (`make gfx-check`, `make gfx-web-check`).
