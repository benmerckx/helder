package helder.scene.render;

import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;

// Fog over a scene (Renderer.fog; null: none). A surface's light is mixed
// towards color (linear, times the exposure) by the fog between it and
// the eye: 1 - e^(-density * the distance past start), at most max. With
// falloff, the fog thins upwards: density at height, times
// e^(-falloff * (y - height)), summed along the view, so valleys fill and
// what is high, the sky above among it, clears. In linear light before
// tone mapping, so an HDR frame blooms and grades it as the rest. The
// standard material (Material.fog: on by default), Sky and Environment's
// background (to the camera's far plane) and GpuParticles (faded, as they
// add light) take it; a program's own shaders read it through FrameInfo.fog
// (color and shape, as PbrShader.fogAmount takes them).
class Fog {
	public var color:Vec3;
	// per metre (0.02: half gone at 35 m)
	public var density:Float;
	// metres from the eye before it begins
	public var start = 0.0;
	// how fast it thins upwards (per metre; 0: as thick at any height) and
	// the height where it is density
	public var falloff = 0.0;
	public var height = 0.0;
	// the most it hides (below 1: the far hills and the sky show through)
	public var max = 1.0;

	public function new(color:Vec3, density:Float) {
		this.color = color;
		this.density = density;
	}

	// as shaders take it: rgb its colour, w the density (none: 0)
	public static function colorOf(f:Null<Fog>):Vec4
		return f == null ? new Vec4(0, 0, 0, 0) : new Vec4(f.color.x, f.color.y, f.color.z, f.density);

	// x the start, y the falloff, z the height, w the most
	public static function shapeOf(f:Null<Fog>):Vec4
		return f == null ? new Vec4(0, 0, 0, 0) : new Vec4(f.start, f.falloff, f.height, f.max);
}
