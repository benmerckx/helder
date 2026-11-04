package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The renderer's shader (Renderer): glTF's metallic-roughness model lit by
// a directional light, up to four point lights and a sky-and-ground
// ambient, in linear light,
// tone mapped (ACES, Narkowicz's fit) and encoded to sRGB for an 8-bit
// target. The specular term is Cook-Torrance: GGX's distribution, the
// height-correlated Smith visibility and Schlick's Fresnel; the ambient's
// specular part is the environment's colour along the reflection,
// weighted by an analytic fit of the split-sum's lookup (Karis'), so
// metals are not black without an environment map.
@:structInit @:publicFields class PbrVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
}

@:structInit @:publicFields class PbrVaryings {
	@:position var clip:Vec4;
	var world:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	// the node's up (its y axis in the world: Material.ground's sphere's
	// normal) and its tint (MeshRenderer.tint: rgb times the base colour)
	var up:Vec3;
	var tint:Vec3;
}

// per frame: the camera and the lights
@:structInit @:publicFields class PbrFrame {
	var viewProj:Mat4;
	var eye:Vec4; // xyz: the camera's position
	var lightDir:Vec4; // xyz: towards the light, normalized
	var lightColor:Vec4; // rgb: colour times intensity
	var sky:Vec4; // the ambient from above, rgb
	var ground:Vec4; // the ambient from below, rgb
	var exposure:Vec4; // x: exposure; y: 1 for a linear, HDR target (Renderer.hdr: tone mapped later, PostProcess)
	var lightViewProj:Mat4; // the shadow map's view-projection (Shadows)
	var shadow:Vec4; // x: strength (0: no shadows), y: bias, z: a texel of the map
	// up to four point lights: position (w: range, 0 for none), colour times intensity
	var point0:Vec4;
	var point1:Vec4;
	var point2:Vec4;
	var point3:Vec4;
	var pointColor0:Vec4;
	var pointColor1:Vec4;
	var pointColor2:Vec4;
	var pointColor3:Vec4;
	// spot lights: the direction they shine (xyz) and the cosine of the outer
	// cone (w; below -1 for a point light); pointColor's w the inner cone's
	var spot0:Vec4;
	var spot1:Vec4;
	var spot2:Vec4;
	var spot3:Vec4;
	// the second shadow cascade (Shadows with two: the whole scene's map,
	// read where the first, near the camera, does not reach; else the first's)
	var lightViewProjFar:Mat4;
	var shadowFar:Vec4;
	// the environment's light (Environment): x its intensity (0: none, the
	// sky and the ground instead), y its map's mip levels below the first;
	// a prefiltered atlas's (Environment.prefiltered): z its levels of
	// roughness (0: a mip-mapped image), w half a texel of a row
	var environment:Vec4;
	// a rim light (Renderer.rim): rgb its colour times intensity, w the
	// falloff's power; the silhouette's edge lit from the light's side
	var rim:Vec4;
}

// per draw: the node's matrices
@:structInit @:publicFields class PbrObject {
	var model:Mat4;
	var normalMatrix:Mat4;
	var tint:Vec4; // rgb: the node's tint (MeshRenderer.tint)
}

// per draw: the material
@:structInit @:publicFields class PbrMaterial {
	var baseColor:Vec4;
	var params:Vec4; // x: metallic, y: roughness, z: the normal map's scale, w: 1 double-sided
	var emissive:Vec4; // rgb; w: its share emitted on the night side only (Material.emissiveNight)
	var ground:Vec4; // x: Material.ground, y: the air's strength (Material.air's w), z: Material.crystal
	var air:Vec4; // rgb: the air's colour (Material.air)
	// the textures' uv transform (Material.uvOffset, uvRotation, uvScale):
	// u = dot(uvU.xy, uv) + uvU.z, v likewise by uvV
	var uvU:Vec4;
	var uvV:Vec4;
	// x: Material.clearcoat, y: its roughness, z: Material.transmission, w: Material.alphaCutoff
	var layers:Vec4;
}

class PbrShader implements Shaders {
	// a material's block (PbrMaterial) as the renderer writes it
	public static function materialOf(m:Material):PbrMaterial {
		var c = Math.cos(m.uvRotation), s = Math.sin(m.uvRotation);
		return {
			baseColor: m.baseColor,
			params: new Vec4(m.metallic, m.roughness, m.normalScale, m.doubleSided ? 1 : 0),
			emissive: new Vec4(m.emissive.x, m.emissive.y, m.emissive.z, m.emissiveNight),
			ground: new Vec4(m.ground, m.air.w, m.crystal, 0),
			air: m.air,
			uvU: new Vec4(c * m.uvScale.x, s * m.uvScale.y, m.uvOffset.x, 0),
			uvV: new Vec4(-s * m.uvScale.x, c * m.uvScale.y, m.uvOffset.y, 0),
			layers: new Vec4(m.clearcoat, m.clearcoatRoughness, m.transmission, m.alphaCutoff)
		};
	}

	// a vertex's uvs as the material's textures read them (KHR_texture_transform)
	public static function uvOf(material:PbrMaterial, uv:Vec2):Vec2
		return vec2(dot(material.uvU.xy, uv) + material.uvU.z, dot(material.uvV.xy, uv) + material.uvV.z);

	@:vertex static function vs(v:PbrVertex, frame:PbrFrame, object:PbrObject):PbrVaryings {
		var world = object.model * vec4(v.pos, 1);
		return {
			clip: frame.viewProj * world,
			world: world.xyz,
			normal: (object.normalMatrix * vec4(v.normal, 0)).xyz,
			uv: v.uv,
			up: (object.model * vec4(0, 1, 0, 0)).xyz,
			tint: object.tint.xyz
		};
	}

	@:fragment static function fs(i:PbrVaryings, frame:PbrFrame, material:PbrMaterial, baseColorTexture:Texture2D, metallicRoughnessTexture:Texture2D,
			emissiveTexture:Texture2D, occlusionTexture:Texture2D, shadowMap:Texture2D, shadowMapFar:Texture2D, environmentMap:Texture2D):Vec4
		return shadeAt(normalize(i.normal), i.world, uvOf(material, i.uv), normalize(i.up), i.tint, frame, material, baseColorTexture, metallicRoughnessTexture,
			emissiveTexture, occlusionTexture, shadowMap, shadowMapFar, environmentMap);

	// the fragment's colour at a point of the world with a unit normal n, the
	// node's unit up and its tint (also the instanced, skinned and
	// normal-mapped shaders'), uv already the material's (uvOf)
	public static function shadeAt(facing:Vec3, world:Vec3, uv:Vec2, up:Vec3, tint:Vec3, frame:PbrFrame, material:PbrMaterial, baseColorTexture:Texture2D,
			metallicRoughnessTexture:Texture2D, emissiveTexture:Texture2D, occlusionTexture:Texture2D, shadowMap:Texture2D, shadowMapFar:Texture2D, environmentMap:Texture2D):Vec4 {
		var texel = sample(baseColorTexture, uv);
		// (the texture's sRGB decoded)
		var base = material.baseColor.xyz * pow(texel.xyz, vec3(2.2)) * tint;
		// (glTF's: roughness in green, metallic in blue, linear)
		var mr = sample(metallicRoughnessTexture, uv);
		var crystal = material.ground.z;
		var metallic = clamp(material.params.x * mr.z, 0, 1);
		// (a crystal: polished whatever its roughness)
		var rough = clamp(mix(material.params.y * mr.y, 0.07, crystal), 0.04, 1);
		var v = normalize(frame.eye.xyz - world);
		// (double-sided: a face seen from behind lit by its normal turned
		// to the eye, not by its front's: a model's inward walls lit as walls)
		var n = material.params.w > 0.5 && dot(facing, v) < 0 ? -facing : facing;
		var l = frame.lightDir.xyz;
		var nv = max(dot(n, v), 0.0001);
		var a = rough * rough;
		var a2 = a * a;
		// (a crystal's dielectric reflectance higher than glass's: a gem's)
		var f0 = mix(mix(vec3(0.04), base, metallic), vec3(0.12), crystal);
		// (standing on a sphere (Material.ground): its up the sphere's normal
		// under it, the sun set there as on the ground around it, faded
		// across the terminator as the planet's own light is)
		var sunUp = dot(up, l);
		var day = mix(1.0, smoothstep(-0.08, 0.22, sunUp), material.ground.x);
		var direct = brdf(n, v, l, base, metallic, a2, f0) * frame.lightColor.xyz * (shadowed(frame, shadowMap, shadowMapFar, world, max(dot(n, l), 0)) * day);
		direct += point(n, v, world, base, metallic, a2, f0, frame.point0, frame.pointColor0, frame.spot0)
			+ point(n, v, world, base, metallic, a2, f0, frame.point1, frame.pointColor1, frame.spot1)
			+ point(n, v, world, base, metallic, a2, f0, frame.point2, frame.pointColor2, frame.spot2)
			+ point(n, v, world, base, metallic, a2, f0, frame.point3, frame.pointColor3, frame.spot3);
		// the ambient: the sky and the ground blended by the normal (diffuse)
		// and by the reflection (specular, Karis' fit of the split sum)
		var above = n.y * 0.5 + 0.5;
		var irradiance = mix(frame.ground.xyz, frame.sky.xyz, above);
		var r = reflect(-v, n);
		var env = reflected(frame, environmentMap, r, rough);
		if (frame.environment.x > 0) {
			// (an environment map: its small levels along the normal; a
			// prefiltered atlas's last row, the irradiance)
			var top = frame.environment.y;
			irradiance = pow(sampleLevel(environmentMap, EnvironmentShader.equirect(n), max(top - 2, 0)).xyz, vec3(2.2)) * frame.environment.x;
			if (frame.environment.z > 0) {
				var rows = frame.environment.z;
				irradiance = pow(EnvironmentShader.atlas(environmentMap, EnvironmentShader.equirect(n), rows, rows, frame.environment.w), vec3(2.2)) * frame.environment.x;
			}
		}
		var c0 = vec4(-1, -0.0275, -0.572, 0.022);
		var c1 = vec4(1, 0.0425, 1.04, -0.04);
		var rr = c0 * rough + c1;
		var a004 = min(rr.x * rr.x, pow(2, -9.28 * nv)) * rr.x + rr.y;
		var ab = vec2(-1.04, 1.04) * a004 + rr.zw;
		// (standing on a sphere (Material.ground): below its horizon (about
		// up) it reflects the sphere's dark ground, not the sky beyond it,
		// and gets less of the sky's light the more it faces down; on the
		// night side the sky it reflects half the dark ground's)
		var horizon = smoothstep(-0.2, 0.2, dot(r, up));
		var specularAmbient = env * (f0 * ab.x + ab.y) * mix(1.0, mix(0.12, 1, horizon) * (0.45 + 0.55 * day), material.ground.x);
		irradiance = irradiance * mix(1.0, 0.55 + 0.45 * smoothstep(-0.6, 0.6, dot(n, up)), material.ground.x);
		// (occlusion, in red, darkens the ambient only)
		var occlusion = sample(occlusionTexture, uv).x;
		var ambient = (irradiance * base * (1 - metallic) + specularAmbient) * occlusion;
		var emitted = material.emissive.xyz * pow(sample(emissiveTexture, uv).xyz, vec3(2.2));
		// (city lights: on the night side, faded in past the terminator)
		emitted = emitted * mix(1.0, smoothstep(0.12, -0.18, dot(n, l)), material.emissive.w);
		// (the rim: grazing views, on the light's side and a little past it)
		var edge = 1 - nv;
		var rim = frame.rim.xyz * (pow(edge, frame.rim.w) * smoothstep(-0.25, 0.5, dot(n, l)) * day);
		direct += rim * mix(vec3(1), base, 0.5);
		var alpha = material.baseColor.w * texel.w;
		var coat = material.layers.x;
		if (coat > 0) {
			// (a clear coat (Material.clearcoat): a polished dielectric's
			// reflection of the sun and the environment over the base, which
			// it dims by its Fresnel)
			var cr = clamp(material.layers.y, 0.04, 1);
			var ca = cr * cr;
			var fc = (0.04 + 0.96 * pow(1 - nv, 5)) * coat;
			var lit = shadowed(frame, shadowMap, shadowMapFar, world, max(dot(n, l), 0)) * day;
			var layer = coatLobe(n, v, l, ca * ca) * frame.lightColor.xyz * (lit * coat) + reflected(frame, environmentMap, r, cr) * fc;
			direct = direct * (1 - fc);
			ambient = ambient * (1 - fc) + layer;
		}
		if (crystal > 0) {
			// (a crystal (Material.crystal): the environment's reflection
			// stronger at grazing angles (Fresnel); light from inside, its
			// emissive colour lifted towards white where it is seen through
			// most (facing the eye: a fake subsurface), and the sun through it
			// from behind; its edges opaque and bright, its middle see-through
			// by the base colour's alpha (with Material.blend))
			var fres = pow(edge, 3);
			var glow = mix(material.emissive.xyz, vec3(dot(material.emissive.xyz, vec3(0.3, 0.4, 0.3))) * 1.6 + material.emissive.xyz * 0.4, 0.22);
			var inner = glow * (0.35 + 0.65 * nv * nv) * (0.75 + 0.25 * day);
			var through = frame.lightColor.xyz * base * (pow(max(dot(v, -l), 0), 6) * 0.6 * day);
			var sheen = (env * 1.4 + frame.rim.xyz * day) * (f0 + (1 - f0) * fres) * fres;
			emitted = mix(emitted, inner + through, crystal) + sheen * crystal;
			alpha = mix(alpha, 1, fres * crystal);
		}
		var transmission = max(material.layers.z, 0) * (1 - metallic);
		if (transmission > 0) {
			// (transmission (Material.transmission): the diffuse light let
			// through, what is behind showing instead (premultiplied: the
			// reflections over it as they are))
			var diffuse = (irradiance * base * (1 - metallic)) * occlusion;
			ambient = ambient - diffuse * transmission;
			direct = direct * (1 - transmission * 0.9);
		}
		var color = (direct + ambient + emitted) * frame.exposure.x;
		// (the air (Material.air): towards its sphere's limb, as seen through
		// more of the atmosphere, its colour lit by the sun over the ground)
		var limb = 1 - max(dot(up, v), 0);
		var haze = material.ground.y * limb * limb;
		color = mix(color, material.air.xyz * (0.12 + 0.88 * smoothstep(-0.2, 0.35, sunUp)) * frame.exposure.x, haze);
		var shown = output(color, frame.exposure.y);
		// (alphaMode MASK: below the cutoff dropped, else opaque)
		if (material.layers.w > 0) {
			if (alpha < material.layers.w) discard();
			alpha = 1;
		}
		if (transmission > 0) {
			shown = shown * alpha;
			alpha = alpha * (1 - transmission);
		}
		if (material.layers.z < 0) {
			// (a transmitting surface's first draw (Renderer, Multiply): what
			// is behind times its colour, where the light goes through; an
			// 8-bit target's colours encoded)
			var through = -material.layers.z * (1 - metallic) * alpha;
			var filter = mix(vec3(1), base, through);
			shown = frame.exposure.y > 0.5 ? filter : encode(filter);
			alpha = 1;
		}
		return vec4(shown, alpha);
	}

	// the light from the environment along a reflection r at a roughness:
	// a prefiltered atlas's two rows by it, blended, a mip-mapped image's
	// level by it, else the sky and the ground blended by r's height
	static function reflected(frame:PbrFrame, environmentMap:Texture2D, r:Vec3, rough:Float):Vec3 {
		var env = mix(frame.ground.xyz, frame.sky.xyz, smoothstep(-0.2, 0.2, r.y));
		if (frame.environment.x > 0) {
			var top = frame.environment.y;
			env = pow(sampleLevel(environmentMap, EnvironmentShader.equirect(r), rough * max(top - 1, 0)).xyz, vec3(2.2)) * frame.environment.x;
			if (frame.environment.z > 0) {
				var rows = frame.environment.z;
				var edge = frame.environment.w;
				var at = rough * (rows - 1);
				var r0 = floor(at);
				var ru = EnvironmentShader.equirect(r);
				var lo = EnvironmentShader.atlas(environmentMap, ru, r0, rows, edge);
				var hi = EnvironmentShader.atlas(environmentMap, ru, min(r0 + 1, rows - 1), rows, edge);
				env = pow(mix(lo, hi, at - r0), vec3(2.2)) * frame.environment.x;
			}
		}
		return env;
	}

	// a clear coat's specular lobe towards v from a unit light along l,
	// times n.l (GGX, height-correlated Smith, a dielectric's Fresnel)
	static function coatLobe(n:Vec3, v:Vec3, l:Vec3, a2:Float):Vec3 {
		var h = normalize(l + v);
		var nl = max(dot(n, l), 0);
		var nv = max(dot(n, v), 0.0001);
		var nh = max(dot(n, h), 0);
		var fresnel = 0.04 + 0.96 * pow(1 - max(dot(v, h), 0), 5);
		var dd = nh * nh * (a2 - 1) + 1;
		var visibility = 0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001);
		return vec3(fresnel * a2 / (3.14159265 * dd * dd) * visibility * nl);
	}

	// the light reflected towards v from a unit light along l, times n.l:
	// Lambert's diffuse and Cook-Torrance's specular (GGX, height-correlated
	// Smith, Schlick)
	static function brdf(n:Vec3, v:Vec3, l:Vec3, base:Vec3, metallic:Float, a2:Float, f0:Vec3):Vec3 {
		var h = normalize(l + v);
		var nl = max(dot(n, l), 0);
		var nv = max(dot(n, v), 0.0001);
		var nh = max(dot(n, h), 0);
		var vh = max(dot(v, h), 0);
		var fresnel = f0 + (1 - f0) * pow(1 - vh, 5);
		var dd = nh * nh * (a2 - 1) + 1;
		var distribution = a2 / (3.14159265 * dd * dd);
		var visibility = 0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001);
		var diffuse = (1 - fresnel) * (1 - metallic) * base / 3.14159265;
		return (diffuse + fresnel * (distribution * visibility)) * nl;
	}

	// a point or spot light at pos.xyz (pos.w: its range, 0 for no light): the
	// inverse square falloff windowed to reach 0 at the range (glTF's
	// KHR_lights_punctual)
	static function point(n:Vec3, v:Vec3, world:Vec3, base:Vec3, metallic:Float, a2:Float, f0:Vec3, pos:Vec4, color:Vec4, spot:Vec4):Vec3 {
		var result = vec3(0);
		if (pos.w > 0) {
			var d = pos.xyz - world;
			var dist2 = max(dot(d, d), 0.0001);
			var dist = sqrt(dist2);
			var q = dist / pos.w;
			var window = clamp(1 - q * q * q * q, 0, 1);
			// (a spot light: full inside the inner cone, nothing outside the outer)
			var cone = 1.0;
			if (spot.w > -1.5) cone = smoothstep(spot.w, color.w, dot(-d / dist, spot.xyz));
			result = brdf(n, v, d / dist, base, metallic, a2, f0) * color.xyz * (window * window / dist2 * cone);
		}
		return result;
	}

	// the direct light's share at a point (1: lit) from the shadow maps: the
	// first cascade's where it reaches, else the second's; a 3x3
	// percentage-closer filter; 1 outside them or without shadows
	static function shadowed(frame:PbrFrame, map:Texture2D, far:Texture2D, world:Vec3, nl:Float):Float {
		var strength = frame.shadow.x;
		var result = 1.0;
		if (strength > 0) {
			var lit = cascade(map, frame.lightViewProj, frame.shadow, world, nl);
			if (lit < 0) lit = cascade(far, frame.lightViewProjFar, frame.shadowFar, world, nl);
			if (lit >= 0) result = 1 - strength * (1 - lit / 9);
		}
		return result;
	}

	// a cascade's lit taps (0 to 9) at a point, or -1 where its map does not
	// reach (params: y the bias, z a texel of the map)
	static function cascade(map:Texture2D, viewProj:Mat4, params:Vec4, world:Vec3, nl:Float):Float {
		var result = -1.0;
		var ls = viewProj * vec4(world, 1);
		var p = ls.xyz / ls.w;
		var uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
		if (uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1 && p.z < 1) {
			// (more bias where the light grazes the surface)
			var depth = p.z - params.y * (1 + 2 * (1 - nl));
			var t = params.z;
			result = tap(map, uv, depth, -t, -t) + tap(map, uv, depth, 0, -t) + tap(map, uv, depth, t, -t) + tap(map, uv, depth, -t, 0)
				+ tap(map, uv, depth, 0, 0) + tap(map, uv, depth, t, 0) + tap(map, uv, depth, -t, t) + tap(map, uv, depth, 0, t)
				+ tap(map, uv, depth, t, t);
		}
		return result;
	}

	// 1 where the map's depth at uv + (dx, dy) is not nearer than depth
	static function tap(map:Texture2D, uv:Vec2, depth:Float, dx:Float, dy:Float):Float
		return step(depth, sampleLevel(map, uv + vec2(dx, dy), 0).x);

	// a colour in linear light as the target takes it: as it is into an HDR
	// target (hdr 1: a half-float one, tone mapped by a PostProcess), else
	// tone mapped and encoded for an 8-bit one (the shaders that draw into
	// a Renderer's targets end with it)
	public static function output(c:Vec3, hdr:Float):Vec3 {
		var result = c;
		if (hdr < 0.5) result = encode(aces(c));
		return result;
	}

	// ACES filmic tone mapping (Narkowicz's fit), to 0..1
	public static function aces(x:Vec3):Vec3
		return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0, 1);

	// a display colour's light (0..1, encoded as encode's) in an HDR target:
	// what aces and encode turn back into it (Narkowicz's curve solved for
	// x), so an image made for the display (a painted backdrop, a ui's
	// colour) looks as it did once a PostProcess tone maps with Aces
	public static function unaces(display:Vec3):Vec3 {
		var y = clamp(pow(display, vec3(2.2)), 0, 0.985);
		var a = 2.43 * y - 2.51;
		var b = 0.59 * y - 0.03;
		var c = 0.14 * y;
		return (-b - sqrt(max(b * b - 4 * a * c, vec3(0)))) / (2 * a);
	}

	// linear to sRGB (the 2.2 power: the frame's format is not an sRGB one)
	public static function encode(c:Vec3):Vec3
		return pow(c, vec3(1 / 2.2));
}
