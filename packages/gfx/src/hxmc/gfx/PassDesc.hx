package hxmc.gfx;

// built once and reused each frame. A pass into the frame has the device's
// depth buffer (depth: null keeps its contents); a pass into a texture
// (colors[0].texture) has a depth buffer only when depth names a texture.
typedef PassDesc = {
	colors:Array<ColorTarget>,
	?depth:DepthTarget
}
