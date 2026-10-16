package hxmc.gfx;

// the device's depth buffer in a pass (Device: 0 near, 1 far), cleared to
// clear (default 1) or kept
typedef DepthTarget = {
	load:LoadOp,
	?clear:Float
}
