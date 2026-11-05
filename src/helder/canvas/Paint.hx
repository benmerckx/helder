package helder.canvas;

import haxe.ds.Vector;
import helder.canvas.Blend.Blender;

// What a fill or a stroke draws with: a colour (0xAARRGGBB, straight
// alpha) or a shader (a gradient, an image pattern: classes of their own,
// so an executable keeps only those it makes), an opacity, a blend mode
// (null: source-over, the fast path; Blend.multiply...). A paint is a
// value kept and changed by its owner: drawing with one allocates nothing.
final class Paint {
	public var color = 0xFF000000;
	public var shader:Null<Shader> = null;
	// multiplies the colour's or the shader's alpha (Canvas 2D's globalAlpha)
	public var alpha = 1.0;
	public var blend:Null<Blender> = null;

	public function new(color = 0xFF000000) {
		this.color = color;
	}

	public static inline function solid(color:Int):Paint
		return new Paint(color);

	public static inline function shaded(shader:Shader):Paint {
		var p = new Paint();
		p.shader = shader;
		return p;
	}

	public function copyFrom(p:Paint):Paint {
		color = p.color;
		shader = p.shader;
		alpha = p.alpha;
		blend = p.blend;
		return this;
	}
}

// Colours across a span of pixels, premultiplied (0 to 1)
interface Shader {
	// ready for a draw whose device pixels map to the shader's space by
	// inverse (the canvas's transform's inverse); false: it paints nothing
	function begin(inverse:Matrix):Bool;
	// pixels x...x+n of row y (their centres) into out, 4 floats each
	function shade(x:Int, y:Int, n:Int, out:Vector<Float>):Void;
}

// A pixel in floats, premultiplied (a blend mode's operands)
final class Rgba {
	public var r = 0.0;
	public var g = 0.0;
	public var b = 0.0;
	public var a = 0.0;

	public function new() {}
}
