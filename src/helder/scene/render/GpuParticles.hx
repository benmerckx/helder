package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.math.MathTools;
import helder.scene.render.GpuParticleShader;

// Particles moved on the GPU (renderer.use(new GpuParticles(device))):
// emit writes a particle once, into a ring of capacity particles (the
// oldest written over when it is full), and GpuParticleShader moves it
// from then on, from the clock's time (time, which the program sets or
// advance moves): nothing is simulated or allocated a frame, the frame
// uploads only the particles emitted since the last (one or two runs of
// the ring) and draws the ring in one instanced draw at AfterOpaque,
// added to the scene. drag slows every particle (per second), gravity
// pulls them. For sparks, debris, exhaust trails, smoke and flashes:
//
//   var fx = new GpuParticles(device, 8192);
//   renderer.use(fx);
//   fx.advance(dt);
//   fx.emit(x, y, z, vx, vy, vz, 2, 1.2, 0.5, 1, 0.3, 0.05, 0.6, 0.02, 1);
class GpuParticles implements RenderFeature {
	public static inline var STRIDE = 64;

	public final capacity:Int;
	// the clock, in seconds
	public var time = 0.0;
	// how fast the particles slow (per second: their speed times e^(-drag t))
	public var drag = 0.0;
	public var gravity = new Vec3(0, 0, 0);
	// whether the ring is drawn
	public var visible = true;

	final device:Device;
	final staging:Bytes;
	final ring:Buffer;
	final quad:Buffer;
	final indices:Buffer;
	final viewBytes = Bytes.alloc(GpuParticleShader.uniforms[0].size);
	var pipeline:Pipeline = cast 0;
	// the next slot written, and the run written since the last upload (from, count)
	var next = 0;
	var dirtyFrom = 0;
	var dirtyCount = 0;
	// (the last particle's death: nothing drawn once the ring is all past it)
	var lastDeath = -1.0;

	static final LAYOUT:Array<VertexBufferLayout> = [
		{stride: 8, attributes: [{location: 0, format: Float2, offset: 0}]},
		{
			stride: STRIDE,
			step: Instance,
			attributes: [
				{location: 1, format: Float4, offset: 0}, {location: 2, format: Float4, offset: 16}, {location: 3, format: Float4, offset: 32},
				{location: 4, format: Float4, offset: 48}
			]
		}
	];

	public function new(device:Device, capacity = 4096) {
		this.device = device;
		this.capacity = capacity;
		staging = Bytes.alloc(capacity * STRIDE);
		// (every slot born never: a birth far in the future draws nothing)
		for (k in 0...capacity)
			staging.setFloat(k * STRIDE + 12, 1e9);
		ring = device.createBuffer({size: staging.length, usage: Vertex, data: staging});
		var q = Bytes.alloc(32);
		var c = [-1.0, -1, 1, -1, 1, 1, -1, 1];
		for (k in 0...8)
			q.setFloat(4 * k, c[k]);
		quad = device.createBuffer({size: 32, usage: Vertex, data: q});
		var ib = Bytes.alloc(12);
		var idx = [0, 1, 2, 0, 2, 3];
		for (k in 0...6)
			ib.setUInt16(2 * k, idx[k]);
		indices = device.createBuffer({size: 12, usage: Index, data: ib});
	}

	public function attach(renderer:Renderer) {
		var d = GpuParticleShader.pipeline({blend: Premultiplied, depthCompare: Less, depthWrite: false});
		d.layout = LAYOUT;
		pipeline = renderer.createPipeline(d);
		renderer.inject(AfterOpaque, (enc, frame) -> draw(enc, frame));
	}

	public inline function advance(dt:Float)
		time += dt;

	// a particle at x, y, z moving at vx, vy, vz (units a second), of a
	// linear colour r, g, b and opacity a, its size (half its side) from
	// size0 to size1 over life seconds; stretch: drawn as a streak of that
	// many seconds of its path; heat: whiter and brighter while young (0 to 1)
	public function emit(x:Float, y:Float, z:Float, vx:Float, vy:Float, vz:Float, r:Float, g:Float, b:Float, a:Float, size0:Float, size1:Float,
			life:Float, stretch = 0.0, heat = 0.0, delay = 0.0) {
		var o = next * STRIDE, s = staging;
		s.setFloat(o, x);
		s.setFloat(o + 4, y);
		s.setFloat(o + 8, z);
		s.setFloat(o + 12, time + delay);
		s.setFloat(o + 16, vx);
		s.setFloat(o + 20, vy);
		s.setFloat(o + 24, vz);
		s.setFloat(o + 28, life);
		s.setFloat(o + 32, r);
		s.setFloat(o + 36, g);
		s.setFloat(o + 40, b);
		s.setFloat(o + 44, a);
		s.setFloat(o + 48, size0);
		s.setFloat(o + 52, size1);
		s.setFloat(o + 56, stretch);
		s.setFloat(o + 60, heat);
		if (dirtyCount == 0) dirtyFrom = next;
		if (dirtyCount < capacity) dirtyCount++;
		next = (next + 1) % capacity;
		if (time + delay + life > lastDeath) lastDeath = time + delay + life;
	}

	// how many were emitted since the last frame's upload
	public var pending(get, never):Int;

	inline function get_pending()
		return dirtyCount;

	function upload() {
		if (dirtyCount == 0) return;
		var end = dirtyFrom + dirtyCount;
		if (end <= capacity) device.writeBuffer(ring, dirtyFrom * STRIDE, staging, dirtyFrom * STRIDE, dirtyCount * STRIDE);
		else {
			device.writeBuffer(ring, dirtyFrom * STRIDE, staging, dirtyFrom * STRIDE, (capacity - dirtyFrom) * STRIDE);
			device.writeBuffer(ring, 0, staging, 0, (end - capacity) * STRIDE);
		}
		dirtyCount = 0;
	}

	function draw(enc:Encoder, frame:Renderer.FrameInfo) {
		// (gfx writes buffers at once, ahead of the frame's commands: the
		// emitted particles are there for this frame's draw)
		upload();
		if (!visible || time > lastDeath || frame.camera == null) return;
		var m = frame.camera.node.worldMatrix();
		var right = MathTools.transformDir(m, new Vec3(1, 0, 0)), up = MathTools.transformDir(m, new Vec3(0, 1, 0)),
			forward = MathTools.transformDir(m, new Vec3(0, 0, -1));
		GpuParticleShader.writeGpuParticleView({
			viewProj: frame.viewProj,
			right: new Vec4(right.x, right.y, right.z, frame.hdr ? 1 : 0),
			up: new Vec4(up.x, up.y, up.z, time),
			forward: new Vec4(forward.x, forward.y, forward.z, drag),
			gravity: new Vec4(gravity.x, gravity.y, gravity.z, 0)
		}, viewBytes);
		enc.setPipeline(pipeline);
		enc.setUniforms(GpuParticleShader.uniforms[0].binding, viewBytes);
		enc.setVertexBuffer(0, quad);
		enc.setVertexBuffer(1, ring);
		enc.setIndexBuffer(indices, UInt16);
		enc.drawIndexed(6, capacity);
	}

	public function dispose() {
		device.destroyBuffer(ring);
		device.destroyBuffer(quad);
		device.destroyBuffer(indices);
	}
}
