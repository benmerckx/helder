package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Shader;

// A pass of a program's own at the end of a PostProcess (post.add(shader,
// bytes)): its shader drawn over the whole target, a triangle of vertices
// {pos:Vec2} in clip space (the chain's), its first texture the image the
// chain has made so far (tone mapped and graded: 8 bits), its first uniform
// block bytes. The last stage draws into the chain's output (the frame, or
// run's target: any size, its fragments' positions in that target's
// pixels), the others into targets of the run's size. Its pipelines are
// made by the chain, for what it draws into.
class PostStage {
	// its block's std140 bytes (the shader's first uniform block; null: none)
	public var bytes:Null<Bytes>;
	// how the image so far is read: Linear, or Nearest (big pixels)
	public var filter:Filter = Linear;
	// off: passed over
	public var enabled = true;
	// what else it binds before it draws (another block or texture)
	public var bind:Null<Encoder->Void> = null;

	@:allow(helder.scene.render.PostProcess) final desc:PipelineDesc;
	@:allow(helder.scene.render.PostProcess) final block:Int;
	@:allow(helder.scene.render.PostProcess) final source:Int;
	// (into the targets between, RGBA8; into the output: made when first drawn)
	@:allow(helder.scene.render.PostProcess) var middle:Null<Pipeline> = null;
	@:allow(helder.scene.render.PostProcess) var last:Null<Pipeline> = null;

	@:allow(helder.scene.render.PostProcess)
	function new<V, P>(shader:Shader<V, P>, bytes:Null<Bytes>) {
		if (shader.textures.length == 0) throw "helder.scene: a post stage's shader reads the image so far (a Texture2D parameter)";
		if (shader.layout.length != 1 || shader.layout[0].stride != 8) throw "helder.scene: a post stage's vertex is {pos:Vec2}";
		desc = shader.pipeline();
		block = shader.uniforms.length > 0 ? shader.uniforms[0].binding : -1;
		source = shader.textures[0].binding;
		this.bytes = bytes;
	}
}
