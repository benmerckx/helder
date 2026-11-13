// helder.scene's standard material for TypeScript: pbr, the slot object of
// src/helder/scene/render/PbrShader.hx in TypeScript (the same stages,
// slots, options, structs and functions, helder/gfx's operators as methods),
// so that a program's material(pbr.with({...})) compiles with the
// program: its variants are the renderer's (plain, normal mapped, skinned,
// instanced, instanced and normal mapped) and draw what Haxe's draw
// (tests/3d's ts-glow frame is glow.png). Keep it in step with
// PbrShader.hx: what one changes the other does.
import {
	slots, position, vec2, vec3, vec4, mat4, sample, sampleLevel, dot, cross, normalize, reflect, mix, clamp, smoothstep, pow, min, max, abs,
	sqrt, floor, fract, step, discard, length, exp, type Vec2, type Vec3, type Vec4, type Mat4, type Texture2D,
} from "helder/gfx";

// the combined vertex: a variant's attributes those it reads, in this order
export type PbrVertex = {
	pos: Vec3, normal: Vec3, uv: Vec2,
	tangent?: Vec4, joints?: Vec4, weights?: Vec4, m0?: Vec4, m1?: Vec4, m2?: Vec4, m3?: Vec4,
};

export type PbrVaryings = {clip: Vec4, world: Vec3, normal: Vec3, uv: Vec2, tangent?: Vec4, up: Vec3, tint: Vec3};

// per frame: the camera and the lights (PbrShader.hx's PbrFrame)
export type PbrFrame = {
	viewProj: Mat4, eye: Vec4, lightDir: Vec4, lightColor: Vec4, sky: Vec4, ground: Vec4, exposure: Vec4, lightViewProj: Mat4, shadow: Vec4,
	point0: Vec4, point1: Vec4, point2: Vec4, point3: Vec4, pointColor0: Vec4, pointColor1: Vec4, pointColor2: Vec4, pointColor3: Vec4,
	spot0: Vec4, spot1: Vec4, spot2: Vec4, spot3: Vec4, lightViewProjFar: Mat4, shadowFar: Vec4, environment: Vec4, rim: Vec4,
	fog: Vec4, fogShape: Vec4, shadowSoft: Vec4,
};

// per draw: the node's matrices
export type PbrObject = {model: Mat4, normalMatrix: Mat4, tint: Vec4};

// per draw: the material
export type PbrMaterial = {baseColor: Vec4, params: Vec4, emissive: Vec4, ground: Vec4, air: Vec4, uvU: Vec4, uvV: Vec4, layers: Vec4};

export type PbrSkinInfo = {rows: Vec4};

export type PbrVertexParams = {frame: PbrFrame, object?: PbrObject, skin?: PbrSkinInfo, jointMatrices?: Texture2D};

export type PbrFragmentParams = {
	frame: PbrFrame, material: PbrMaterial, baseColorTexture: Texture2D, metallicRoughnessTexture: Texture2D, emissiveTexture: Texture2D,
	occlusionTexture: Texture2D, shadowMap: Texture2D, shadowMapFar: Texture2D, environmentMap: Texture2D, normalTexture?: Texture2D,
};

export type PbrOptions = {normalMap: boolean, skinned: boolean, instanced: boolean};

// what the fragment's slots read: the point in the world, its unit normal,
// the material's uvs, the node's unit up, the base colour (linear)
export type PbrSurface = {world: Vec3, normal: Vec3, uv: Vec2, up: Vec3, baseColor: Vec4};

// what the position slot reads: the vertex's point, normal and uvs
export type PbrPoint = {pos: Vec3, normal: Vec3, uv: Vec2};

// the slot object (the stages' third parameter): its options, its slots
export type Pbr = {
	options: PbrOptions,
	color: (s: PbrSurface, p: PbrFragmentParams) => Vec3,
	alpha: (s: PbrSurface, p: PbrFragmentParams) => number,
	normal: (s: PbrSurface, p: PbrFragmentParams) => Vec3,
	roughness: (s: PbrSurface, p: PbrFragmentParams) => number,
	metalness: (s: PbrSurface, p: PbrFragmentParams) => number,
	emissive: (s: PbrSurface, p: PbrFragmentParams) => Vec3,
	position: (v: PbrPoint, p: PbrVertexParams) => Vec3,
};

// a vertex's uvs as the material's textures read them (KHR_texture_transform)
function uvOf(material: PbrMaterial, uv: Vec2): Vec2 {
	return vec2(dot(material.uvU.xy, uv) + material.uvU.z, dot(material.uvV.xy, uv) + material.uvV.z);
}

// the slots' defaults
export function pbrColor(s: PbrSurface, p: {}): Vec3 {
	return s.baseColor.xyz;
}

export function pbrAlpha(s: PbrSurface, p: {}): number {
	return s.baseColor.w;
}

export function pbrNormal(s: PbrSurface, p: {}): Vec3 {
	return s.normal;
}

export function pbrMetalness(s: PbrSurface, p: {material: PbrMaterial, metallicRoughnessTexture: Texture2D}): number {
	return clamp(p.material.params.x * sample(p.metallicRoughnessTexture, s.uv).z, 0, 1);
}

export function pbrRoughness(s: PbrSurface, p: {material: PbrMaterial, metallicRoughnessTexture: Texture2D}): number {
	return clamp(mix(p.material.params.y * sample(p.metallicRoughnessTexture, s.uv).y, 0.07, p.material.ground.z), 0.04, 1);
}

export function pbrEmissive(s: PbrSurface, p: {material: PbrMaterial, emissiveTexture: Texture2D}): Vec3 {
	return p.material.emissive.xyz.mul(pow(sample(p.emissiveTexture, s.uv).xyz, vec3(2.2)));
}

export function pbrPosition(v: PbrPoint, p: {}): Vec3 {
	return v.pos;
}

// (Equirect.hx's)
function equirect(d: Vec3): Vec2 {
	return vec2(arcTan2(d.x, -d.z) * 0.15915494 + 0.5, arcCos(clamp(d.y, -1, 1)) * 0.31830989);
}

function atlas(t: Texture2D, uv: Vec2, row: number, levels: number, edge: number): Vec3 {
	return sampleLevel(t, vec2(uv.x, (row + clamp(uv.y, edge, 1 - edge)) / (levels + 1)), 0).xyz;
}

function arcTan2(y: number, x: number): number {
	const ax = abs(x), ay = abs(y);
	const a = min(ax, ay) / max(max(ax, ay), 0.000001);
	const s = a * a;
	let r = a * (0.999866 + s * (-0.3302995 + s * (0.180141 + s * (-0.085133 + s * 0.0208351))));
	if (ay > ax) r = 1.5707964 - r;
	if (x < 0) r = 3.1415927 - r;
	if (y < 0) r = -r;
	return r;
}

function arcCos(x: number): number {
	const ax = abs(x);
	let r = sqrt(1 - ax) * (1.5707288 + ax * (-0.2121144 + ax * (0.074261 - 0.0187293 * ax)));
	if (x < 0) r = 3.1415927 - r;
	return r;
}

// the fragment's colour from its surface's terms
function shade(facing: Vec3, world: Vec3, uv: Vec2, up: Vec3, base: Vec3, baseAlpha: number, metallic: number, rough: number, emissive: Vec3,
		frame: PbrFrame, material: PbrMaterial, occlusionTexture: Texture2D, shadowMap: Texture2D, shadowMapFar: Texture2D, environmentMap: Texture2D): Vec4 {
	const crystal = material.ground.z;
	const v = normalize(frame.eye.xyz.sub(world));
	const n = material.params.w > 0.5 && dot(facing, v) < 0 ? facing.neg() : facing;
	const l = frame.lightDir.xyz;
	const nv = max(dot(n, v), 0.0001);
	const a = rough * rough;
	const a2 = a * a;
	const f0 = mix(mix(vec3(0.04), base, metallic), vec3(0.12), crystal);
	const sunUp = dot(up, l);
	const day = mix(1.0, smoothstep(-0.08, 0.22, sunUp), material.ground.x);
	let direct = brdf(n, v, l, base, metallic, a2, f0).mul(frame.lightColor.xyz).mul(shadowed(frame, shadowMap, shadowMapFar, world, max(dot(n, l), 0)) * day);
	direct = direct.add(point(n, v, world, base, metallic, a2, f0, frame.point0, frame.pointColor0, frame.spot0)
		.add(point(n, v, world, base, metallic, a2, f0, frame.point1, frame.pointColor1, frame.spot1))
		.add(point(n, v, world, base, metallic, a2, f0, frame.point2, frame.pointColor2, frame.spot2))
		.add(point(n, v, world, base, metallic, a2, f0, frame.point3, frame.pointColor3, frame.spot3)));
	const above = n.y * 0.5 + 0.5;
	let irradiance = mix(frame.ground.xyz, frame.sky.xyz, above);
	const r = reflect(v.neg(), n);
	const env = reflected(frame, environmentMap, r, rough);
	if (frame.environment.x > 0) {
		const top = frame.environment.y;
		irradiance = pow(sampleLevel(environmentMap, equirect(n), max(top - 2, 0)).xyz, vec3(2.2)).mul(frame.environment.x);
		if (frame.environment.z > 0) {
			const rows = frame.environment.z;
			irradiance = pow(atlas(environmentMap, equirect(n), rows, rows, frame.environment.w), vec3(2.2)).mul(frame.environment.x);
		}
	}
	const c0 = vec4(-1, -0.0275, -0.572, 0.022);
	const c1 = vec4(1, 0.0425, 1.04, -0.04);
	const rr = c0.mul(rough).add(c1);
	const a004 = min(rr.x * rr.x, pow(2, -9.28 * nv)) * rr.x + rr.y;
	const ab = vec2(-1.04, 1.04).mul(a004).add(rr.zw);
	const horizon = smoothstep(-0.2, 0.2, dot(r, up));
	const specularAmbient = env.mul(f0.mul(ab.x).add(ab.y)).mul(mix(1.0, mix(0.12, 1, horizon) * (0.45 + 0.55 * day), material.ground.x));
	irradiance = irradiance.mul(mix(1.0, 0.55 + 0.45 * smoothstep(-0.6, 0.6, dot(n, up)), material.ground.x));
	const occlusion = sample(occlusionTexture, uv).x;
	let ambient = irradiance.mul(base).mul(1 - metallic).add(specularAmbient).mul(occlusion);
	let emitted = emissive;
	emitted = emitted.mul(mix(1.0, smoothstep(0.12, -0.18, dot(n, l)), material.emissive.w));
	const edge = 1 - nv;
	const rim = frame.rim.xyz.mul(pow(edge, frame.rim.w) * smoothstep(-0.25, 0.5, dot(n, l)) * day);
	direct = direct.add(rim.mul(mix(vec3(1), base, 0.5)));
	let alpha = baseAlpha;
	const coat = material.layers.x;
	if (coat > 0) {
		const cr = clamp(material.layers.y, 0.04, 1);
		const ca = cr * cr;
		const fc = (0.04 + 0.96 * pow(1 - nv, 5)) * coat;
		const lit = shadowed(frame, shadowMap, shadowMapFar, world, max(dot(n, l), 0)) * day;
		const layer = coatLobe(n, v, l, ca * ca).mul(frame.lightColor.xyz).mul(lit * coat).add(reflected(frame, environmentMap, r, cr).mul(fc));
		direct = direct.mul(1 - fc);
		ambient = ambient.mul(1 - fc).add(layer);
	}
	if (crystal > 0) {
		const fres = pow(edge, 3);
		const glow = mix(material.emissive.xyz, vec3(dot(material.emissive.xyz, vec3(0.3, 0.4, 0.3))).mul(1.6).add(material.emissive.xyz.mul(0.4)), 0.22);
		const inner = glow.mul(0.35 + 0.65 * nv * nv).mul(0.75 + 0.25 * day);
		const through = frame.lightColor.xyz.mul(base).mul(pow(max(dot(v, l.neg()), 0), 6) * 0.6 * day);
		const sheen = env.mul(1.4).add(frame.rim.xyz.mul(day)).mul(f0.add(vec3(1).sub(f0).mul(fres))).mul(fres);
		emitted = mix(emitted, inner.add(through), crystal).add(sheen.mul(crystal));
		alpha = mix(alpha, 1, fres * crystal);
	}
	const transmission = max(material.layers.z, 0) * (1 - metallic);
	if (transmission > 0) {
		const diffuse = irradiance.mul(base).mul(1 - metallic).mul(occlusion);
		ambient = ambient.sub(diffuse.mul(transmission));
		direct = direct.mul(1 - transmission * 0.9);
	}
	let color = direct.add(ambient).add(emitted).mul(frame.exposure.x);
	const limb = 1 - max(dot(up, v), 0);
	const haze = material.ground.y * limb * limb;
	color = mix(color, material.air.xyz.mul(0.12 + 0.88 * smoothstep(-0.2, 0.35, sunUp)).mul(frame.exposure.x), haze);
	const mist = fogAmount(frame.fog, frame.fogShape, frame.eye.xyz, world) * material.ground.w;
	color = mix(color, material.uvV.w > 0 ? vec3(0) : frame.fog.xyz.mul(frame.exposure.x), mist);
	let shown = output(color, frame.exposure.y);
	if (material.layers.w > 0) {
		if (alpha < material.layers.w) discard();
		alpha = 1;
	}
	if (transmission > 0) {
		shown = shown.mul(alpha);
		alpha = alpha * (1 - transmission);
	}
	if (material.layers.z < 0) {
		const through = -material.layers.z * (1 - metallic) * alpha;
		const filter = mix(vec3(1), base, through * (1 - mist));
		shown = frame.exposure.y > 0.5 ? filter : encode(filter);
		alpha = 1;
	}
	if (material.uvV.w > 0) shown = shown.mul(alpha);
	return vec4(shown, alpha);
}

// the light from the environment along a reflection r at a roughness
function reflected(frame: PbrFrame, environmentMap: Texture2D, r: Vec3, rough: number): Vec3 {
	let env = mix(frame.ground.xyz, frame.sky.xyz, smoothstep(-0.2, 0.2, r.y));
	if (frame.environment.x > 0) {
		const top = frame.environment.y;
		env = pow(sampleLevel(environmentMap, equirect(r), rough * max(top - 1, 0)).xyz, vec3(2.2)).mul(frame.environment.x);
		if (frame.environment.z > 0) {
			const rows = frame.environment.z;
			const edge = frame.environment.w;
			const at = rough * (rows - 1);
			const r0 = floor(at);
			const ru = equirect(r);
			const lo = atlas(environmentMap, ru, r0, rows, edge);
			const hi = atlas(environmentMap, ru, min(r0 + 1, rows - 1), rows, edge);
			env = pow(mix(lo, hi, at - r0), vec3(2.2)).mul(frame.environment.x);
		}
	}
	return env;
}

// a clear coat's specular lobe
function coatLobe(n: Vec3, v: Vec3, l: Vec3, a2: number): Vec3 {
	const h = normalize(l.add(v));
	const nl = max(dot(n, l), 0);
	const nv = max(dot(n, v), 0.0001);
	const nh = max(dot(n, h), 0);
	const fresnel = 0.04 + 0.96 * pow(1 - max(dot(v, h), 0), 5);
	const dd = nh * nh * (a2 - 1) + 1;
	const visibility = 0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001);
	return vec3(fresnel * a2 / (3.14159265 * dd * dd) * visibility * nl);
}

// Lambert's diffuse and Cook-Torrance's specular, times n.l
function brdf(n: Vec3, v: Vec3, l: Vec3, base: Vec3, metallic: number, a2: number, f0: Vec3): Vec3 {
	const h = normalize(l.add(v));
	const nl = max(dot(n, l), 0);
	const nv = max(dot(n, v), 0.0001);
	const nh = max(dot(n, h), 0);
	const vh = max(dot(v, h), 0);
	const fresnel = f0.add(vec3(1).sub(f0).mul(pow(1 - vh, 5)));
	const dd = nh * nh * (a2 - 1) + 1;
	const distribution = a2 / (3.14159265 * dd * dd);
	const visibility = 0.5 / max(nl * sqrt(nv * nv * (1 - a2) + a2) + nv * sqrt(nl * nl * (1 - a2) + a2), 0.0001);
	const diffuse = vec3(1).sub(fresnel).mul(1 - metallic).mul(base).div(3.14159265);
	return diffuse.add(fresnel.mul(distribution * visibility)).mul(nl);
}

// a point or spot light at pos.xyz (pos.w: its range, 0 for no light)
function point(n: Vec3, v: Vec3, world: Vec3, base: Vec3, metallic: number, a2: number, f0: Vec3, pos: Vec4, color: Vec4, spot: Vec4): Vec3 {
	let result = vec3(0);
	if (pos.w > 0) {
		const d = pos.xyz.sub(world);
		const dist2 = max(dot(d, d), 0.0001);
		const dist = sqrt(dist2);
		const q = dist / pos.w;
		const window = clamp(1 - q * q * q * q, 0, 1);
		let cone = 1.0;
		if (spot.w > -1.5) cone = smoothstep(spot.w, color.w, dot(d.neg().div(dist), spot.xyz));
		result = brdf(n, v, d.div(dist), base, metallic, a2, f0).mul(color.xyz).mul(window * window / dist2 * cone);
	}
	return result;
}

// the direct light's share at a point (1: lit) from the shadow maps
function shadowed(frame: PbrFrame, map: Texture2D, far: Texture2D, world: Vec3, nl: number): number {
	const strength = frame.shadow.x;
	let result = 1.0;
	if (strength > 0) {
		let lit = cascade(map, frame.lightViewProj, frame.shadow, frame.shadowSoft, frame.shadowSoft.y, world, nl);
		if (lit < 0) lit = cascade(far, frame.lightViewProjFar, frame.shadowFar, frame.shadowSoft, frame.shadowSoft.z, world, nl);
		if (lit >= 0) result = 1 - strength * (1 - lit);
	}
	return result;
}

// a cascade's lit share (0 to 1) at a point, or -1 where its map does not reach
function cascade(map: Texture2D, viewProj: Mat4, params: Vec4, soft: Vec4, deep: number, world: Vec3, nl: number): number {
	let result = -1.0;
	const ls = viewProj.mul(vec4(world, 1));
	const p = ls.xyz.div(ls.w);
	const uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
	if (uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1 && p.z < 1) {
		const depth = p.z - params.y * (1 + 2 * (1 - nl));
		const t = params.z;
		if (soft.x > 0 && params.w > 0) result = softly(map, uv, depth, params.w, t, soft, deep, nl);
		else
			result = (tap(map, uv, depth, -t, -t) + tap(map, uv, depth, 0, -t) + tap(map, uv, depth, t, -t) + tap(map, uv, depth, -t, 0)
				+ tap(map, uv, depth, 0, 0) + tap(map, uv, depth, t, 0) + tap(map, uv, depth, -t, t) + tap(map, uv, depth, 0, t)
				+ tap(map, uv, depth, t, t)) / 9;
	}
	return result;
}

// 1 where the map's depth at uv + (dx, dy) is not nearer than depth
function tap(map: Texture2D, uv: Vec2, depth: number, dx: number, dy: number): number {
	return step(depth, sampleLevel(map, uv.add(vec2(dx, dy)), 0).x);
}

// the soft filter's lit share (Shadows.soft; PbrShader.hx's softly)
function softly(map: Texture2D, uv: Vec2, depth: number, widest: number, texel: number, soft: Vec4, deep: number, nl: number): number {
	const n = soft.x;
	const slope = deep * min(sqrt(max(1 - nl * nl, 0)) / max(nl, 0.05), 4);
	const cell = fract(floor(uv.div(texel)).div(64)).mul(64);
	const h = fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
	const t = 2 * fract(2 * h) - 1;
	const start = vec2(1 - t * t, 2 * t).mul((h < 0.5 ? 1 : -1) / (1 + t * t));
	const c = -0.7373688;
	const s = 0.6754903;
	let radius = widest;
	let lit = -1.0;
	if (soft.w > 0) {
		const m = max(floor(n * 0.5), 4);
		let dir = start;
		let sum = 0.0;
		let found = 0.0;
		let k = 0.0;
		while (k < m) {
			const at = sqrt((k + 0.5) / m) * widest;
			const d = sampleLevel(map, uv.add(dir.mul(at)), 0).x;
			if (d < depth - (at + texel) * slope) {
				sum += d;
				found += 1;
			}
			dir = vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
			k += 1;
		}
		if (found > 0) radius = clamp((depth - sum / found) * soft.w / max(deep, 0.0001), texel * 1.5, widest);
		else lit = 1;
	}
	if (lit < 0) {
		let dir = start;
		let sum = 0.0;
		let k = 0.0;
		while (k < n) {
			const at = sqrt((k + 0.5) / n) * radius;
			sum += step(depth - (at + texel) * slope, sampleLevel(map, uv.add(dir.mul(at)), 0).x);
			dir = vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
			k += 1;
		}
		lit = sum / n;
	}
	return lit;
}

// how much of the fog lies between the eye and a point (PbrShader.hx's fogAmount)
function fogAmount(fog: Vec4, shape: Vec4, eye: Vec3, at: Vec3): number {
	const d = at.sub(eye);
	const dist = max(length(d), 0.0001);
	const through = max(dist - shape.x, 0);
	const y = eye.y + d.y * min(shape.x / dist, 1);
	const k = clamp(shape.y * d.y / dist * through, -30, 30);
	const mean = abs(k) > 0.0001 ? (1 - exp(-k)) / k : 1 - 0.5 * k;
	const depth = fog.w * exp(clamp(shape.y * (shape.z - y), -30, 30)) * through * mean;
	return min(1 - exp(-depth), shape.w);
}

// a colour in linear light as the target takes it
function output(c: Vec3, hdr: number): Vec3 {
	let result = c;
	if (hdr < 0.5) result = encode(aces(c));
	return result;
}

// ACES filmic tone mapping (Narkowicz's fit), to 0..1
function aces(x: Vec3): Vec3 {
	return clamp(x.mul(x.mul(2.51).add(0.03)).div(x.mul(x.mul(2.43).add(0.59)).add(0.14)), 0, 1);
}

// linear to sRGB
function encode(c: Vec3): Vec3 {
	return pow(c, vec3(1 / 2.2));
}

// joint k's matrix from its row of the texture
function joint(t: Texture2D, k: number, rows: number): Mat4 {
	const y = (k + 0.5) / rows;
	return mat4(vec4(texel(t, 0, y), texel(t, 1, y), texel(t, 2, y), texel(t, 3, y)), vec4(texel(t, 4, y), texel(t, 5, y), texel(t, 6, y), texel(t, 7, y)),
		vec4(texel(t, 8, y), texel(t, 9, y), texel(t, 10, y), texel(t, 11, y)),
		vec4(texel(t, 12, y), texel(t, 13, y), texel(t, 14, y), texel(t, 15, y)));
}

function texel(t: Texture2D, x: number, y: number): number {
	return sampleLevel(t, vec2((x + 0.5) / 16, y), 0).x;
}

// a normal turned to the world by an instance's matrix (its columns): by
// its cofactors, the inverse transpose times the determinant, with the
// determinant's sign (PbrShader.hx's instanceNormal)
function instanceNormal(c0: Vec3, c1: Vec3, c2: Vec3, n: Vec3): Vec3 {
	const x = cross(c1, c2);
	const turned = x.mul(n.x).add(cross(c2, c0).mul(n.y)).add(cross(c0, c1).mul(n.z));
	return dot(c0, x) < 0 ? turned.neg() : turned;
}

export const pbr = slots({
	options: {normalMap: false, skinned: false, instanced: false},
	vertex: (v: PbrVertex, p: PbrVertexParams, m: Pbr): PbrVaryings => {
		let pos = m.position({pos: v.pos, normal: v.normal, uv: v.uv}, p);
		let nr = v.normal;
		if (m.options.skinned) {
			const j0 = joint(p.jointMatrices!, v.joints!.x, p.skin!.rows.x), j1 = joint(p.jointMatrices!, v.joints!.y, p.skin!.rows.x);
			const j2 = joint(p.jointMatrices!, v.joints!.z, p.skin!.rows.x), j3 = joint(p.jointMatrices!, v.joints!.w, p.skin!.rows.x);
			const q = vec4(pos, 1), n4 = vec4(v.normal, 0);
			pos = j0.mul(q).mul(v.weights!.x).add(j1.mul(q).mul(v.weights!.y)).add(j2.mul(q).mul(v.weights!.z)).add(j3.mul(q).mul(v.weights!.w)).xyz;
			nr = j0.mul(n4).mul(v.weights!.x).add(j1.mul(n4).mul(v.weights!.y)).add(j2.mul(n4).mul(v.weights!.z)).add(j3.mul(n4).mul(v.weights!.w)).xyz;
		}
		const model = m.options.instanced ? mat4(vec4(v.m0!.xyz, 0), vec4(v.m1!.xyz, 0), vec4(v.m2!.xyz, 0), v.m3!) : p.object!.model;
		const world = model.mul(vec4(pos, 1));
		return {
			clip: position(p.frame.viewProj.mul(world)),
			world: world.xyz,
			normal: m.options.instanced ? instanceNormal(v.m0!.xyz, v.m1!.xyz, v.m2!.xyz, nr) : p.object!.normalMatrix.mul(vec4(nr, 0)).xyz,
			uv: v.uv,
			tangent: m.options.normalMap ? vec4(model.mul(vec4(v.tangent!.xyz, 0)).xyz, v.tangent!.w) : vec4(0),
			up: m.options.instanced ? v.m1!.xyz : model.mul(vec4(0, 1, 0, 0)).xyz,
			tint: m.options.instanced ? vec3(1 + v.m0!.w, 1 + v.m1!.w, 1 + v.m2!.w) : p.object!.tint.xyz,
		};
	},
	fragment: (i: PbrVaryings, p: PbrFragmentParams, m: Pbr): Vec4 => {
		const ng = normalize(i.normal);
		const uv = uvOf(p.material, i.uv);
		let n = ng;
		if (m.options.normalMap) {
			const t = normalize(i.tangent!.xyz.sub(ng.mul(dot(ng, i.tangent!.xyz))));
			const b = cross(ng, t).mul(i.tangent!.w);
			const mapped = sample(p.normalTexture!, uv).xyz.mul(2).sub(1);
			const scale = p.material.params.z;
			n = normalize(t.mul(mapped.x * scale).add(b.mul(mapped.y * scale)).add(ng.mul(mapped.z)));
		}
		const texel = sample(p.baseColorTexture, uv);
		const s: PbrSurface = {
			world: i.world,
			normal: n,
			uv: uv,
			up: normalize(i.up),
			baseColor: vec4(p.material.baseColor.xyz.mul(pow(texel.xyz, vec3(2.2))), p.material.baseColor.w * texel.w),
		};
		return shade(m.normal(s, p), s.world, uv, s.up, m.color(s, p).mul(i.tint), m.alpha(s, p), m.metalness(s, p), m.roughness(s, p), m.emissive(s, p),
			p.frame, p.material, p.occlusionTexture, p.shadowMap, p.shadowMapFar, p.environmentMap);
	},
	color: pbrColor,
	alpha: pbrAlpha,
	normal: pbrNormal,
	roughness: pbrRoughness,
	metalness: pbrMetalness,
	emissive: pbrEmissive,
	position: pbrPosition,
});
