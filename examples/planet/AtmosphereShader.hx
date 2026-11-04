
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;

// A planet's air (Atmosphere), ported from Expansion's app.AtmosphereShader; after Maxime Heckel's "On rendering the sky,
// sunsets and planets" and Hillaire's LUTs: the shell around the sphere
// drawn as its front faces, each pixel's ray from the eye clipped to the
// shell and to the planet (ray-sphere intersections), marched in `steps`
// (the tier's): at each point the air's density (Rayleigh's and Mie's
// exponential falloffs, ozone's tent), the view's optical depth so far,
// and the sun's light reaching it read from the transmittance LUT (the
// sun's own march, precomputed: Atmosphere.lut) rather than marched
// again. The light scattered towards the eye by Rayleigh's phase (blue
// overhead, the sunset's reds where the sun's light crossed the most air)
// and Mie's (Cornette-Shanks: a forward halo about the sun) is added; what
// is behind (the planet, the stars) is dimmed by the view's transmittance
// (its mean: one alpha, premultiplied). Units: the planet's radius is 1,
// the coefficients per radius (Atmosphere.Preset in km, scaled).
@:structInit @:publicFields class AirVertex {
	var pos:Vec3; // per vertex: the unit sphere's point
	var center:Vec4; // per instance: the planet's centre, w its radius (world)
	var rayleigh:Vec4; // Rayleigh's scattering (rgb), w: the shell's radius
	var ozone:Vec4; // ozone's absorption (rgb), w: Mie's scattering
	var shape:Vec4; // x: Mie's extinction, y: Mie's g, z: Rayleigh's scale height, w: Mie's
	var extra:Vec4; // x: the LUT's band, y: the sun's intensity, z: strength (0 to 1), w: ozone's height
	var ground:Vec4; // the surface's mean colour (linear), for the sun reddened on it
}

@:structInit @:publicFields class AirVaryings {
	@:position var clip:Vec4;
	var world:Vec3;
	var center:Vec4;
	var rayleigh:Vec4;
	var ozone:Vec4;
	var shape:Vec4;
	var extra:Vec4;
	var ground:Vec4;
}

@:structInit @:publicFields class AirView {
	var viewProj:Mat4;
	var eye:Vec4; // w: the exposure
	var light:Vec4; // xyz: towards the sun; w: the march's steps
	var sun:Vec4; // the sun's colour; w: 1 into an HDR target
	var lut:Vec4; // x: the LUT's bands, y: its width, z: its band's height
}

class AtmosphereShader implements Shaders {
	@:vertex static function vs(v:AirVertex, view:AirView):AirVaryings {
		// (a little larger than the shell: the mesh's facets inside the true sphere)
		var p = v.center.xyz + v.pos * (v.center.w * v.rayleigh.w * 1.03);
		return {
			clip: view.viewProj * vec4(p, 1), world: p, center: v.center, rayleigh: v.rayleigh, ozone: v.ozone, shape: v.shape,
			extra: v.extra, ground: v.ground
		};
	}

	@:fragment static function fs(i:AirVaryings, view:AirView, lut:Texture2D):Vec4 {
		var o = (view.eye.xyz - i.center.xyz) / i.center.w;
		var d = normalize(i.world - view.eye.xyz);
		var top = i.rayleigh.w;
		var shell = hit(o, d, top);
		var result = vec4(0, 0, 0, 0);
		if (shell.y > 0 && shell.x <= shell.y) {
			var t0 = max(shell.x, 0), t1 = shell.y;
			var ground = hit(o, d, 1), solid = ground.x > 0 && ground.x <= ground.y;
			if (solid) t1 = min(t1, ground.x);
			// (the samples gathered about where the ray passes lowest, the
			// air's densest: the closest approach to the centre, or the
			// ground; t = c +- u^2 on each side, weighted by dt/du)
			var steps = view.light.w, c = clamp(-dot(o, d), t0, t1);
			// (each pixel's samples shifted by a noise: banding turned to grain)
			var jitter = 0.5 + 0.5 * (fract(52.9829189 * fract(0.06711056 * i.clip.x + 0.00583715 * i.clip.y)) - 0.5);
			var tau = vec3(0, 0, 0), sumR = vec3(0, 0, 0), sumM = vec3(0, 0, 0);
			var k = 0.0;
			while (k < steps) {
				var u = (k + jitter) / steps * 2 - 1, side = u < 0 ? c - t0 : t1 - c;
				var dt = 4 * abs(u) * side / steps;
				var p = o + d * (c + sign(u) * u * u * side);
				var len = length(p), h = len - 1;
				var dr = exp(-h / i.shape.z), dm = exp(-h / i.shape.w), dz = ozone(h, i.extra.w);
				var ext = i.rayleigh.xyz * dr + vec3(i.shape.x * dm) + i.ozone.xyz * dz;
				var seen = exp(-(tau + ext * (dt * 0.5)));
				tau += ext * dt;
				var sun = sunlight(lut, view.lut, i.extra.x, h / (top - 1), dot(p / len, view.light.xyz));
				var w = sun * seen * dt;
				sumR += w * dr;
				sumM += w * dm;
				k += 1;
			}
			var mu = dot(d, view.light.xyz);
			var scatter = view.sun.xyz * (i.extra.y * i.extra.z) * (i.rayleigh.xyz * sumR * rayleighPhase(mu) + sumM * (i.ozone.w * miePhase(mu, i.shape.y)));
			var through = exp(-tau), seen = dot(through, vec3(0.3, 0.45, 0.25));
			// (the ground: the sun's light on it through the air, reddened
			// along the terminator (Mars's bluer): the surface (its mean
			// colour's Lambert under the sun) dimmed by the least of the
			// channels' transmittance, the rest of each added back)
			var g = o + d * t1, up = normalize(g), cosine = dot(up, view.light.xyz);
			var lit = solid ? smoothstep(-0.02, 0.1, cosine) * i.extra.z : 0;
			var sunT = sunlight(lut, view.lut, i.extra.x, 0, cosine), least = min(sunT.x, min(sunT.y, sunT.z));
			var surface = i.ground.xyz / 3.14159265 * view.sun.xyz * max(cosine, 0);
			scatter += surface * (sunT - vec3(least)) * (lit * seen);
			var alpha = 1 - (1 - (1 - least) * lit) * (1 - (1 - seen) * i.extra.z);
			var c = scatter * view.eye.w;
			result = vec4(view.sun.w > 0.5 ? c : PbrShader.encode(PbrShader.aces(c)), alpha);
		}
		return result;
	}

	// where the ray o + d t crosses the sphere of radius r about the origin:
	// (near, far); a miss: near past far
	public static function hit(o:Vec3, d:Vec3, r:Float):Vec2 {
		var b = dot(o, d), c = dot(o, o) - r * r, disc = b * b - c;
		var s = sqrt(max(disc, 0));
		return disc < 0 ? vec2(1, -1) : vec2(-b - s, -b + s);
	}

	// ozone's density at height h: a tent about its height c, as wide as c
	public static function ozone(h:Float, c:Float):Float
		return c <= 0 ? 0 : max(0, 1 - abs(h - c) / c);

	// the sun's light (0 to 1 a channel) reaching a point at height hn (a
	// share of the shell's) under the sun at cos mu: the LUT's texel, stored
	// as its square root (8 bits enough at a sunset's dim end)
	public static function sunlight(lut:Texture2D, at:Vec4, band:Float, hn:Float, mu:Float):Vec3 {
		var u = (0.5 + (mu * 0.5 + 0.5) * (at.y - 1)) / at.y;
		var v = (band + (0.5 + clamp(hn, 0, 1) * (at.z - 1)) / at.z) / at.x;
		var s = sample(lut, vec2(u, v)).xyz;
		return s * s;
	}

	public static function rayleighPhase(mu:Float):Float
		return 3 / (16 * 3.14159265) * (1 + mu * mu);

	// Cornette-Shanks's (Henyey-Greenstein's with Rayleigh's lobe shape)
	public static function miePhase(mu:Float, g:Float):Float {
		var g2 = g * g;
		return 3 * (1 - g2) * (1 + mu * mu) / (8 * 3.14159265 * (2 + g2) * pow(max(1 + g2 - 2 * g * mu, 0.0001), 1.5));
	}
}
