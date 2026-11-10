import Mood.noise2;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// What the moth can wake, drawn on the stone's faces (quads in the wall's
// plane, a little in front of it): a glyph's sigil, an eye, the snail's
// home door. Carved hairlines that breathe faintly so they read as
// something to touch; lit from the moth's side as it comes near, filling
// with light as they charge. Each one's state is an entry of one block's
// array (written each frame): one draw for them all.
@:structInit @:publicFields class GlyphVertex {
	var corner:Vec2;
	var at:Vec4; // xyz: its centre, w: its half size
	var kind:Vec4; // x: 0 a glyph, 1 an eye, 2 the home's door; y: its entry in state
}

@:structInit @:publicFields class GlyphVaryings {
	var clip:Vec4;
	var q:Vec2;
	var world:Vec3;
	var kind:Vec4;
	var state:Vec4;
}

@:structInit @:publicFields class GlyphView {
	var viewProj:Mat4;
	var moth:Vec4; // xyz: the moth, w: seconds
	// x: charge (0 to 1), y: lit, z: how near the moth is (0 to 1), w: 1 armed
	// (the door's: x the snail near, y home)
	@:length(8) var state:Array<Vec4>;
}

final GLOW = vec3(0.62, 0.3, 1.0);
final WARM = vec3(1.0, 0.55, 0.18);

// the sigil's distance (q: its half size 1)
function sigil(q:Vec2):Float {
	var ring = abs(length(q - vec2(0, 0.1)) - 0.62);
	var crescent = max(ring, -(length(q - vec2(0.28, 0.32)) - 0.5));
	var stem = max(abs(q.x + sin(q.y * 4) * 0.06), abs(q.y + 0.15) - 0.75);
	var arm1 = max(abs((q.y + 0.1) - (q.x * 0.9)) * 0.75, abs(q.x - 0.22) - 0.22);
	var arm2 = max(abs((q.y + 0.35) + (q.x * 0.9)) * 0.75, abs(q.x + 0.22) - 0.22);
	var dots = min(length(q - vec2(0, 0.95)), min(length(q - vec2(-0.32, 0.86)), length(q - vec2(0.32, 0.86)))) - 0.06;
	return min(min(min(crescent, stem), min(arm1, arm2)), dots);
}

final GlyphShader = shader({
	vertex: function(v:GlyphVertex, p:{view:GlyphView}):GlyphVaryings {
		var s = v.at.w * 1.5;
		var w = v.at.xyz + vec3(v.corner.x * s, v.corner.y * s, 0);
		var k = Std.int(v.kind.y + 0.5);
		return {
			clip: position(p.view.viewProj * vec4(w, 1)),
			q: v.corner * 1.5,
			world: w,
			kind: v.kind,
			state: p.view.state[k]
		};
	},
	fragment: function(i:GlyphVaryings, p:{view:GlyphView}):Vec4 {
		var t = p.view.moth.w, q = i.q, st = i.state;
		var kind = floor(i.kind.x + 0.5);
		if (kind > 1.5) {
			// (the home: a round-topped door, dark inside, a warm light in
			// it that brightens as the snail comes, full once it is home)
			var d = max(abs(q.x) - 0.42, -q.y - 0.95);
			d = q.y > 0.1 ? length(q - vec2(0, 0.1)) - 0.42 : d;
			var inside = 1 - smoothstep(-0.02, 0.02, d);
			var rim = 1 - smoothstep(0.0, 0.1, abs(d));
			var breathe = 0.8 + 0.2 * sin(t * 1.2);
			var lamp = 0.35 + st.x * 0.8 + st.y * 2.5;
			var glow = WARM * ((inside * (0.5 + 0.5 * smoothstep(-0.95, 0.4, -q.y)) * 1.2 + rim * 0.8) * lamp * breathe);
			var halo = exp(-max(d, 0) * 5) * (1 - inside) * (0.15 + st.y * 0.6) * breathe;
			return vec4(glow + WARM * halo, inside * 0.85);
		}
		var line = 0.0, fill = 0.0;
		if (kind > 0.5) {
			// (an eye: an almond, its iris filling with light)
			var w = 0.85, h = 0.42 * (1 - (q.x * q.x) / (w * w));
			var lid = abs(abs(q.y) - max(h, 0)) + max(abs(q.x) - w, 0);
			var iris = length(q) - 0.24;
			line = min(lid, abs(iris));
			fill = 1 - smoothstep(-0.02, 0.02, iris);
		} else line = sigil(q);
		var stroke = 1 - smoothstep(0.02, 0.06, line);
		var halo = 1 - smoothstep(0.02, 0.22, line);
		// (lit from the moth's side first as it comes near)
		var reveal = smoothstep(1.85, 1.05, length(i.world - p.view.moth.xyz)) * st.z;
		var breathe = 0.5 + 0.5 * sin(t * 1.3 + i.kind.y * 2.1);
		var charge = st.x;
		var light = 0.04 + 0.07 * breathe + reveal * 0.8 + charge * 1.6 + st.y * 0.4;
		// (spent: dimmer until it has gone dark again)
		light *= mix(0.55, 1, st.w);
		var flicker = 0.9 + 0.1 * noise2(vec2(t * 6, i.kind.y));
		var c = GLOW * ((stroke * 1.4 + halo * 0.18 + fill * charge * 1.6) * light * flicker);
		return vec4(c, stroke * 0.35);
	}
});
