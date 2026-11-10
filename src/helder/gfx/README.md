# helder.gfx

A portable GPU layer for hxmc in pure Haxe (`helder.gfx`): integer handles,
immutable pipelines, back ends over GL through EGL (Linux, Android: GLES 3.0
on the activity's window), Metal (macOS, iOS),
Direct3D 11 (Windows), WebGPU and WebGL2 (the browser). See
`examples/triangle/Triangle.hx` (the least a program needs), `examples/cube/Cube.hx`
(textures, depth, uniforms, blending, indices), `examples/instances/Instances.hx`
(instanced draws), `examples/cube/Targets.hx` (render targets),
`examples/mips/Mips.hx` (mip maps) and `examples/formats/Formats.hx` (texture formats).

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
device.writeTexture(tex, texels);                     // all of it, or a region: (tex, bytes, x, y, w, h[, offset, level])
device.destroyTexture(tex);                           // (and destroyBuffer)
var smp = device.createSampler({filter: Linear, wrap: Repeat});
var pipeline = device.createPipeline(CubeShader.pipeline({
	cull: Back, depthCompare: Less, depthWrite: true, blend: Opaque // or Alpha, Additive (src + dst), Premultiplied, Multiply (dst * src: a tint)
}));

var enc = device.beginFrame();                        // null: no frame now (a hidden window)
enc.beginPass({colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}], depth: {load: Clear}});
enc.setPipeline(pipeline);
CubeShader.params.cam.write({mvp: mvp, model: model}, bytes); // a uniform block's std140 bytes
enc.setUniforms(0, bytes);                            // its slot: into the frame's uniform ring
enc.setTexture(1, tex, smp);
enc.setVertexBuffer(0, vb);
enc.setIndexBuffer(ib, UInt16);                       // or UInt32
enc.drawIndexed(36);                                  // or draw(vertices)
enc.endPass();
device.endFrame();                                    // submit and present
```

Slots: a shader's uniform blocks and textures (the fields of each stage's
object of parameters, its second parameter) are numbered 0, 1, ... in
order of appearance, the vertex stage's first; the generated `uniforms`
and `textures` lists give each one's `binding`, as do `params.<field>`
(`.block.binding` of a writer, `.binding` of a texture's slot). `setUniforms` copies the block into the frame's uniform
ring (`Encoder.UNIFORM_RING` bytes a frame, 256-byte aligned blocks; one
ring per frame in flight; Metal: `setVertexBytes`, at most 4 KB a block).
The device has a depth buffer of the target's size; `PassDesc.depth`
clears or keeps it. `Device.readPixels` reads the frame back (tests,
screenshots; on WebGPU, `readPixels` in `imports.mjs`, asynchronously).

Antialiasing: `Device.create(window.surface, {antialias: true})`
multisamples a window's frames, 4 samples a pixel (Metal: a multisampled
colour and depth texture resolved into the drawable at each pass's end;
GL: an EGL config with 4 samples, when there is one; D3D11: a
multisampled colour and depth texture resolved into the back buffer before
`Present`, when the device has 4 samples; in the browser the page's
`antialias` run option decides when it is set, else the device's option:
WebGPU a multisampled colour and depth texture, WebGL2 the context's
antialias). Headless surfaces stay single-sampled; `readPixels` reads the
frame resolved. helder.ui's `<Surface>` (UiWindow) asks for it by default
(`antialias={false}`: one sample), and so does a `<Scene>`'s box.

Multisampled render targets: a render target or depth texture made with
`samples: 4` (RGBA8, RGBA8Srgb, RGBA16F or a depth format, one level) is
drawn into by pipelines made with `PipelineDesc.samples = 4` and never
sampled; the pass's colour is resolved at its end into
`ColorTarget.resolve`, a single-sampled render target of its size and
format, which is then sampled as usual (GL and WebGL2: a multisampled
renderbuffer blitted into the texture; Metal: a 2D multisample texture and
its resolve texture; D3D11: `ResolveSubresource`; WebGPU: the attachment's
`resolveTarget`). `examples/cube/Targets.hx` with `samples` 4 is the
`msaa` frame of the gfx lanes (tests/gfx/msaa.png: GL, D3D11 under Wine,
WebGPU and WebGL2 in Chromium; Metal on CI's macOS):

```haxe
var multi = device.createTexture({width: w, height: h, renderTarget: true, samples: 4});
var depth = device.createTexture({width: w, height: h, format: Depth32F, samples: 4});
var color = device.createTexture({width: w, height: h, renderTarget: true});
enc.beginPass({colors: [{load: Clear, texture: multi, resolve: color}], depth: {load: Clear, texture: depth}});
```

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

Textures: `TextureFormat` has the formats every back end has: `RGBA8`,
`RGBA8Srgb` (decoded when sampled, encoded when rendered to), `R8`, `RG8`,
`RGBA16F` (half floats), `R32F` and the depth formats `Depth16` and
`Depth32F`; data is `format.texelSize` bytes a texel. R32F and depth
textures are not filterable everywhere: they are read through a sampler of
`Nearest` filters and have no generated mip levels. `Device.textureBytes`
counts the bytes of the textures alive (their levels and samples, as
their formats store them): the GPU memory a scene's textures take.

Mip maps: `mipLevels` levels (0: all of them, down to 1x1), each written
with `writeTexture`'s level or generated from the first (GL's
`glGenerateMipmap`, D3D11's `GenerateMips`, Metal's blit, a small pass on
WebGPU; outside a pass); a sampler's `mipFilter` reads between them
(`Linear` with `filter: Linear`: trilinear; none: the first level only):

```haxe
var checks = device.createTexture({width: 256, height: 256, mipLevels: 0, data: texels});
device.generateMips(checks);                          // or writeTexture(t, bytes, 0, 0, -1, -1, 0, level)
var trilinear = device.createSampler({filter: Linear, mipFilter: Linear});
```

Render targets: a texture made with `renderTarget: true` (and every depth
texture) is a pass's colour target (`ColorTarget.texture`) or depth target
(`DepthTarget.texture`, of the same size; a pass into a texture has a depth
buffer only when it names one), filled by passes (not data), then sampled
like any texture (after `endPass`). Metal and WebGPU make a pipeline for
its targets' formats: `PipelineDesc.colorFormat` and `depthFormat` (by
default the frame's colour and the device's depth buffer):

```haxe
var color = device.createTexture({width: 128, height: 128, renderTarget: true});
var depth = device.createTexture({width: 128, height: 128, format: Depth32F});
var d = SceneShader.pipeline({depthCompare: Less, depthWrite: true});
d.colorFormat = RGBA8;
d.depthFormat = Depth32F;
var offscreen = device.createPipeline(d);
...
enc.beginPass({colors: [{load: Clear, texture: color}], depth: {load: Clear, texture: depth}});
enc.setPipeline(offscreen);                           // ... draw into it
enc.endPass();
enc.beginPass(framePass);
enc.setTexture(1, color, sampler);                    // ... and sample it
```

Shared textures: a render target another process samples without a copy
(helder.story's native preview host draws each screen into one, the
studio composites it). `Device.sharing` says how: `"iosurface"` (Metal: an
IOSurface found by its id), `"dxgi"` (Direct3D 11: a texture with a keyed
mutex, by its DXGI shared handle; a frame holds the mutex from the first
draw that samples it, or from beginFrame into it, to endFrame), `"dmabuf"`
(GL: exported with EGL_MESA_image_dma_buf_export, its descriptor taken by
the other process with pidfd_getfd and imported with
EGL_EXT_image_dma_buf_import), or null (WebGPU, WebGL2, Android, an EGL
without those: llvmpipe without udmabuf; `HELDER_NO_DMABUF=1`). A frame
into a shared texture waits for the GPU at `endFrame`, so its pixels are
complete when the other process is told; the producer does not draw into a
texture the consumer is sampling (helder.story keeps buffers for that).
`tests/gfx/SharedTexture.hx` is the gfx-shared lane's check, two processes:

```haxe
var s = device.createShared(w, h);                   // null: no sharing here
device.frameInto(s.texture);                          // the next frames into it (null: the surface again)
var enc = device.beginFrame(); ... device.endFrame(); // complete: give s.handle to the other process
var t = other.openShared(handle, w, h);               // there: a texture to sample (destroyTexture when done)
```

Conventions, the same on every back end: clip space y up and z from 0
(near) to w (far), counter-clockwise front faces; the fragment position in
pixels from the target's top left; a texture's first row is its top
(v = 0), a render target's too (GL renders into it upside down, its front
faces clockwise, so that it reads alike); `readPixels` rows top to bottom. `Mat4.perspective` and
`Mat4.orthographic` project into that clip space. The GLSL a shader definition
emits makes GL match (its clip z and `gl_FragCoord.y` differ).

## Shaders

Shaders are Haxe (`helder.gfx.shader`): a definition, `shader({vertex,
fragment})` (src/helder/compiler/DESIGN.md), of functions on the math types
(`Vec2`, `Vec3`, `Vec4`, `Mat4`, swizzles, operators, `ShaderMath`'s
builtins), structs of them (`@:structInit` classes, typedefs of anonymous
structures) and `Texture2D` parameters (`sample(t, uv)`: in the fragment
stage at the mip level the fragment's footprint needs, in the vertex stage
the first; `sampleLevel(t, uv, level)` at a given one; `discard()`, a
statement of the fragment stage, drops the fragment: alpha testing). The
stages call any static or module-level function of those values. They run
on the CPU as they are; the definition compiles them, when the program is
built, to GLSL ES 3.00, WGSL, MSL and HLSL (the target's only), with the
vertex layout, the uniform blocks' layout, the slots and the CPU writers:

```haxe
@:structInit @:publicFields class Vertex { var pos:Vec2; var uv:Vec2; }
@:structInit @:publicFields class Varyings { var pos:Vec4; var uv:Vec2; }
@:structInit @:publicFields class Tint { var color:Vec4; }

final SpriteShader = shader({
	vertex: function(v:Vertex):Varyings
		return {pos: position(vec4(v.pos, 0, 1)), uv: v.uv},  // position: the clip-space position
	fragment: function(i:Varyings, p:{tint:Tint, image:Texture2D}):Vec4
		return sample(p.image, i.uv) * p.tint.color   // slots: tint 0, image 1
});

var pipeline = device.createPipeline(SpriteShader.pipeline({blend: Alpha}));
var bytes = SpriteShader.vertexBytes([{pos: vec2(0, 0.6), uv: vec2(0.5, 0)}, ...]);
SpriteShader.params.tint.write({color: vec4(1)}, uniformBytes);   // std140
enc.setTexture(SpriteShader.params.image.binding, texture, sampler);
```

A stage takes its input and, optionally, one object of parameters (an
anonymous structure, written out or a typedef): its fields, in order, are
the stage's uniform blocks and textures, read as `p.tint`; a field both
stages name is one resource. `params` has a field for each: a uniform
block's writer (`UniformWriter`), a texture's slot (`TextureSlot`).

A shader written once with parts to replace is a slot object,
`slots({vertex, fragment, options, <slot>: ...})` (`Slots`): its stages
take the object as a third parameter, `m.options.<name>` an option and
`m.<slot>(s, p)` a slot (a function with a default; its own parameters
the stage's of the same names, the others joining them). `variant(options)`
is a shader compiled at build time with the options folded (an `if` on
one takes its branch, a loop over constants is unrolled), the slots
inlined and what it never reads of the optional fields (`@:optional`:
vertex attributes, varyings, parameters) dropped; `with({<slot>: ...})`
replaces slots. helder.scene's standard material is one (`pbr`).

`uniform(value)` (a module-level final) is a value the CPU sets
(`time.value = t`) and any stage reads as `time.value`: a shader that
reads uniforms gets a block of them, `Uniforms` (a field each, in the
order first read; `params.uniforms`), `uniformBytes()` the block with
their values now, `bind(encoder)` binding it at `uniformBinding`.

In TypeScript, `import {shader, position, vec4, ...} from "helder/gfx"`: the
same definition with the operators as methods (`a.mul(b)`) and type
aliases as the structs, compiled to the same text (helder.typescript's
README): `fragment: (i, p: {tint: Tint, image: Texture2D}) => ...`, its
`params` typed by `Params<P>` (a `TextureSlot` for a `Texture2D` field,
a `UniformWriter<T>` for the others).

`src/helder/gfx/shader/Shader.hx` lists the generated members; the tests are
`tests/gfx/ShaderTest.hx` (`bun run test gfx-shader`) and GfxTest and WebTest,
the examples' frames against `tests/gfx/<scene>.png` (triangle, cube,
instances, targets, mips, formats) on each back end (`bun run test gfx`, `bun run test gfx-web`).
