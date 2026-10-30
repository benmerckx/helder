package helder.scene.render;

import helder.gfx.*;

// Normal maps drawn, opted in (renderer.use(new NormalMaps(device))):
// PbrNormalShader's pipelines for primitives with tangents whose material
// has a normalTexture (glTF's, tangents from the file or computed when
// loaded: models loaded after it is made). Without it those primitives are drawn with the standard shader
// (their tangents unread, the map ignored), and a program links no
// normal-map shader. Instanced runs are drawn with the map too
// (PbrInstancedNormalShader); skinned draws keep their own shader (the map
// ignored) for now.
class NormalMaps implements RenderFeature implements RenderFeature.NormalSource {
	// (the vertices as the standard layout's, the tangents in a second buffer)
	static final LAYOUT:Array<VertexBufferLayout> = [
		{
			stride: 32,
			attributes: [{location: 0, format: Float3, offset: 0}, {location: 1, format: Float3, offset: 12}, {location: 2, format: Float2, offset: 24}]
		},
		{stride: 16, attributes: [{location: 3, format: Float4, offset: 0}]}
	];

	// (the instanced runs': a third buffer of the instances' matrices)
	static final INSTANCED_LAYOUT:Array<VertexBufferLayout> = [
		LAYOUT[0],
		LAYOUT[1],
		{
			stride: 64,
			step: Instance,
			attributes: [
				{location: 4, format: Float4, offset: 0}, {location: 5, format: Float4, offset: 16}, {location: 6, format: Float4, offset: 32},
				{location: 7, format: Float4, offset: 48}
			]
		}
	];

	// (the renderer's, when attached)
	var plain:Pipeline = cast 0;
	var double:Pipeline = cast 0;
	var instanced:Pipeline = cast 0;
	var instancedDouble:Pipeline = cast 0;
	final slotList:Array<Int>;
	final instancedSlotList:Array<Int>;

	public function new(device:Device) {
		// (models loaded from now on get their tangents)
		VertexData.tangentsFrom = VertexData.computeTangents;
		slotList = Renderer.slotsOf(PbrNormalShader.uniforms, PbrNormalShader.textures);
		instancedSlotList = Renderer.slotsOf(PbrInstancedNormalShader.uniforms, PbrInstancedNormalShader.textures);
	}

	public function attach(renderer:Renderer) {
		var d = PbrNormalShader.pipeline({cull: Back, depthCompare: Less, depthWrite: true});
		d.layout = LAYOUT;
		plain = renderer.createPipeline(d);
		d = PbrNormalShader.pipeline({cull: None, depthCompare: Less, depthWrite: true});
		d.layout = LAYOUT;
		double = renderer.createPipeline(d);
		for (cull in [helder.gfx.Cull.Back, helder.gfx.Cull.None]) {
			var d = PbrInstancedNormalShader.pipeline({cull: cull, depthCompare: Less, depthWrite: true});
			d.layout = INSTANCED_LAYOUT;
			if (cull == Back) instanced = renderer.createPipeline(d) else instancedDouble = renderer.createPipeline(d);
		}
		@:privateAccess renderer.normalSource = this;
	}

	public function pipeline(doubleSided:Bool):Pipeline
		return doubleSided ? double : plain;

	public function slots():Array<Int>
		return slotList;

	public function instancedPipeline(doubleSided:Bool):Pipeline
		return doubleSided ? instancedDouble : instanced;

	public function instancedSlots():Array<Int>
		return instancedSlotList;
}
