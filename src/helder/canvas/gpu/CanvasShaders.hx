package helder.canvas.gpu;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// GpuCanvas's shaders. CoverageShader: a trapezoid of a path (Trapezoids,
// in the path's units) through the transform (view) into pixels, drawn as
// its bounds a pixel larger, each fragment's coverage the product of its
// coverage by the trapezoid's two pairs of opposite sides (each side's
// signed distance in pixels, a pair's clamp(d0 + 0.5) + clamp(d1 + 0.5) - 1:
// exact for a side's half plane and for a sliver thinner than a pixel), added
// into a float target (Blend.Additive): trapezoids that share a side sum to
// one across it, so any fill rule's tiling is seamless. CoverShader: a
// batch's bounds painted by a paint (a colour per vertex, a gradient through
// a table of its colours, an image, a layer) times the coverage and the
// clip, premultiplied; with a blend mode, of the target's pixels copied
// first (dst), W3C Compositing's formulas.
@:structInit @:publicFields class TrapVertex {
	var corner:Vec2; // x: 0 to 3 (top left, top right, bottom right, bottom left)
	var top:Vec4; // the top side: left x, y, right x, y (path units)
	var bottom:Vec4; // the bottom side: right x, y, left x, y
}

@:structInit @:publicFields class TrapVaryings {
	@:position var pos:Vec4;
	var pixel:Vec2;
	var q01:Vec4;
	var q23:Vec4;
}

@:structInit @:publicFields class TrapView {
	var m:Vec4; // the transform's a, b, c, d
	var t:Vec4; // its e, f; the target's width, height
}

class CoverageShader implements Shaders {
	@:vertex static function vs(v:TrapVertex, view:TrapView):TrapVaryings {
		var q0 = px(view, v.top.xy), q1 = px(view, v.top.zw), q2 = px(view, v.bottom.xy), q3 = px(view, v.bottom.zw);
		var lo = min(min(q0, q1), min(q2, q3)) - vec2(1, 1), hi = max(max(q0, q1), max(q2, q3)) + vec2(1, 1);
		var c = v.corner.x;
		var sx = step(0.5, c) - step(2.5, c), sy = step(1.5, c);
		var p = vec2(mix(lo.x, hi.x, sx), mix(lo.y, hi.y, sy));
		return {
			pos: vec4(p.x / view.t.z * 2 - 1, 1 - p.y / view.t.w * 2, 0, 1),
			pixel: p,
			q01: vec4(q0.x, q0.y, q1.x, q1.y),
			q23: vec4(q2.x, q2.y, q3.x, q3.y)
		};
	}

	static function px(view:TrapView, p:Vec2):Vec2
		return vec2(view.m.x * p.x + view.m.z * p.y + view.t.x, view.m.y * p.x + view.m.w * p.y + view.t.y);

	// the signed distance in pixels from the side a to b, positive toward inside (c: a point inside); a side of no length: far inside
	static function side(a:Vec2, b:Vec2, c:Vec2, p:Vec2):Float {
		var d = b - a, l = length(d), result = 1000.0;
		if (l > 0.00001) {
			var n = vec2(-d.y, d.x) / l;
			var s = dot(n, c - a);
			var k = 1.0;
			if (s < 0) k = -1.0;
			result = dot(n, p - a) * k;
		}
		return result;
	}

	@:fragment static function fs(i:TrapVaryings):Vec4 {
		var q0 = i.q01.xy, q1 = i.q01.zw, q2 = i.q23.xy, q3 = i.q23.zw;
		var c = (q0 + q1 + q2 + q3) * 0.25, p = i.pixel;
		var across = clamp(side(q0, q1, c, p) + 0.5, 0.0, 1.0) + clamp(side(q2, q3, c, p) + 0.5, 0.0, 1.0) - 1;
		var along = clamp(side(q1, q2, c, p) + 0.5, 0.0, 1.0) + clamp(side(q3, q0, c, p) + 0.5, 0.0, 1.0) - 1;
		var cov = max(across, 0.0) * max(along, 0.0);
		return vec4(cov, cov, cov, 1);
	}
}

@:structInit @:publicFields class CoverVertex {
	var pos:Vec2; // pixels
	var color:Vec4; // premultiplied (kind 0)
}

@:structInit @:publicFields class CoverVaryings {
	@:position var pos:Vec4;
	var pixel:Vec2;
	var color:Vec4;
}

@:structInit @:publicFields class CoverPaint {
	var size:Vec4; // the target's width, height; x: alpha, y: whether coverage counts (1) or is whole (0)
	var kind:Vec4; // x: 0 colour, 1 linear, 2 radial, 3 conic, 4 image, 5 layer; y: spread; z: the table's row (v); w: mode (blend) or -1
	var inv0:Vec4; // device pixels to the paint's space: a, b, c, d
	var inv1:Vec4; // e, f; the image's clamp: x0, y0 in texels (drawImage), or -1
	var g0:Vec4; // linear: x0, y0, x1, y1; radial: x0, y0, r0; conic: start, x, y; image: width, height, repeat x, repeat y
	var g1:Vec4; // radial: x1, y1, r1; image: the clamp's x1, y1 in texels
	var pd:Vec4; // Porter-Duff's factors (x: fa, y: fb: 0 zero, 1 one, 2 the other's alpha, 3 one minus it), z: 1 when unbounded
}

class CoverShader implements Shaders {
	@:vertex static function vs(v:CoverVertex, paint:CoverPaint):CoverVaryings
		return {pos: vec4(v.pos.x / paint.size.x * 2 - 1, 1 - v.pos.y / paint.size.y * 2, 0, 1), pixel: v.pos, color: v.color};

	static function spread(t:Float, mode:Float):Float {
		var r = clamp(t, 0.0, 1.0);
		if (mode > 1.5) r = fract(t);
		if (mode > 0.5 && mode < 1.5) {
			var u = t - floor(t / 2) * 2;
			r = u;
			if (u > 1) r = 2 - u;
		}
		return r;
	}

	static function atan2(y:Float, x:Float):Float {
		// (a minimax polynomial of atan on [0, 1], then the octants: within 1e-5)
		var ax = abs(x), ay = abs(y);
		var a = min(ax, ay) / max(max(ax, ay), 0.0000001);
		var s = a * a;
		var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
		if (ay > ax) r = 1.57079637 - r;
		if (x < 0) r = 3.14159274 - r;
		if (y < 0) r = -r;
		return r;
	}

	// the paint's colour at the pixel, premultiplied
	public static function paintAt(i:CoverVaryings, paint:CoverPaint, table:Texture2D, image:Texture2D):Vec4 {
		var k = paint.kind.x;
		var result = i.color;
		var c = i.pixel;
		var u = paint.inv0.x * c.x + paint.inv0.z * c.y + paint.inv1.x, v = paint.inv0.y * c.x + paint.inv0.w * c.y + paint.inv1.y;
		if (k > 0.5 && k < 3.5) {
			var t = 0.0;
			var some = 1.0;
			if (k < 1.5) {
				var d = paint.g0.zw - paint.g0.xy;
				t = dot(vec2(u, v) - paint.g0.xy, d) / dot(d, d);
			} else if (k < 2.5) {
				var cd = paint.g1.xy - paint.g0.xy, dr = paint.g1.z - paint.g0.z;
				var pd = vec2(u, v) - paint.g0.xy;
				var qa = dot(cd, cd) - dr * dr, b = dot(pd, cd) + paint.g0.z * dr, cc = dot(pd, pd) - paint.g0.z * paint.g0.z;
				some = 0.0;
				if (abs(qa) < 0.000001) {
					if (abs(b) > 0.000001) {
						t = cc / (2 * b);
						if (paint.g0.z + t * dr >= 0) some = 1.0;
					}
				} else {
					var disc = b * b - qa * cc;
					if (disc >= 0) {
						var sq = sqrt(disc);
						var s1 = (b + sq) / qa, s2 = (b - sq) / qa;
						var hi = max(s1, s2), lo = min(s1, s2);
						if (paint.g0.z + hi * dr >= 0) {
							t = hi;
							some = 1.0;
						} else if (paint.g0.z + lo * dr >= 0) {
							t = lo;
							some = 1.0;
						}
					}
				}
			} else {
				t = (atan2(v - paint.g0.z, u - paint.g0.y) - paint.g0.x) / 6.28318531;
				t = t - floor(t);
			}
			var at = (spread(t, paint.kind.y) * 255 + 0.5) / 256;
			result = sample(table, vec2(at, paint.kind.z)) * some;
		} else if (k > 3.5 && k < 4.5) {
			var w = paint.g0.x, h = paint.g0.y;
			var x = u, y = v;
			var inside = 1.0;
			if (paint.inv1.z >= 0) {
				// (drawImage: within its source rectangle's texels' centres)
				x = clamp(x, paint.inv1.z + 0.5, paint.g1.x - 0.5);
				y = clamp(y, paint.inv1.w + 0.5, paint.g1.y - 0.5);
			} else {
				if (paint.g0.z < 0.5 && (x < 0 || x > w)) inside = 0.0;
				if (paint.g0.w < 0.5 && (y < 0 || y > h)) inside = 0.0;
			}
			result = sample(image, vec2(x / w, y / h)) * inside;
		} else if (k > 4.5) {
			result = sample(image, vec2(c.x / paint.size.x, c.y / paint.size.y));
		}
		return result;
	}

	@:fragment static function fs(i:CoverVaryings, paint:CoverPaint, coverage:Texture2D, clip:Texture2D, table:Texture2D, image:Texture2D):Vec4 {
		var uv = vec2(i.pixel.x / paint.size.x, i.pixel.y / paint.size.y);
		var cov = 1.0;
		if (paint.size.w > 0.5) cov = min(sample(coverage, uv).x, 1.0);
		var m = sample(clip, uv).x;
		return paintAt(i, paint, table, image) * (cov * m * paint.size.z);
	}
}

// CoverShader's paint through a blend mode, over the target's pixels as
// they were (dst, copied first), written as they come out (Blend.Opaque)
class BlendShader implements Shaders {
	@:vertex static function vs(v:CoverVertex, paint:CoverPaint):CoverVaryings
		return {pos: vec4(v.pos.x / paint.size.x * 2 - 1, 1 - v.pos.y / paint.size.y * 2, 0, 1), pixel: v.pos, color: v.color};

	static function factor(f:Float, other:Float):Float {
		var r = 0.0;
		if (f > 0.5) r = 1.0;
		if (f > 1.5) r = other;
		if (f > 2.5) r = 1 - other;
		return r;
	}

	static function channel(mode:Float, cb:Float, cs:Float):Float {
		var r = cb * cs;
		if (mode > 0.5) r = cb + cs - cb * cs;
		if (mode > 1.5) {
			r = cs * 2 * cb;
			if (cb > 0.5) r = cs + (2 * cb - 1) - cs * (2 * cb - 1);
		}
		if (mode > 2.5) r = min(cb, cs);
		if (mode > 3.5) r = max(cb, cs);
		if (mode > 4.5) {
			r = min(1.0, cb / max(1 - cs, 0.000001));
			if (cs >= 1) r = 1.0;
			if (cb <= 0) r = 0.0;
		}
		if (mode > 5.5) {
			r = 1 - min(1.0, (1 - cb) / max(cs, 0.000001));
			if (cs <= 0) r = 0.0;
			if (cb >= 1) r = 1.0;
		}
		if (mode > 6.5) {
			r = cb * 2 * cs;
			if (cs > 0.5) r = cb + (2 * cs - 1) - cb * (2 * cs - 1);
		}
		if (mode > 7.5) {
			var d = sqrt(cb);
			if (cb <= 0.25) d = ((16 * cb - 12) * cb + 4) * cb;
			r = cb - (1 - 2 * cs) * cb * (1 - cb);
			if (cs > 0.5) r = cb + (2 * cs - 1) * (d - cb);
		}
		if (mode > 8.5) r = abs(cb - cs);
		if (mode > 9.5) r = cb + cs - 2 * cb * cs;
		return r;
	}

	static function lum(c:Vec3):Float
		return 0.3 * c.x + 0.59 * c.y + 0.11 * c.z;

	static function setLum(c:Vec3, l:Float):Vec3 {
		var r = c + vec3(l - lum(c));
		var ll = lum(r), n = min(r.x, min(r.y, r.z)), x = max(r.x, max(r.y, r.z));
		if (n < 0) r = vec3(ll) + (r - vec3(ll)) * (ll / (ll - n));
		if (x > 1) r = vec3(ll) + (r - vec3(ll)) * ((1 - ll) / (x - ll));
		return r;
	}

	static function setSat(c:Vec3, s:Float):Vec3 {
		var mx = max(c.x, max(c.y, c.z)), mn = min(c.x, min(c.y, c.z));
		var r = vec3(0);
		if (mx > mn) r = (c - vec3(mn)) * (s / (mx - mn));
		return r;
	}

	static function sat(c:Vec3):Float
		return max(c.x, max(c.y, c.z)) - min(c.x, min(c.y, c.z));

	@:fragment static function fs(i:CoverVaryings, paint:CoverPaint, coverage:Texture2D, clip:Texture2D, table:Texture2D, image:Texture2D,
			dst:Texture2D):Vec4 {
		var uv = vec2(i.pixel.x / paint.size.x, i.pixel.y / paint.size.y);
		var cov = 1.0;
		if (paint.size.w > 0.5) cov = min(sample(coverage, uv).x, 1.0);
		var m = sample(clip, uv).x;
		var d = sample(dst, uv);
		var k = cov * paint.size.z;
		if (paint.pd.z < 0.5) k = k * m;
		var s = CoverShader.paintAt(i, paint, table, image) * k;
		var mode = paint.kind.w;
		var out = d;
		if (mode < 0) {
			var ka = factor(paint.pd.x, d.w), kb = factor(paint.pd.y, s.w);
			out = s * ka + d * kb;
			out = min(out, vec4(1));
		} else if (s.w > 0) {
			var cs = s.xyz / s.w, cb = vec3(0);
			if (d.w > 0) cb = d.xyz / d.w;
			var b = vec3(0);
			if (mode < 10.5) b = vec3(channel(mode, cb.x, cs.x), channel(mode, cb.y, cs.y), channel(mode, cb.z, cs.z));
			else if (mode < 11.5) b = setLum(setSat(cs, sat(cb)), lum(cb));
			else if (mode < 12.5) b = setLum(setSat(cb, sat(cs)), lum(cb));
			else if (mode < 13.5) b = setLum(cs, lum(cb));
			else b = setLum(cb, lum(cs));
			if (d.w <= 0) b = cs;
			out = vec4(s.xyz * (1 - d.w) + d.xyz * (1 - s.w) + b * (s.w * d.w), s.w + d.w - s.w * d.w);
		}
		if (paint.pd.z > 0.5) out = d + (out - d) * m;
		return vec4(min(out.xyz, vec3(out.w)), out.w);
	}
}

@:structInit @:publicFields class ClipVaryings {
	@:position var pos:Vec4;
	var uv:Vec2;
}

@:structInit @:publicFields class ClipVertex {
	var pos:Vec2; // clip space
	var uv:Vec2;
}

// A clip narrowed: the coverage of its path times the clip before
// (written into the save's own clip texture); also a texture copied
// (dst, the frame)
class ClipShader implements Shaders {
	@:vertex static function vs(v:ClipVertex):ClipVaryings
		return {pos: vec4(v.pos, 0, 1), uv: v.uv};

	@:fragment static function fs(i:ClipVaryings, coverage:Texture2D, clip:Texture2D):Vec4 {
		var c = min(sample(coverage, i.uv).x, 1.0) * sample(clip, i.uv).x;
		return vec4(c, c, c, 1);
	}
}

class CopyShader implements Shaders {
	@:vertex static function vs(v:ClipVertex):ClipVaryings
		return {pos: vec4(v.pos, 0, 1), uv: v.uv};

	@:fragment static function fs(i:ClipVaryings, image:Texture2D):Vec4
		return sample(image, i.uv);
}
