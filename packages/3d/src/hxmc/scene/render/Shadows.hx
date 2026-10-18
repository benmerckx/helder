package hxmc.scene.render;

import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.Mat4;
import hxmc.gfx.shader.Vec3;
import hxmc.gfx.shader.Vec4;
import hxmc.scene.World;
import hxmc.scene.math.Aabb;
import hxmc.scene.math.MathTools;
import hxmc.scene.render.ShadowShader;

// A shadow map for the directional light, opted in (renderer.use(new
// Shadows(device))): before the frame's pass, every shown mesh drawn from
// the light into a size x size R32F target (an orthographic view fitted
// to the casters' bounds), which the standard material then reads with a
// 3x3 percentage-closer filter. One map (cascades later); a program that
// never makes a Shadows links none of this but the material's lookup of a
// 1x1 map that shadows nothing.
class Shadows {
	public final device:Device;
	public final size:Int;
	// the depth offset against shadow acne (in the map's 0..1 depth)
	public var bias = 0.004;
	// the shadows' strength, 0 (none) to 1 (no direct light at all)
	public var strength = 0.85;
	public final map:Texture;

	final depth:Texture;
	final pipeline:Pipeline;
	final casterBytes = Bytes.alloc(ShadowShader.uniforms[0].size);
	final pass:PassDesc;
	// the last frame's light view-projection
	public var viewProj(default, null):Mat4 = Mat4.identity();

	public function new(device:Device, size = 1024) {
		this.device = device;
		this.size = size;
		map = device.createTexture({width: size, height: size, format: R32F, renderTarget: true});
		depth = device.createTexture({width: size, height: size, format: Depth32F});
		var d = ShadowShader.pipeline({cull: None, depthCompare: Less, depthWrite: true});
		d.colorFormat = R32F;
		d.depthFormat = Depth32F;
		pipeline = device.createPipeline(d);
		pass = {colors: [{load: Clear, clear: new Color(1, 1, 1, 1), texture: map}], depth: {load: Clear, texture: depth}};
	}

	// the map's pass: the world's shown meshes seen from a light shining along -toLight
	@:allow(hxmc.scene.render.Renderer) function render(enc:Encoder, world:World, toLight:Vec3) {
		var meshes = world.store(MeshRenderer.KIND);
		var bounds = Aabb.empty();
		for (k in 0...meshes.length) {
			var n = meshes.nodeAt(k);
			if (n.shown() && world.inTree(n)) bounds = bounds.union(meshes.valueAt(k).bounds.transform(n.worldMatrix()));
		}
		if (bounds.isEmpty()) bounds = new Aabb(new Vec3(-1, -1, -1), new Vec3(1, 1, 1));
		var c = bounds.center(), e = bounds.size();
		var r = Math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 2 + 0.01;
		// (up: any direction not along the light's)
		var up = Math.abs(toLight.y) > 0.99 ? new Vec3(0, 0, 1) : new Vec3(0, 1, 0);
		var view = MathTools.lookAt(c + toLight * (2 * r), c, up);
		viewProj = Mat4.orthographic(-r, r, -r, r, r * 0.5, r * 3.5) * view;
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		for (k in 0...meshes.length) {
			var n = meshes.nodeAt(k);
			if (!n.shown() || !world.inTree(n)) continue;
			ShadowShader.writeShadowCaster({mvp: viewProj * n.worldMatrix()}, casterBytes);
			enc.setUniforms(0, casterBytes);
			for (p in meshes.valueAt(k).primitives) {
				enc.setVertexBuffer(0, p.vertices);
				enc.setIndexBuffer(p.indices, p.indexFormat);
				enc.drawIndexed(p.count);
			}
		}
		enc.endPass();
	}

	public function dispose() {
		device.destroyTexture(map);
		device.destroyTexture(depth);
	}
}
