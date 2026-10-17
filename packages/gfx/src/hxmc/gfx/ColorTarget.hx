package hxmc.gfx;

// a pass's colour target: the frame's, or a render target
// (TextureDesc.renderTarget) of the pipelines' colorFormat
typedef ColorTarget = {
	load:LoadOp,
	?clear:Color,
	?texture:Texture
}
