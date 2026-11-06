import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// A slot object (Slots) and its variants, for ShaderTest: an option tested
// (tinted: the vertex's optional tint and shift read, a varying kept), a
// loop over one unrolled (taps), a slot's default (a module-level
// function) and an override with a parameter of its own (a texture,
// optional in the stage's parameters: a variant without it drops it).
typedef SlotVertex = {
	var pos:Vec2;
	@:optional var tint:Vec4;
	@:optional var shift:Vec2;
}

typedef SlotVaryings = {
	var clip:Vec4;
	var uv:Vec2;
	@:optional var tint:Vec4;
}

typedef SlotView = {scale:Vec4};
typedef SlotSurface = {uv:Vec2};

typedef SlotParams = {
	var view:SlotView;
	@:optional var image:Texture2D;
}

typedef SlotOptions = {tinted:Bool, taps:Int};
typedef SlotObject = {options:SlotOptions, color:(SlotSurface, SlotParams) -> Vec4};

function plainColor(s:SlotSurface, p:{view:SlotView}):Vec4
	return vec4(s.uv, p.view.scale.x, 1);

final slotted = slots({
	options: {tinted: false, taps: 1},
	vertex: function(v:SlotVertex, p:{view:SlotView}, m:SlotObject):SlotVaryings {
		var at = v.pos * p.view.scale.xy;
		if (m.options.tinted) at += v.shift;
		return {clip: position(vec4(at, 0, 1)), uv: v.pos, tint: m.options.tinted ? v.tint : vec4(1)};
	},
	fragment: function(i:SlotVaryings, p:SlotParams, m:SlotObject):Vec4 {
		var c = m.color({uv: i.uv}, p);
		if (m.options.tinted && !(m.options.taps > 2)) c = c * 0.5 else if (m.options.tinted) c = c * i.tint;
		var sum = 0.0;
		for (k in 0...m.options.taps)
			sum += k + 1;
		return c * sum;
	},
	color: plainColor
});

final SlotsPlain = slotted.variant();
final SlotsTinted = slotted.variant({tinted: true, taps: 3});
final SlotsTextured = slotted.with({color: function(s, p:{image:Texture2D}):Vec4 return sample(p.image, s.uv)}).variant();
