import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.math.Quat;
import helder.scene.render.Renderer;

// The cloud sea: one continuous bank far below the islands, soft cumulus
// billboards facing the camera (a cloud's texture: lumpy lit tops, a flat
// shaded base, its edges thin), lit by the island's colours (a lit top, a
// shade darker toward the bottom) and hazed toward the sky's lowest colour
// with distance, fading out by FAR, so its contrast falls toward the
// horizon and the sky stays above it. It lies 9 metres and more below the hole, under every island's
// underside: a sight line from the camera to the hole never reaches it, so
// no cloud comes between them; one nearer the camera than 14 metres fades
// out. Its puffs drift slowly (wrapping round a square, faded out at the
// bank's rim, so none pops).
//
// Its own draw, not a material's: a renderer hook (AfterOpaque: after the
// opaque surfaces, before the see-through ones, so water is drawn over
// it), one draw of the bank's quads sorted far to near, premultiplied,
// depth-tested, a shader of a texture tap and two mixes (cheap on a phone,
// however much of the frame it covers). The quads are written on the CPU
// each frame into bytes made once (no allocation), one writeBuffer.
@:structInit @:publicFields class CloudVertex {
	var pos:Vec3;
	var uv:Vec2;
	var look:Vec2; // x: haze (0 near, toward the sky's colour far), y: alpha
}

@:structInit @:publicFields class CloudVaryings {
	var clip:Vec4;
	var uv:Vec2;
	var look:Vec2;
}

@:structInit @:publicFields class CloudView {
	var viewProj:Mat4;
	var top:Vec4; // rgb: the lit tops' colour (linear, exposed)
	var bottom:Vec4; // rgb: the shaded base's
	var haze:Vec4; // rgb: the sky's lowest colour, the far bank's
}

final CloudShader = shader({
	vertex: function(v:CloudVertex, p:{view:CloudView}):CloudVaryings
		return {clip: position(p.view.viewProj * vec4(v.pos, 1)), uv: v.uv, look: v.look},
	// cloud: r its light (1 a lit top, 0 its base), a its density
	fragment: function(i:CloudVaryings, p:{view:CloudView, cloud:Texture2D}):Vec4 {
		var t = sample(p.cloud, i.uv);
		var c = mix(p.view.bottom.xyz, p.view.top.xyz, t.x);
		c = mix(c, p.view.haze.xyz, i.look.x);
		var a = t.w * i.look.y;
		return vec4(c * a, a);
	}
});

class Clouds {
	// the puffs there may be, and drawn at each quality (2, 1, 0)
	public static inline var MAX = 140;
	static final COUNTS = [60, 96, MAX];
	// the bank: its puffs' spread round the hole (metres), how far below it
	static inline var SPREAD = 38.0;
	static inline var DEPTH = 9.5;
	// how far off it fades out (metres from the camera): the frame's upper part, farther, left to the sky
	static inline var FAR = 30.0;
	// floats a vertex, vertices a puff
	static inline var FLOATS = 7;
	static inline var VERTICES = 6;

	public var count(default, null) = MAX;
	final device:Device;
	final pipeline:Pipeline;
	final texture:Texture;
	final sampler:Sampler;
	final buffer:Buffer;
	final bytes:Bytes;
	final viewBytes = Bytes.alloc(CloudShader.uniforms[0].size);
	final viewSlot:Int;
	final textureSlot:Int;
	// per puff: x, z on the square (-1..1), its height's offset, its width, its variant (0..3: texture half, mirrored)
	final puffs:Array<Float> = [];
	// (far to near: the order drawn; each puff's distance from the camera)
	final order:Array<Int> = [];
	final distance:Array<Float> = [];
	var drawn = 0;
	// the hole: its middle, its lowest point
	var cx = 0.0;
	var cz = 0.0;
	var cy = 0.0;
	var top = new Vec3(1, 1, 1);
	var bottom = new Vec3(0.7, 0.7, 0.8);
	var haze = new Vec3(1, 1, 1);
	public var visible = true;

	public function new(r:Renderer) {
		device = r.device;
		pipeline = r.createPipeline(CloudShader.pipeline({blend: Premultiplied, cull: None, depthCompare: Less, depthWrite: false}));
		texture = cloudTexture(device);
		sampler = device.createSampler({filter: Linear, wrap: Clamp});
		bytes = Bytes.alloc(MAX * VERTICES * FLOATS * 4);
		buffer = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		viewSlot = CloudShader.uniforms[0].binding;
		textureSlot = CloudShader.textures[0].binding;
		// (a jittered grid over the square, the same on every run)
		var n = Std.int(Math.sqrt(MAX)) + 1, k = 0;
		for (j in 0...n)
			for (i in 0...n) {
				if (k >= MAX) break;
				var h = k * 7;
				puffs.push(((i + 0.5 + (hash(h) - 0.5) * 0.9) / n) * 2 - 1);
				puffs.push(((j + 0.5 + (hash(h + 1) - 0.5) * 0.9) / n) * 2 - 1);
				puffs.push(hash(h + 2) * 1.2);
				puffs.push(6.5 + hash(h + 3) * 5);
				puffs.push(Std.int(hash(h + 4) * 4));
				order.push(k);
				distance.push(0);
				k++;
			}
		r.inject(AfterOpaque, (enc, frame) -> draw(enc, frame));
	}

	static function hash(i:Int):Float {
		var x = Math.sin(i * 12.9898 + 78.233) * 43758.5453;
		return x - Math.floor(x);
	}

	public function quality(level:Int)
		count = COUNTS[Std.int(Math.max(0, Math.min(2, level)))];

	// the hole the bank lies under, and the island's colours (sRGB hex): its
	// clouds' lit top and shaded base, the sky's lowest colour; bright: the
	// light they are drawn with
	public function place(x:Float, z:Float, lowest:Float, lit:Int, shade:Int, sky:Int, bright:Float) {
		cx = x;
		cz = z;
		cy = lowest - DEPTH;
		top = Kit.rgb3(lit, bright);
		bottom = Kit.rgb3(shade, bright);
		haze = Kit.rgb3(sky, bright);
	}

	// the frame's quads: facing the camera at eye (rotation turn), drifting with time, far to near
	public function update(time:Float, eye:Vec3, turn:Quat) {
		var right = turn.rotate(new Vec3(1, 0, 0)), up = turn.rotate(new Vec3(0, 1, 0));
		var n = Std.int(Math.min(count, order.length));
		// (each puff's place now and its distance: the order's key)
		for (k in 0...order.length) {
			var o = k * 5;
			var x = cx + wrap(puffs[o] + time * 0.0035) * SPREAD, z = cz + wrap(puffs[o + 1] + time * 0.0015) * SPREAD;
			var dx = x - eye.x, dy = cy + puffs[o + 2] - eye.y, dz = z - eye.z;
			distance[k] = Math.sqrt(dx * dx + dy * dy + dz * dz);
		}
		// (insertion sort, far first: nearly sorted from the last frame, a few swaps)
		for (i in 1...order.length) {
			var v = order[i], d = distance[v], j = i - 1;
			while (j >= 0 && distance[order[j]] < d) {
				order[j + 1] = order[j];
				j--;
			}
			order[j + 1] = v;
		}
		var w = 0;
		drawn = 0;
		for (i in 0...order.length) {
			var k = order[i];
			// (a thinner bank: puffs dropped all over it, by a fixed hash, not a region)
			if (n < MAX && hash(k * 7 + 5) * MAX >= n) continue;
			var o = k * 5;
			var sx = wrap(puffs[o] + time * 0.0035), sz = wrap(puffs[o + 1] + time * 0.0015);
			var x = cx + sx * SPREAD, y = cy + puffs[o + 2], z = cz + sz * SPREAD;
			var d = distance[k];
			// (faded: near the camera, far off, at the bank's rim)
			var rim = Math.sqrt(sx * sx + sz * sz);
			var a = smooth(14, 20, d) * (1 - smooth(FAR * 0.65, FAR, d)) * (1 - smooth(0.72, 1.0, rim));
			if (a <= 0.003) continue;
			var hz = 0.1 + 0.75 * smooth(15, FAR, d);
			var half = puffs[o + 3] / 2, tall = half * 0.55;
			var variant = Std.int(puffs[o + 4]);
			var u0 = (variant & 1) * 0.5, u1 = u0 + 0.5;
			if (variant >= 2) {
				var t = u0;
				u0 = u1;
				u1 = t;
			}
			// (its base at y, its top up the camera's up)
			var bx = x - right.x * half, by = y - right.y * half, bz = z - right.z * half;
			var ex = x + right.x * half, ey = y + right.y * half, ez = z + right.z * half;
			var ux = up.x * tall * 2, uy = up.y * tall * 2, uz = up.z * tall * 2;
			w = vertex(w, bx, by, bz, u0, 1, hz, a);
			w = vertex(w, ex, ey, ez, u1, 1, hz, a);
			w = vertex(w, ex + ux, ey + uy, ez + uz, u1, 0, hz, a);
			w = vertex(w, bx, by, bz, u0, 1, hz, a);
			w = vertex(w, ex + ux, ey + uy, ez + uz, u1, 0, hz, a);
			w = vertex(w, bx + ux, by + uy, bz + uz, u0, 0, hz, a);
			drawn++;
			if (drawn >= n) break;
		}
		if (w > 0) device.writeBuffer(buffer, 0, bytes, 0, w);
	}

	inline function vertex(at:Int, x:Float, y:Float, z:Float, u:Float, v:Float, hz:Float, a:Float):Int {
		bytes.setFloat(at, x);
		bytes.setFloat(at + 4, y);
		bytes.setFloat(at + 8, z);
		bytes.setFloat(at + 12, u);
		bytes.setFloat(at + 16, v);
		bytes.setFloat(at + 20, hz);
		bytes.setFloat(at + 24, a);
		return at + FLOATS * 4;
	}

	static inline function smooth(a:Float, b:Float, x:Float):Float {
		var t = Math.max(0, Math.min(1, (x - a) / (b - a)));
		return t * t * (3 - 2 * t);
	}

	static inline function wrap(v:Float):Float
		return v - 2 * Math.floor((v + 1) / 2);

	function draw(enc:Encoder, frame:helder.scene.render.Renderer.FrameInfo) {
		if (!visible || drawn == 0) return;
		var e = frame.exposure;
		CloudShader.params.view.write({
			viewProj: frame.viewProj,
			top: new Vec4(top.x * e, top.y * e, top.z * e, 0),
			bottom: new Vec4(bottom.x * e, bottom.y * e, bottom.z * e, 0),
			haze: new Vec4(haze.x * e, haze.y * e, haze.z * e, 0)
		}, viewBytes);
		enc.setPipeline(pipeline);
		enc.setUniforms(viewSlot, viewBytes);
		enc.setTexture(textureSlot, texture, sampler);
		enc.setVertexBuffer(0, buffer);
		enc.draw(drawn * VERTICES);
	}

	// two cumulus side by side (u 0..0.5, 0.5..1): r its light (lit tops,
	// a darker flat base), a its density (soft lumps, thin edges, a soft base)
	static function cloudTexture(device:Device):Texture {
		var w = 256, h = 128;
		var b = Bytes.alloc(w * h * 4);
		var lumps = [
			[[0.22, 0.62, 0.2], [0.42, 0.48, 0.27], [0.62, 0.55, 0.22], [0.8, 0.66, 0.15], [0.5, 0.68, 0.24]],
			[[0.18, 0.68, 0.15], [0.34, 0.56, 0.22], [0.55, 0.42, 0.3], [0.75, 0.58, 0.2], [0.5, 0.7, 0.25]]
		];
		for (y in 0...h)
			for (x in 0...w) {
				var half = x < w / 2 ? 0 : 1;
				var u = (x - half * w / 2 + 0.5) / (w / 2), v = (y + 0.5) / h;
				var d = 0.0, lit = 0.0;
				for (l in lumps[half]) {
					var dx = (u - l[0]) / l[2], dy = (v - l[1]) / (l[2] * 0.9);
					var r2 = dx * dx + dy * dy;
					var k = Math.exp(-r2 * 2.2);
					d += k;
					// (a lump's upper side lit)
					lit += k * Math.max(0, 0.6 - dy * 0.55);
				}
				// (the base flat and soft; the edges thin)
				d *= 1 - smoothStep(0.72, 0.86, v);
				var a = smoothStep(0.12, 0.85, d);
				var light = Math.max(0, Math.min(1, (lit / Math.max(d, 0.001)) * 0.8 + (0.8 - v) * 0.6));
				var o = (y * w + x) * 4;
				b.set(o, Std.int(light * 255));
				b.set(o + 1, Std.int(light * 255));
				b.set(o + 2, Std.int(light * 255));
				b.set(o + 3, Std.int(a * 255));
			}
		return device.createTexture({width: w, height: h, data: b});
	}

	static inline function smoothStep(a:Float, b:Float, x:Float):Float
		return smooth(a, b, x);
}
