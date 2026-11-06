import helder.gfx.shader.ShaderMath.*;
import helder.sprite.SpriteShader;

// helder.sprite's shader as Haxe compiles it: sprite.ts prints the same.
class Sprite {
	static function main() {
		Print.shader(SpriteShader);
		var bytes = haxe.io.Bytes.alloc(16);
		SpriteShader.params.s.write({view: vec4(2, -2, -1, 1)}, bytes);
		Sys.println([for (i in 0...bytes.length) bytes.get(i)].join(","));
		var o = SpriteShader.vertex({pos: vec2(1, 2), uv: vec2(0.5, 0.5), color: vec4(1, 1, 1, 1)}, {s: {view: vec4(2, -2, -1, 1)}});
		Sys.println('${o.pos.x} ${o.pos.y} ${o.pos.z} ${o.pos.w}');
		Sys.println('${SpriteShader.params.image.name} ${SpriteShader.params.image.binding}');
	}
}
