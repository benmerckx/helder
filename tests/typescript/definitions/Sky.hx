import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.SkyShader;

// helder.scene's sky as Haxe compiles it: sky.ts prints the same.
class Sky {
	static function main() {
		Print.shader(SkyShader);
		var b = SkyShader.vertexBytes([{pos: vec2(0.5, -1)}]);
		Sys.println([for (i in 0...b.length) b.get(i)].join(","));
	}
}
