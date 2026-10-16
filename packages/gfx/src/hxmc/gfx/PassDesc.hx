package hxmc.gfx;

// built once and reused each frame
typedef PassDesc = {
	colors:Array<ColorTarget>,
	// the depth buffer: null keeps its contents
	?depth:DepthTarget
}
