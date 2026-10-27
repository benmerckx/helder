package helder.gfx;

// a pass's depth buffer (0 near, 1 far), cleared to clear (default 1) or
// kept: the device's (of the frame's size), or in a pass into a texture a
// depth texture of its size (Depth16, Depth32F), the pipelines' depthFormat
typedef DepthTarget = {
	load:LoadOp,
	?clear:Float,
	?texture:Texture
}
