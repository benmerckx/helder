package hxmc.gfx.shader;

// A class of shader functions: static functions on the math types
// (ShaderMath) and on @:structInit classes of them, which run in CPU code as
// they are and which the shader macro (Macro) also compiles for the GPU.
// The @:vertex and @:fragment functions are a pipeline's stages:
//
//   @:structInit @:publicFields class Vertex { var pos:Vec2; var color:Vec3; }
//   @:structInit @:publicFields class Varyings { @:position var pos:Vec4; var color:Vec3; }
//
//   class TriangleShader implements Shaders {
//     @:vertex static function vs(v:Vertex):Varyings
//       return {pos: vec4(v.pos, 0, 1), color: v.color};
//     @:fragment static function fs(i:Varyings):Vec4
//       return vec4(i.color, 1);
//   }
//   device.createPipeline(TriangleShader.pipeline({topology: Triangles}));
//
// The vertex stage takes a vertex (its fields are the vertex buffer's
// attributes, in order) and returns the varyings, one of them the
// @:position; the fragment stage takes the same varyings and returns the
// colour. Further parameters of either are uniform blocks (structs of
// scalars, vectors and matrices) and textures (Texture2D, read with
// sample(t, uv)), each at a slot (Encoder.setUniforms, setTexture): 0, 1,
// ... in order of appearance, the vertex stage's first, a block shared by
// both stages (the same struct) or a texture (the same name) once. Such a
// class gets (Macro.build):
//
//   vertexCode, fragmentCode   the stages' ShaderCode, in the languages of
//                              the target (-D hxmc.gfx.shaders=glsl,wgsl,msl,hlsl
//                              or all to choose)
//   layout                     the vertex buffer's layout (Float32 attributes,
//                              packed in the vertex type's order)
//   uniforms                   the uniform blocks: name, binding (the slot), size (std140)
//   textures                   the textures: the parameter's name, binding (the slot)
//   pipeline(?options)         a PipelineDesc of all three (Device.createPipeline
//                              compiles the code)
//   vertexBytes(vertices)      the vertex buffer's contents
//   write<Uniform>(u, bytes, offset)   a uniform block's contents
//
// The conventions, the same on every back end (WebGPU's, D3D's and
// Metal's; the GLSL makes GL match): the @:position is in clip space, x
// right and y up, z from 0 (near) to w (far), its front faces counter-
// clockwise; in the fragment stage it is the fragment's position in pixels
// from the target's top left (pixel centres at .5) and its depth (0..1) in
// z; a texture's v = 0 is its first row, the top (TextureDesc), and
// readPixels returns rows top to bottom. Mat4's perspective and
// orthographic projections map to this clip space.
//
// A class without stages holds helpers for other shader classes. Haxe
// runs a build macro only from @:build or @:autoBuild, hence an interface
// (rather than a @:shader metadata). The structs are @:structInit classes
// (objects in CPU code, whose math-type fields are stored inline), so that
// vertex Arrays hold them as they are.
@:autoBuild(hxmc.gfx.shader.Macro.build())
interface Shaders {}

typedef UniformBlock = {
	// the struct's name: GLSL's block is <name>_block
	name:String,
	binding:Int,
	size:Int
}

typedef TextureBinding = {
	// the parameter's name
	name:String,
	binding:Int
}
