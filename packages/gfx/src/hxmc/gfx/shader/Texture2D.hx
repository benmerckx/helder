package hxmc.gfx.shader;

import haxe.io.Bytes;

// A texture a fragment stage samples (ShaderMath.texture(t, uv)): in a
// shader, a parameter of the @:fragment function after its input, bound by
// slot (the order of the texture parameters: Encoder.setTexture); in CPU
// code, an image of 8-bit channels (1: R, read as (r, 0, 0, 1) as the GPU
// reads an R8 texture; 4: RGBA) sampled bilinearly with its edges clamped,
// as a texture with Linear filtering is (level 0: there are no mipmaps).
abstract Texture2D(Texture2DData) {
	public inline function new(width:Int, height:Int, channels:Int, data:Bytes)
		this = new Texture2DData(width, height, channels, data);

	public var width(get, never):Int;
	public var height(get, never):Int;

	inline function get_width()
		return this.width;

	inline function get_height()
		return this.height;

	@:allow(hxmc.gfx.shader.ShaderMath) inline function sample(uv:Vec2):Vec4
		return this.sample(uv.x, uv.y);
}

@:noCompletion final class Texture2DData {
	public final width:Int;
	public final height:Int;
	public final channels:Int;
	public final data:Bytes;

	public function new(width:Int, height:Int, channels:Int, data:Bytes) {
		if (channels != 1 && channels != 4) throw "Texture2D: 1 or 4 channels";
		if (data.length < width * height * channels) throw "Texture2D: data has fewer than width * height * channels bytes";
		this.width = width;
		this.height = height;
		this.channels = channels;
		this.data = data;
	}

	public function sample(u:Float, v:Float):Vec4 {
		// (texel centres at (i + 0.5) / size)
		var x = u * width - 0.5, y = v * height - 0.5;
		var x0 = Math.floor(x), y0 = Math.floor(y);
		var fx = x - x0, fy = y - y0;
		var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
		for (k in 0...4) {
			var dx = k & 1, dy = k >> 1;
			var w = (dx == 0 ? 1 - fx : fx) * (dy == 0 ? 1 - fy : fy);
			var tx = clamp(x0 + dx, width), ty = clamp(y0 + dy, height);
			var o = (ty * width + tx) * channels;
			if (channels == 1) {
				r += w * data.get(o) / 255;
				a += w;
			} else {
				r += w * data.get(o) / 255;
				g += w * data.get(o + 1) / 255;
				b += w * data.get(o + 2) / 255;
				a += w * data.get(o + 3) / 255;
			}
		}
		return new Vec4(r, g, b, a);
	}

	static inline function clamp(i:Int, n:Int):Int
		return i < 0 ? 0 : i >= n ? n - 1 : i;
}
