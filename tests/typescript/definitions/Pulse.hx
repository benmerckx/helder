import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// uniform(value) as Haxe compiles it: pulse.ts prints the same.
typedef PulseVertex = {pos:Vec2};
typedef PulseVaryings = {clip:Vec4, uv:Vec2};
typedef PulseTint = {color:Vec4};

final time = uniform(0.0);
final offset = uniform(vec2(0, 0));

final PulseShader = shader({
	vertex: function(v:PulseVertex):PulseVaryings return {clip: position(vec4(v.pos + offset.value, 0, 1)), uv: v.pos},
	fragment: function(i, p:{tint:PulseTint}):Vec4 return vec4(p.tint.color.xyz * (sin(time.value) * 0.5 + 0.5), 1)
});

class Pulse {
	static function main() {
		Print.shader(PulseShader);
		time.value = 1.5;
		offset.value = vec2(0.25, -0.5);
		var b = PulseShader.uniformBytes();
		Sys.println('${PulseShader.uniformBinding} ${PulseShader.params.tint.block.binding} ' + [for (i in 0...b.length) b.get(i)].join(","));
		var o = PulseShader.vertex({pos: vec2(1, 1)});
		Sys.println('${o.clip.x} ${o.clip.y}');
	}
}
