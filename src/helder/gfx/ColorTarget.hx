package helder.gfx;

// a pass's colour target: the frame's, or a render target
// (TextureDesc.renderTarget) of the pipelines' colorFormat; a multisampled
// texture (TextureDesc.samples) resolved at the pass's end into resolve, a
// single-sampled render target of its size and format
typedef ColorTarget = {
	load:LoadOp,
	?clear:Color,
	?texture:Texture,
	?resolve:Texture
}
