# @hxmc/gfx

A portable GPU layer for hxmc in pure Haxe (`hxmc.gfx`): integer handles,
immutable pipelines, back ends over GL through EGL (Linux), Metal (macOS),
Direct3D 11 (Windows), WebGPU and WebGL2 (the browser). See
`examples/Triangle.hx` and hxmc/PLANS.md, "Graphics".

Shaders are Haxe (`hxmc.gfx.shader`): static functions of a class that
implements `Shaders`, on the math types (`Vec2`, `Vec3`, `Vec4`, `Mat4`,
swizzles, operators, `ShaderMath`'s builtins) and `@:structInit` classes of
them. They run on the CPU as they are; a macro compiles the `@:vertex` and
`@:fragment` stages to GLSL ES 3.00, WGSL, MSL and HLSL (the target's only),
with the vertex layout, the uniform blocks' layout and the CPU writers:

```haxe
@:structInit @:publicFields class Vertex { var pos:Vec2; var color:Vec3; }
@:structInit @:publicFields class Varyings { @:position var pos:Vec4; var color:Vec3; }

class TriangleShader implements Shaders {
	@:vertex static function vs(v:Vertex):Varyings
		return {pos: vec4(v.pos, 0, 1), color: v.color};
	@:fragment static function fs(i:Varyings):Vec4
		return vec4(i.color, 1);
}

var pipeline = device.createPipeline(TriangleShader.pipeline({topology: Triangles}));
var bytes = TriangleShader.vertexBytes([{pos: vec2(0, 0.6), color: vec3(1, 0, 0)}, ...]);
```

`src/hxmc/gfx/shader/Shaders.hx` lists the generated members; the tests are
`test/ShaderTest.hx` (`make gfx-shader-check`).
