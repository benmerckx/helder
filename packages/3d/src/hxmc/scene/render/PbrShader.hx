package hxmc.scene.render;

import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The renderer's shader (Renderer): glTF's metallic-roughness model lit by
// a directional light and a sky-and-ground ambient, in linear light,
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
}

// per frame: the camera and the lights
@:structInit @:publicFields class PbrFrame {
	var viewProj:Mat4;
	var eye:Vec4; // xyz: the camera's position
	var lightDir:Vec4; // xyz: towards the light, normalized
	var lightColor:Vec4; // rgb: colour times intensity
	var sky:Vec4; // the ambient from above, rgb
	var ground:Vec4; // the ambient from below, rgb
	var exposure:Vec4; // x: exposure
	var lightViewProj:Mat4; // the shadow map's view-projection (Shadows)
	var shadow:Vec4; // x: strength (0: no shadows), y: bias, z: a texel of the map
}

// per draw: the node's matrices
@:structInit @:publicFields class PbrObject {
	var model:Mat4;
	var normalMatrix:Mat4;
}

// per draw: the material
@:structInit @:publicFields class PbrMaterial {
	var baseColor:Vec4;
	var params:Vec4; // x: metallic, y: roughness
	var emissive:Vec4; // rgb
}

class PbrShader implements Shaders {
	@:vertex static function vs(v:PbrVertex, frame:PbrFrame, object:PbrObject):PbrVaryings {
		var world = object.model * vec4(v.pos, 1);
		return {
			clip: frame.viewProj * world,
			world: world.xyz,
			normal: (object.normalMatrix * vec4(v.normal, 0)).xyz,
			uv: v.uv
		};
	}

	@:fragment static function fs(i:PbrVaryings, frame:PbrFrame, material:PbrMaterial, baseColorTexture:Texture2D, shadowMap:Texture2D):Vec4 {
		var texel = sample(baseColorTexture, i.uv);
		// (the texture's sRGB decoded)
		var base = material.baseColor.xyz * pow(texel.xyz, vec3(2.2));
		var metallic = clamp(material.params.x, 0, 1);
		var rough = clamp(material.params.y, 0.04, 1);
		var n = normalize(i.normal);
		var v = normalize(frame.eye.xyz - i.world);
		var l = frame.lightDir.xyz;
		var h = normalize(l + v);
		var nl = max(dot(n, l), 0);
		var nv = max(dot(n, v), 0.0001);
		var nh = max(dot(n, h), 0);
		var vh = max(dot(v, h), 0);
		var a = rough * rough;
		var a2 = a * a;
		var f0 = mix(vec3(0.04), base, metallic);
		var fresnel = f0 + (1 - f0) * pow(1 - vh, 5);
		var dd = nh * nh * (a2 - 1) + 1;
		var distribution = a2 / (3.14159265 * dd * dd);
		var visibility = 0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001);
		var diffuse = (1 - fresnel) * (1 - metallic) * base / 3.14159265;
		var direct = (diffuse + fresnel * (distribution * visibility)) * frame.lightColor.xyz * nl * shadowed(frame, shadowMap, i.world, nl);
		// the ambient: the sky and the ground blended by the normal (diffuse)
		// and by the reflection (specular, Karis' fit of the split sum)
		var up = n.y * 0.5 + 0.5;
		var irradiance = mix(frame.ground.xyz, frame.sky.xyz, up);
		var r = reflect(-v, n);
		var env = mix(frame.ground.xyz, frame.sky.xyz, smoothstep(-0.2, 0.2, r.y));
		var c0 = vec4(-1, -0.0275, -0.572, 0.022);
		var c1 = vec4(1, 0.0425, 1.04, -0.04);
		var rr = c0 * rough + c1;
		var a004 = min(rr.x * rr.x, pow(2, -9.28 * nv)) * rr.x + rr.y;
		var ab = vec2(-1.04, 1.04) * a004 + rr.zw;
		var specularAmbient = env * (f0 * ab.x + ab.y);
		var ambient = irradiance * base * (1 - metallic) + specularAmbient;
		var color = (direct + ambient + material.emissive.xyz) * frame.exposure.x;
		return vec4(encode(aces(color)), material.baseColor.w * texel.w);
	}

	// the direct light's share at a point (1: lit) from the shadow map: a
	// 3x3 percentage-closer filter; 1 outside the map or without shadows
	static function shadowed(frame:PbrFrame, map:Texture2D, world:Vec3, nl:Float):Float {
		var strength = frame.shadow.x;
		var result = 1.0;
		if (strength > 0) {
			var ls = frame.lightViewProj * vec4(world, 1);
			var p = ls.xyz / ls.w;
			var uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
			if (uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1 && p.z < 1) {
				// (more bias where the light grazes the surface)
				var depth = p.z - frame.shadow.y * (1 + 2 * (1 - nl));
				var t = frame.shadow.z;
				var lit = tap(map, uv, depth, -t, -t) + tap(map, uv, depth, 0, -t) + tap(map, uv, depth, t, -t) + tap(map, uv, depth, -t, 0)
					+ tap(map, uv, depth, 0, 0) + tap(map, uv, depth, t, 0) + tap(map, uv, depth, -t, t) + tap(map, uv, depth, 0, t)
					+ tap(map, uv, depth, t, t);
				result = 1 - strength * (1 - lit / 9);
			}
		}
		return result;
	}

	// 1 where the map's depth at uv + (dx, dy) is not nearer than depth
	static function tap(map:Texture2D, uv:Vec2, depth:Float, dx:Float, dy:Float):Float
		return step(depth, sampleLevel(map, uv + vec2(dx, dy), 0).x);

	// ACES filmic tone mapping (Narkowicz's fit), to 0..1
	static function aces(x:Vec3):Vec3
		return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0, 1);

	// linear to sRGB (the 2.2 power: the frame's format is not an sRGB one)
	static function encode(c:Vec3):Vec3
		return pow(c, vec3(1 / 2.2));
}
