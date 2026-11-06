// with(...) replaces the slots a slot object has (in TypeScript: slot-unknown.ts).
// expect: shader: the slot object has no slot colour (it has color)
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};
typedef M = {options:{}, color:(Vec3, {}) -> Vec3};

function white(s:Vec3, p:{}):Vec3
	return vec3(1);

final lit = slots({
	options: {},
	vertex: function(v:V, p:{}, m:M):O return {pos: position(vec4(v.pos, 0, 1))},
	fragment: function(o:O, p:{}, m:M):Vec4 return vec4(m.color(o.pos.xyz, p), 1),
	color: white
});

final S = lit.with({colour: white}).variant();

class RejectSlotUnknown {
	static function main()
		trace(S.vertexCode);
}
