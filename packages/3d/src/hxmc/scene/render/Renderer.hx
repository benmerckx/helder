package hxmc.scene.render;

import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.Mat4;
import hxmc.gfx.shader.Vec3;
import hxmc.gfx.shader.Vec4;
import hxmc.scene.Camera;
import hxmc.scene.Node;
import hxmc.scene.Scene;
import hxmc.scene.math.MathTools;
import hxmc.scene.render.PbrShader;

// Draws a scene's meshes (nodes whose mesh is a Mesh) as seen by a camera,
// lit by one directional light (sun, from the light's direction) and an
// ambient from the sky and the ground, with PbrShader: one pass into the
// frame (or a target), depth-tested, each primitive a draw with its
// node's matrices and its material in uniform blocks (gfx's uniform ring:
// nothing allocated per frame). Meshes
// outside the camera's view are skipped (their bounds against the view's
// clip space).
//
// It is ordinary gfx code: draw records its pass into the caller's
// encoder, so a program adds its own passes before or after.
class Renderer {
	public final device:Device;
	// towards the light (normalized when drawn), and its colour times intensity
	public var sunDirection = new Vec3(-0.4, 0.8, 0.45);
	public var sunColor = new Vec3(2.1, 1.95, 1.8);
	public var sky = new Vec3(0.3, 0.36, 0.48);
	public var ground = new Vec3(0.12, 0.1, 0.09);
	public var exposure = 1.0;
	public var clearColor = new Color(0.07, 0.08, 0.1);
	// draws and primitives culled by the last draw (statistics)
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

	// records the frame's pass: scene seen by camera (aspect: the target's, by default the device's)
	public function draw(enc:Encoder, scene:Scene, camera:Camera, ?aspect:Float) {
		if (aspect == null) aspect = device.width / device.height;
		var viewProj = camera.viewProjection(aspect);
		var eye = camera.eye();
		var l = sunDirection / Math.sqrt(sunDirection.x * sunDirection.x + sunDirection.y * sunDirection.y + sunDirection.z * sunDirection.z);
		PbrShader.writePbrFrame({
			viewProj: viewProj,
			eye: new Vec4(eye.x, eye.y, eye.z, 1),
			lightDir: new Vec4(l.x, l.y, l.z, 0),
			lightColor: new Vec4(sunColor.x, sunColor.y, sunColor.z, 0),
			sky: new Vec4(sky.x, sky.y, sky.z, 0),
			ground: new Vec4(ground.x, ground.y, ground.z, 0),
			exposure: new Vec4(exposure, 0, 0, 0)
		}, frameBytes);
		pass.colors[0].clear = clearColor;
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setUniforms(0, frameBytes);
		draws = culled = 0;
		this.viewProj = viewProj;
		current = pipeline;
		drawNode(enc, scene);
		enc.endPass();
	}

	// (the walk: methods, not a closure, which could not capture struct values)
	var viewProj:Mat4 = Mat4.identity();
	var current:Pipeline;

	function drawNode(enc:Encoder, node:Node) {
		if (!node.visible) return;
		if (Std.isOfType(node.mesh, Mesh)) drawMesh(enc, node, cast node.mesh);
		for (c in node.children)
			drawNode(enc, c);
	}

	function drawMesh(enc:Encoder, node:Node, mesh:Mesh) {
		var model = node.world();
		if (!visible(viewProj * model, mesh)) {
			culled += mesh.primitives.length;
			return;
		}
		PbrShader.writePbrObject({model: model, normalMatrix: MathTools.normalMatrix(model)}, objectBytes);
		enc.setUniforms(1, objectBytes);
		for (p in mesh.primitives) {
			var m = p.material;
			var want = m.doubleSided ? doubleSided : pipeline;
			if (want != current) {
				enc.setPipeline(want);
				// (the pipeline changed: its blocks set again)
				enc.setUniforms(0, frameBytes);
				enc.setUniforms(1, objectBytes);
				current = want;
			}
			PbrShader.writePbrMaterial({
				baseColor: m.baseColor,
				params: new Vec4(m.metallic, m.roughness, 0, 0),
				emissive: new Vec4(m.emissive.x, m.emissive.y, m.emissive.z, 0)
			}, materialBytes);
			enc.setUniforms(2, materialBytes);
			enc.setTexture(3, m.baseColorTexture != null ? m.baseColorTexture : white, sampler);
			enc.setVertexBuffer(0, p.vertices);
			enc.setIndexBuffer(p.indices, p.indexFormat);
			enc.drawIndexed(p.count);
			draws++;
		}
	}

	// whether a mesh's bounds, through mvp, reach the view: not all eight
	// corners beyond one of the clip space's planes
	static function visible(mvp:Mat4, mesh:Mesh):Bool {
		var b = mesh.bounds;
		if (b.isEmpty()) return false;
		var out = [0, 0, 0, 0, 0, 0];
		for (k in 0...8) {
			var c = mvp * new Vec4((k & 1) == 0 ? b.min.x : b.max.x, (k & 2) == 0 ? b.min.y : b.max.y, (k & 4) == 0 ? b.min.z : b.max.z, 1);
			if (c.x < -c.w) out[0]++;
			if (c.x > c.w) out[1]++;
			if (c.y < -c.w) out[2]++;
			if (c.y > c.w) out[3]++;
			if (c.z < 0) out[4]++;
			if (c.z > c.w) out[5]++;
		}
		for (o in out)
			if (o == 8) return false;
		return true;
	}

	public function dispose() {
		device.destroyTexture(white);
	}
}
