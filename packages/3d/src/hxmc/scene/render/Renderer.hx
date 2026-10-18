package hxmc.scene.render;

import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.Mat4;
import hxmc.gfx.shader.Vec3;
import hxmc.gfx.shader.Vec4;
import hxmc.scene.Camera;
import hxmc.scene.Node;
import hxmc.scene.World;
import hxmc.scene.math.MathTools;
import hxmc.scene.render.PbrShader;

// Draws a world's meshes (MeshRenderer) as seen by a camera, lit by its
// first directional Light (else the renderer's sun) and an ambient from
// the sky and the ground, with PbrShader. Two stages:
//
//   extract   the world's meshes into a flat draw list: the nodes shown,
//             their bounds inside the camera's view, a draw per primitive
//             sorted by pipeline and material (the seam for instancing,
//             threads and GPU culling later)
//   record    the list as one depth-tested pass into the caller's encoder,
//             each draw's matrices and material in uniform blocks through
//             gfx's uniform ring (nothing allocated per frame: the list's
//             entries are kept)
//
// It is ordinary gfx code: draw records into the caller's encoder, so a
// program adds its own passes before or after; each camera of a world
// (split screens, XR's eyes) is a draw of its own.
class Renderer {
	public final device:Device;
	// without a Light in the world: towards the light (normalized when
	// drawn), and its colour times intensity
	public var sunDirection = new Vec3(-0.4, 0.8, 0.45);
	public var sunColor = new Vec3(2.1, 1.95, 1.8);
	public var sky = new Vec3(0.3, 0.36, 0.48);
	public var ground = new Vec3(0.12, 0.1, 0.09);
	public var exposure = 1.0;
	public var clearColor = new Color(0.07, 0.08, 0.1);
	// the last draw's draws and primitives culled (statistics)
	public var draws(default, null) = 0;
	public var culled(default, null) = 0;

	final pipeline:Pipeline;
	final doubleSided:Pipeline;
	final white:Texture;
	final sampler:Sampler;
	final frameBytes = Bytes.alloc(PbrShader.uniforms[0].size);
	final objectBytes = Bytes.alloc(PbrShader.uniforms[1].size);
	final materialBytes = Bytes.alloc(PbrShader.uniforms[2].size);
	final pass:PassDesc;
	// the draw list: entries kept between frames, count of them in use
	final list:Array<DrawItem> = [];
	var count = 0;

	public function new(device:Device) {
		this.device = device;
		pipeline = device.createPipeline(PbrShader.pipeline({cull: Back, depthCompare: Less, depthWrite: true}));
		doubleSided = device.createPipeline(PbrShader.pipeline({cull: None, depthCompare: Less, depthWrite: true}));
		var w = Bytes.alloc(4);
		w.fill(0, 4, 255);
		white = device.createTexture({width: 1, height: 1, data: w});
		sampler = device.createSampler({filter: Linear, wrap: Repeat});
		pass = {colors: [{load: Clear, clear: clearColor}], depth: {load: Clear}};
	}

	// records the frame's pass: world seen by camera (aspect: the target's,
	// by default the device's)
	public function draw(enc:Encoder, world:World, camera:Camera, ?aspect:Float) {
		if (aspect == null) aspect = device.width / device.height;
		var viewProj = camera.viewProjection(aspect);
		extract(world, viewProj);
		writeFrame(world, camera, viewProj);
		record(enc);
	}

	// the draw list: each shown mesh inside the view, a draw per primitive, sorted
	public function extract(world:World, viewProj:Mat4) {
		count = 0;
		culled = 0;
		var meshes = world.store(MeshRenderer.KIND);
		for (k in 0...meshes.length) {
			var node = meshes.nodeAt(k), mesh = meshes.valueAt(k);
			if (!node.shown() || !world.inTree(node)) continue;
			var model = node.worldMatrix();
			if (!visible(viewProj * model, mesh)) {
				culled += mesh.primitives.length;
				continue;
			}
			for (p in mesh.primitives) {
				if (count == list.length) list.push(new DrawItem());
				var d = list[count++];
				d.node = node;
				d.primitive = p;
				// (the pipeline, then the material)
				d.key = (p.material.doubleSided ? 1 << 24 : 0) | (p.material.id & 0xFFFFFF);
			}
		}
		// (insertion sort: a scene's order changes little from frame to frame)
		for (i in 1...count) {
			var d = list[i], j = i - 1;
			while (j >= 0 && list[j].key > d.key) {
				list[j + 1] = list[j];
				j--;
			}
			list[j + 1] = d;
		}
	}

	function writeFrame(world:World, camera:Camera, viewProj:Mat4) {
		var eye = camera.eye();
		var l = sunDirection, c = sunColor;
		var lights = world.store(Light.KIND);
		for (k in 0...lights.length)
			if (lights.nodeAt(k).shown()) {
				var light = lights.valueAt(k);
				// (it shines down its node's -z: the light is towards +z)
				l = MathTools.transformDir(lights.nodeAt(k).worldMatrix(), new Vec3(0, 0, 1));
				c = light.color * light.intensity;
				break;
			}
		l = l / Math.sqrt(l.x * l.x + l.y * l.y + l.z * l.z);
		PbrShader.writePbrFrame({
			viewProj: viewProj,
			eye: new Vec4(eye.x, eye.y, eye.z, 1),
			lightDir: new Vec4(l.x, l.y, l.z, 0),
			lightColor: new Vec4(c.x, c.y, c.z, 0),
			sky: new Vec4(sky.x, sky.y, sky.z, 0),
			ground: new Vec4(ground.x, ground.y, ground.z, 0),
			exposure: new Vec4(exposure, 0, 0, 0)
		}, frameBytes);
	}

	function record(enc:Encoder) {
		pass.colors[0].clear = clearColor;
		enc.beginPass(pass);
		var current:Null<Pipeline> = null, material:Null<Material> = null, node = Node.NONE;
		draws = 0;
		for (i in 0...count) {
			var d = list[i], p = d.primitive, m = p.material;
			var want = m.doubleSided ? doubleSided : pipeline;
			if (want != current) {
				enc.setPipeline(want);
				enc.setUniforms(0, frameBytes);
				current = want;
				material = null;
				node = Node.NONE;
			}
			if (d.node != node) {
				var model = d.node.worldMatrix();
				PbrShader.writePbrObject({model: model, normalMatrix: MathTools.normalMatrix(model)}, objectBytes);
				enc.setUniforms(1, objectBytes);
				node = d.node;
			}
			if (m != material) {
				PbrShader.writePbrMaterial({
					baseColor: m.baseColor,
					params: new Vec4(m.metallic, m.roughness, 0, 0),
					emissive: new Vec4(m.emissive.x, m.emissive.y, m.emissive.z, 0)
				}, materialBytes);
				enc.setUniforms(2, materialBytes);
				enc.setTexture(3, m.baseColorTexture != null ? m.baseColorTexture : white, sampler);
				material = m;
			}
			enc.setVertexBuffer(0, p.vertices);
			enc.setIndexBuffer(p.indices, p.indexFormat);
			enc.drawIndexed(p.count);
			draws++;
		}
		enc.endPass();
	}

	// whether a mesh's bounds, through mvp, reach the view: not all eight
	// corners beyond one of the clip space's planes
	static function visible(mvp:Mat4, mesh:Mesh):Bool {
		var b = mesh.bounds;
		if (b.isEmpty()) return false;
		var o0 = 0, o1 = 0, o2 = 0, o3 = 0, o4 = 0, o5 = 0;
		for (k in 0...8) {
			var c = mvp * new Vec4((k & 1) == 0 ? b.min.x : b.max.x, (k & 2) == 0 ? b.min.y : b.max.y, (k & 4) == 0 ? b.min.z : b.max.z, 1);
			if (c.x < -c.w) o0++;
			if (c.x > c.w) o1++;
			if (c.y < -c.w) o2++;
			if (c.y > c.w) o3++;
			if (c.z < 0) o4++;
			if (c.z > c.w) o5++;
		}
		return o0 < 8 && o1 < 8 && o2 < 8 && o3 < 8 && o4 < 8 && o5 < 8;
	}

	public function dispose() {
		device.destroyTexture(white);
	}
}

// an entry of the draw list
class DrawItem {
	public var node:Node = Node.NONE;
	public var primitive:Null<Mesh.Primitive>;
	public var key = 0;

	public function new() {}
}
