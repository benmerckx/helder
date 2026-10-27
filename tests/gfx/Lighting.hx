import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// Shader helpers in a module of their own, for LitShader (ShaderTest).
class Lighting implements Shaders {
	public static inline var AMBIENT = 0.1;

	public static function lambert(n:Vec3, l:Vec3):Float
		return max(dot(normalize(n), normalize(l)), 0);

	// x in steps bands (steps < 2: x)
	public static function posterize(x:Float, steps:Int):Float {
		if (steps < 2) return x;
		return floor(x * steps) / (steps - 1);
	}
}
