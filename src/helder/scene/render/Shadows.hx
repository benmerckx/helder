package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.Aabb;
import helder.scene.math.MathTools;
import helder.scene.render.ShadowShader;
import helder.scene.render.ShadowInstancedShader;

// Shadow maps for the directional light, opted in (renderer.use(new
// Shadows(device))): before the frame's pass, every shown mesh drawn from
// the light into size x size R32F targets (the casters of one primitive
// in one instanced draw, their matrices in an instance buffer written once
// for every cascade), which the standard material then reads with a 3x3
// percentage-closer filter, or a soft one (soft: a wider disc of taps,
// sharper where the shadow meets its caster). One cascade: an
// orthographic view fitted to the casters' bounds. Two (Shadows.cascaded,
// whose fitting code a program without it does not link):
// the first fitted to the camera's view up to split metres (its bounding
// sphere, moved by whole texels: steady as the camera moves), sharp near
// the camera, the second the whole scene's, read beyond the first. A
// program that never makes a Shadows links none of this but the
// material's lookup of a 1x1 map that shadows nothing.
class Shadows implements RenderFeature implements RenderFeature.ShadowSource {
	public final device:Device;
	public final size:Int;
	// 1, or 2 (Shadows.cascaded)
	public var cascades(default, null) = 1;
	// how far from the camera the first of two cascades reaches (metres)
	public var split = 10.0;
	// the depth offset against shadow acne (in the whole scene's map's 0..1
	// depth; the first of two cascades', as many of its texels)
	public var bias = 0.004;
	// the shadows' strength, 0 (none) to 1 (no direct light at all)
	public var strength = 0.85;
	// the first cascade's map (one cascade: the only one), the second's
	public final map:Texture;
	public var mapFar(default, null):Texture;
	// the soft filter (soft): the widest penumbra's radius in metres (0: the
	// 3x3 filter), its taps a point (8 for phones, 16, 32), and how much
	// the penumbra widens a metre from its caster (0: the radius
	// everywhere, no blocker search)
	public var softRadius = 0.0;
	public var softSamples = 16;
	public var softSpread = 0.0;
	// the last frame's draws into the maps (every cascade's: a primitive's
	// casters one instanced draw, a skinned caster one draw)
	public var draws(default, null) = 0;

	final depth:Texture;
	// (the casters' pipeline: their matrices from the instance buffer)
	final pipeline:Pipeline;
	final casterBytes = Bytes.alloc(ShadowShader.uniforms[0].size);
	final pass:PassDesc;
	var passFar:PassDesc;
	// the last frame's light view-projections (the first cascade's, the second's)
	public var viewProj(default, null):Mat4 = Mat4.identity();
	public var viewProjFar(default, null):Mat4 = Mat4.identity();
	// (the first of two cascades' bias in its depth)
	var nearBias = 0.004;
	// (the frame's casters, count of them in use, sorted by primitive; the
	// skinned ones and their meshes, drawn alone; the runs of one primitive)
	final casterNodes:Array<Node> = [];
	final casterPrims:Array<Mesh.Primitive> = [];
	var count = 0;
	final skinned:Array<Node> = [];
	final skinnedMeshes:Array<Mesh> = [];
	var skinnedCount = 0;
	final batchStart:Array<Int> = [];
	final batchSize:Array<Int> = [];
	var batchCount = 0;
	var instanceBytes = Bytes.alloc(64 * 64);
	var instanceBuffer:Buffer = Buffer.NONE;
	var instanceCapacity = 0;
	// (the last frame's maps' width and depth in metres: the first's, the second's)
	var nearWidth = 1.0;
	var nearRange = 1.0;
	var farWidth = 1.0;
	var farRange = 1.0;
	// (two cascades: the first's fitting, set by cascaded)
	var fit:Null<(Renderer.FrameInfo, Vec3, Vec3, Vec3, Float) -> Mat4>;

	// one cascade
	public function new(device:Device, size = 1024) {
		this.device = device;
		this.size = size;
		map = device.createTexture({width: size, height: size, format: R32F, renderTarget: true});
		mapFar = map;
		depth = device.createTexture({width: size, height: size, format: Depth32F});
		var d = ShadowInstancedShader.pipeline({cull: None, depthCompare: Less, depthWrite: true});
		d.colorFormat = R32F;
		d.depthFormat = Depth32F;
		d.layout = @:privateAccess Renderer.INSTANCED_LAYOUT;
		pipeline = device.createPipeline(d);
		pass = {colors: [{load: Clear, clear: new Color(1, 1, 1, 1), texture: map}], depth: {load: Clear, texture: depth}};
		passFar = pass;
	}

	// two cascades, the first reaching split metres from the camera
	public static function cascaded(device:Device, size = 1024, split = 10.0):Shadows {
		var s = new Shadows(device, size);
		s.cascades = 2;
		s.split = split;
		s.mapFar = device.createTexture({width: size, height: size, format: R32F, renderTarget: true});
		s.passFar = {colors: [{load: Clear, clear: new Color(1, 1, 1, 1), texture: s.mapFar}], depth: {load: Clear, texture: s.depth}};
		s.fit = s.fitNear;
		return s;
	}

	// the soft filter on (returns the shadows): taps on a disc out to radius
	// metres, samples a point (8: phones; 16; 32), and with a spread a
	// blocker search first, the penumbra growing by spread a metre from its
	// caster up to the radius (contact hardening: PCSS); spread 0, the
	// radius everywhere
	public function soft(radius = 0.1, samples = 16, spread = 0.05):Shadows {
		softRadius = radius;
		softSamples = samples;
		softSpread = spread;
		return this;
	}

	public function attach(renderer:Renderer)
		@:privateAccess renderer.shadowSource = this;

	final frame = new RenderFeature.ShadowFrame();

	public function shadowFrame():RenderFeature.ShadowFrame {
		frame.map = map;
		frame.viewProj = viewProj;
		var on = softRadius > 0 && softSamples > 0;
		frame.params = new Vec4(strength, cascades == 2 ? nearBias : bias, 1 / size, on ? softRadius / nearWidth : 0);
		frame.mapFar = mapFar;
		frame.viewProjFar = viewProjFar;
		frame.paramsFar = cascades == 2 ? new Vec4(strength, bias, 1 / size, on ? softRadius / farWidth : 0) : frame.params;
		frame.soft = on ? new Vec4(softSamples, nearWidth / nearRange, farWidth / farRange, softSpread) : new Vec4(0, 0, 0, 0);
		frame.draws = draws;
		return frame;
	}

	// the maps' passes: the world's shown meshes that cast (Material.castShadows)
	// seen from a light shining along -toLight, the map fitted to them
	public function render(enc:Encoder, world:World, toLight:Vec3, skins:Null<RenderFeature.SkinSource>, view:Renderer.FrameInfo) {
		var meshes = world.store(MeshRenderer.KIND);
		var bounds = Aabb.empty();
		count = 0;
		skinnedCount = 0;
		for (k in 0...meshes.length) {
			var n = meshes.nodeAt(k), mesh = meshes.valueAt(k);
			if (!n.shown() || !world.inTree(n) || !casts(mesh)) continue;
			bounds = bounds.union(mesh.bounds.transform(n.worldMatrix()));
			// (the casters: a skinned node drawn alone, else each casting primitive)
			if (mesh.primitives[0].skinned) {
				if (skinnedCount == skinned.length) {
					skinned.push(n);
					skinnedMeshes.push(mesh);
				} else {
					skinned[skinnedCount] = n;
					skinnedMeshes[skinnedCount] = mesh;
				}
				skinnedCount++;
				continue;
			}
			for (p in mesh.primitives) {
				if (!p.material.castShadows) continue;
				if (count == casterNodes.length) {
					casterNodes.push(n);
					casterPrims.push(p);
				} else {
					casterNodes[count] = n;
					casterPrims[count] = p;
				}
				count++;
			}
		}
		batch();
		// (instanced sets: their bounds when the program gave them)
		var sets = world.store(InstancedMesh.KIND);
		for (k in 0...sets.length) {
			var n = sets.nodeAt(k), s = sets.valueAt(k);
			if (n.shown() && world.inTree(n) && s.count > 0 && s.castShadows && casts(s.mesh)) bounds = bounds.union(s.bounds);
		}
		if (bounds.isEmpty()) bounds = new Aabb(new Vec3(-1, -1, -1), new Vec3(1, 1, 1));
		var c = bounds.center(), e = bounds.size();
		var r = Math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 2 + 0.01;
		// (up: any direction not along the light's)
		var up = Math.abs(toLight.y) > 0.99 ? new Vec3(0, 0, 1) : new Vec3(0, 1, 0);
		var whole = Mat4.orthographic(-r, r, -r, r, r * 0.5, r * 3.5) * MathTools.lookAt(c + toLight * (2 * r), c, up);
		draws = 0;
		// (each map's width and depth in metres: the soft filter's radius in its uv, its slopes)
		farWidth = nearWidth = 2 * r;
		farRange = nearRange = 3 * r;
		if (fit == null || view.camera == null) {
			viewProj = viewProjFar = whole;
			draw(enc, pass, world, skins, viewProj);
			return;
		}
		viewProjFar = whole;
		viewProj = fit(view, toLight, up, c, r);
		draw(enc, pass, world, skins, viewProj);
		draw(enc, passFar, world, skins, viewProjFar);
	}

	// the first cascade: the bounding sphere of the camera's view from its
	// near plane to split, as deep towards the light as the scene (its
	// sphere: centre c, radius r)
	function fitNear(view:Renderer.FrameInfo, toLight:Vec3, up:Vec3, c:Vec3, r:Float):Mat4 {
		var cam = view.camera, inv = MathTools.inverse(view.viewProj);
		var f = Math.min(Math.max((split - cam.near) / (cam.far - cam.near), 0), 1);
		var corners = [];
		for (k in 0...4) {
			var x = (k & 1) == 0 ? -1.0 : 1.0, y = (k & 2) == 0 ? -1.0 : 1.0;
			var a = MathTools.transformPoint(inv, new Vec3(x, y, 0)), b = MathTools.transformPoint(inv, new Vec3(x, y, 1));
			corners.push(a);
			// (along the corner's edge: linear in the view's depth)
			corners.push(a + (b - a) * f);
		}
		var centre = new Vec3(0, 0, 0);
		for (p in corners)
			centre = centre + p * (1 / 8);
		var radius = 0.0;
		for (p in corners) {
			var d = p - centre;
			radius = Math.max(radius, Math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z));
		}
		radius += 0.01;
		// (the centre moved by whole texels in the light's view: shadows do not crawl)
		var lightView = MathTools.lookAt(new Vec3(0, 0, 0), toLight * -1, up);
		var lc = MathTools.transformPoint(lightView, centre), texel = 2 * radius / size;
		lc = new Vec3(Math.floor(lc.x / texel) * texel, Math.floor(lc.y / texel) * texel, lc.z);
		var snapped = MathTools.transformPoint(MathTools.inverse(lightView), lc);
		// (back towards the light past every caster: the scene's sphere)
		var toCentre = c - snapped, back = Math.sqrt(toCentre.x * toCentre.x + toCentre.y * toCentre.y + toCentre.z * toCentre.z) + r;
		// (the bias: as many of this map's texels as the whole map's, in its depth)
		nearBias = bias * (3 * r / (back + radius + r)) * (radius / r);
		nearWidth = 2 * radius;
		nearRange = back + radius + r - 0.01;
		return Mat4.orthographic(-radius, radius, -radius, radius, 0.01, back + radius + r) * MathTools.lookAt(snapped + toLight * back, snapped, up);
	}

	static function casts(m:Mesh):Bool {
		for (p in m.primitives)
			if (p.material.castShadows) return true;
		return false;
	}

	// the casters sorted by primitive (insertion sort: a scene's order
	// changes little from frame to frame), cut into runs of one primitive,
	// their matrices written to the instance buffer before the passes
	function batch() {
		for (i in 1...count) {
			var n = casterNodes[i], p = casterPrims[i], j = i - 1;
			while (j >= 0 && casterPrims[j].id > p.id) {
				casterNodes[j + 1] = casterNodes[j];
				casterPrims[j + 1] = casterPrims[j];
				j--;
			}
			casterNodes[j + 1] = n;
			casterPrims[j + 1] = p;
		}
		batchCount = 0;
		if (count * 64 > instanceBytes.length) instanceBytes = Bytes.alloc(Std.int(Math.max(instanceBytes.length * 2, count * 64)));
		var i = 0, bytes = 0;
		while (i < count) {
			var j = i + 1;
			while (j < count && casterPrims[j] == casterPrims[i])
				j++;
			if (batchCount == batchStart.length) {
				batchStart.push(0);
				batchSize.push(0);
			}
			batchStart[batchCount] = i;
			batchSize[batchCount] = j - i;
			batchCount++;
			i = j;
		}
		for (k in 0...count) {
			var m = casterNodes[k].worldMatrix();
			for (c in 0...4) {
				var col = MathTools.col(m, c);
				instanceBytes.setFloat(bytes, col.x);
				instanceBytes.setFloat(bytes + 4, col.y);
				instanceBytes.setFloat(bytes + 8, col.z);
				instanceBytes.setFloat(bytes + 12, c == 3 ? 1 : 0);
				bytes += 16;
			}
		}
		if (bytes > 0) {
			if (bytes > instanceCapacity) {
				if (instanceCapacity > 0) device.destroyBuffer(instanceBuffer);
				instanceCapacity = instanceBytes.length;
				instanceBuffer = device.createBuffer({size: instanceCapacity, usage: Vertex});
			}
			device.writeBuffer(instanceBuffer, 0, instanceBytes, 0, bytes);
		}
	}

	function draw(enc:Encoder, pass:PassDesc, world:World, skins:Null<RenderFeature.SkinSource>, viewProj:Mat4) {
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		ShadowShader.params.caster.write({mvp: viewProj}, casterBytes);
		enc.setUniforms(ShadowInstancedShader.uniforms[0].binding, casterBytes);
		for (b in 0...batchCount) {
			var p = casterPrims[batchStart[b]];
			enc.setVertexBuffer(0, p.vertices);
			enc.setVertexBuffer(1, instanceBuffer, batchStart[b] * 64);
			enc.setIndexBuffer(p.indices, p.indexFormat);
			enc.drawIndexed(p.count, batchSize[b]);
			draws++;
		}
		drawSets(enc, world);
		// (a skinned mesh: drawn by the skinning's shadow pipeline, its joints bound)
		if (skins != null && skinnedCount > 0) {
			enc.setPipeline(skins.shadowPipeline());
			var slots = skins.shadowSlots();
			for (k in 0...skinnedCount) {
				var n = skinned[k];
				ShadowShader.params.caster.write({mvp: viewProj * n.worldMatrix()}, casterBytes);
				enc.setUniforms(slots[0], casterBytes);
				skins.bind(enc, slots, n);
				for (p in skinnedMeshes[k].primitives) {
					if (!p.material.castShadows) continue;
					enc.setVertexBuffer(0, p.vertices);
					enc.setIndexBuffer(p.indices, p.indexFormat);
					enc.drawIndexed(p.count);
					draws++;
				}
			}
		}
		enc.endPass();
	}

	// the instanced sets that cast, each primitive one instanced draw (the
	// casters' pipeline and block bound)
	function drawSets(enc:Encoder, world:World) {
		var sets = world.store(InstancedMesh.KIND);
		for (k in 0...sets.length) {
			var n = sets.nodeAt(k), s = sets.valueAt(k);
			if (!n.shown() || !world.inTree(n) || s.count == 0 || !s.castShadows || s.buffer == Buffer.NONE) continue;
			for (p in s.mesh.primitives) {
				if (!p.material.castShadows || p.skinned) continue;
				enc.setVertexBuffer(0, p.vertices);
				enc.setVertexBuffer(1, s.buffer);
				enc.setIndexBuffer(p.indices, p.indexFormat);
				enc.drawIndexed(p.count, s.count);
				draws++;
			}
		}
	}

	public function dispose() {
		if (instanceCapacity > 0) device.destroyBuffer(instanceBuffer);
		instanceCapacity = 0;
		device.destroyTexture(map);
		if (mapFar != map) device.destroyTexture(mapFar);
		device.destroyTexture(depth);
	}
}
