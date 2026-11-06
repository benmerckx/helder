package helder.gfx.shader;

import haxe.io.Bytes;
import helder.gfx.PipelineDesc;
import helder.gfx.ShaderCode;
import helder.gfx.VertexBufferLayout;

// A shader: what shader({vertex, fragment}) makes (ShaderMath.shader, a
// definition: DESIGN.md in src/helder/compiler), its stages' functions
// compiled at build time:
//
//   @:structInit @:publicFields class Vertex { var pos:Vec2; var color:Vec3; }
//   @:structInit @:publicFields class Varyings { var pos:Vec4; var color:Vec3; }
//
//   final TriangleShader = shader({
//     vertex: function(v:Vertex):Varyings return {pos: position(vec4(v.pos, 0, 1)), color: v.color},
//     fragment: function(i:Varyings):Vec4 return vec4(i.color, 1)
//   });
//   device.createPipeline(TriangleShader.pipeline({topology: Triangles}));
//
// The vertex function takes a vertex (its fields are the vertex buffer's
// attributes, in order) and returns the varyings, one of them built
// position(...): the clip-space position; the fragment function takes the
// same varyings (its first parameter's type may be left out) and returns
// the colour. Either may take one more parameter, an object of parameters
// (an anonymous structure: function(i:Varyings, p:{cam:Camera, image:Texture2D})),
// whose fields, read as p.cam, are uniform blocks (structs of scalars,
// vectors and matrices) and textures (Texture2D, read with sample(t, uv)),
// each at a slot (Encoder.setUniforms, setTexture): 0, 1, ... in order of
// appearance, the vertex stage's first, a block shared by both stages (the
// same struct) or a texture (the same name) once. Structs
// are @:structInit classes (objects in CPU code, whose math-type fields are
// stored inline, so that vertex Arrays hold them as they are) or typedefs
// of anonymous structures. The functions they call are any static or
// module-level functions of the same kinds of values (helpers, as the
// stages are: they run as CPU code too). The shader has:
//
//   vertexCode, fragmentCode   the stages' ShaderCode, in the languages of
//                              the target (-D helder.gfx.shaders=glsl,wgsl,msl,hlsl
//                              or all to choose)
//   layout                     the vertex buffer's layout (Float32 attributes,
//                              packed in the vertex type's order)
//   uniforms                   the uniform blocks: name, binding (the slot), size (std140)
//   textures                   the textures: the parameter's name, binding (the slot)
//   pipeline(?options)         a PipelineDesc of all three (Device.createPipeline
//                              compiles the code)
//   vertexBytes(vertices)      the vertex buffer's contents
//   params.<name>              a field of the stages' objects of parameters:
//                              a uniform block's writer (UniformWriter:
//                              .write(u, bytes, offset), std140) or a
//                              texture's slot (TextureSlot: .binding)
//   vertex, fragment           the stages as CPU code
//   uniformBytes(), uniformBinding, bind(encoder)
//                              the block of the uniform(...)s the stages
//                              read (ShaderMath.uniform), their values now
//
// (Each shader is a class of its own extending Shader, made by the
// definition beside its module: <Module>_<name>, its stages' fields of
// their exact function types, which hxmc calls directly.)
//
// The conventions, the same on every back end (WebGPU's, D3D's and
// Metal's; the GLSL makes GL match): the position is in clip space, x
// right and y up, z from 0 (near) to w (far), its front faces counter-
// clockwise; in the fragment stage it is the fragment's position in pixels
// from the target's top left (pixel centres at .5) and its depth (0..1) in
// z; a texture's v = 0 is its first row, the top (TextureDesc), and
// readPixels returns rows top to bottom. Mat4's perspective and
// orthographic projections map to this clip space.
class Shader<V, P> {
	public final vertexCode:ShaderCode;
	public final fragmentCode:ShaderCode;
	public final layout:Array<VertexBufferLayout>;
	public final uniforms:Array<UniformBlock>;
	public final textures:Array<TextureBinding>;
	public final params:P;

	final writeVertices:Array<V>->Bytes;

	public function new(vertexCode, fragmentCode, layout, uniforms, textures, writeVertices, params) {
		this.vertexCode = vertexCode;
		this.fragmentCode = fragmentCode;
		this.layout = layout;
		this.uniforms = uniforms;
		this.textures = textures;
		this.writeVertices = writeVertices;
		this.params = params;
	}

	// the pipeline of both stages and the vertex layout (Device.createPipeline compiles the code)
	public function pipeline(?options:PipelineOptions):PipelineDesc
		return options == null ? {program: {vertex: vertexCode, fragment: fragmentCode}, layout: layout} : {
			program: {vertex: vertexCode, fragment: fragmentCode},
			layout: layout,
			topology: options.topology,
			cull: options.cull,
			blend: options.blend,
			depthCompare: options.depthCompare,
			depthWrite: options.depthWrite
		};

	// the vertex buffer's contents
	public function vertexBytes(vertices:Array<V>):Bytes
		return writeVertices(vertices);

	// the slot of the block of the uniform(...)s the stages read (-1: none)
	public var uniformBinding(default, null) = -1;

	// that block with the uniforms' values now (null: none; a shader that
	// reads them binds it with bind(encoder) on a GPU's target)
	public function uniformBytes():Null<Bytes>
		return null;
}

typedef PipelineOptions = {
	?topology:helder.gfx.Topology,
	?cull:helder.gfx.Cull,
	?blend:helder.gfx.Blend,
	?depthCompare:helder.gfx.Compare,
	?depthWrite:Bool
}

// a uniform block's writer: the block's struct at offset, std140
// (bytes.length >= offset + size)
class UniformWriter<T> {
	public final block:UniformBlock;

	final store:(T, Bytes, Int) -> Void;

	public function new(block, store) {
		this.block = block;
		this.store = store;
	}

	public inline function write(value:T, bytes:Bytes, offset = 0)
		store(value, bytes, offset);
}

// a texture parameter's slot (Encoder.setTexture(slot.binding, ...))
class TextureSlot {
	// the parameter's name
	public final name:String;
	public final binding:Int;

	public function new(name, binding) {
		this.name = name;
		this.binding = binding;
	}
}

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
