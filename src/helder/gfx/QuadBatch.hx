package helder.gfx;

import haxe.io.Bytes;

// Quads in one buffer, drawn in runs: the quads in order with one key (a
// texture, its sampling; a set of textures), a draw each. Either four
// vertices of stride bytes a quad, drawn as two triangles each by a shared
// index buffer (0 1 2, 2 1 3 from each quad's first vertex); or, instanced,
// one instance of stride bytes a quad (its vertex buffer at slot 1, step
// Instance), every quad the same four corners (a vertex buffer of them at
// slot 0: Float2, 0 or 1 across and down, in that order) and six indices,
// a run one instanced draw, the instances in a ring of RING buffers, a
// frame's written to the one the GPU drew the longest ago (no wait for it
// to be done with the last frame's). The batchers helder.ui's Renderer (instanced:
// its UiShader's instances) and helder.sprite's SpriteBatch (SpriteQuads)
// are layers over, each writing its own vertices at the offset add gives.
// The vertices and runs need no device (a test's); upload writes them
// into the buffer, grown when they outgrew it (instanced: only the bytes
// that differ from what the buffer held, the instances before and after
// them already there), bind binds it and the index buffer, draw draws a run.
// Kept between frames: clear empties it, the buffers stay (a steady frame
// allocates nothing).
class QuadBatch {
	public final stride:Int;
	public final instanced:Bool;
	public var bytes(default, null):Bytes;
	// the quads since clear
	public var count(default, null) = 0;
	// the runs: key, first quad, quads; three ints each
	public final runs:Array<Int> = [];
	// the bytes the last upload wrote (instanced: the rest the buffer held already)
	public var uploaded(default, null) = 0;

	var buffer:Null<Buffer> = null;
	var capacity = 0;
	var indices:Null<Buffer> = null;
	var indexQuads = 0;
	// (instanced: the corners; the ring's buffers, each one's size, a copy of
	// what it holds and how many of its first bytes; the one written last)
	var corners:Null<Buffer> = null;
	final ring:Array<Null<Buffer>> = [for (_ in 0...RING) null];
	final ringCapacity:Array<Int> = [for (_ in 0...RING) 0];
	final ringHeld:Array<Null<Bytes>> = [for (_ in 0...RING) null];
	final ringHeldBytes:Array<Int> = [for (_ in 0...RING) 0];
	var current = 0;

	public static inline var RING = 3;

	public function new(stride:Int, quads = 1024, instanced = false) {
		this.stride = stride;
		this.instanced = instanced;
		bytes = Bytes.alloc(quads * (instanced ? 1 : 4) * stride);
	}

	public function clear() {
		count = 0;
		runs.resize(0);
	}

	// the number of runs (draws)
	public inline function draws():Int
		return Std.int(runs.length / 3);

	// the bytes a quad takes
	inline function quadBytes():Int
		return instanced ? stride : 4 * stride;

	// a quad more, of key (a run of its own where the key changes): the
	// offset of its first vertex (instanced: of the instance) in bytes,
	// which may have grown
	public inline function add(key:Int):Int {
		var q = quadBytes(), o = count * q, n = runs.length;
		if (o + q > bytes.length) grow(o);
		if (n > 0 && runs[n - 3] == key) runs[n - 1]++ else {
			runs.push(key);
			runs.push(count);
			runs.push(1);
		}
		count++;
		return o;
	}

	function grow(used:Int) {
		var b = Bytes.alloc(bytes.length * 2);
		b.blit(0, bytes, 0, used);
		bytes = b;
	}

	// the quads into the vertex buffer (false: none), the index buffer made for them
	public function upload(device:Device):Bool {
		if (count == 0) return false;
		var n = count * quadBytes();
		if (instanced) {
			current = (current + 1) % RING;
			uploadChanged(device, n);
			if (indices == null) {
				var ib = Bytes.alloc(6 * 4), cb = Bytes.alloc(4 * 8);
				for (k in 0...6)
					ib.setInt32(k * 4, [0, 1, 2, 2, 1, 3][k]);
				for (k in 0...4) {
					cb.setFloat(k * 8, k >> 1);
					cb.setFloat(k * 8 + 4, k & 1);
				}
				indices = device.createBuffer({size: ib.length, usage: Index, data: ib});
				corners = device.createBuffer({size: cb.length, usage: Vertex, data: cb});
			}
			return true;
		}
		if (buffer == null || bytes.length > capacity) {
			if (buffer != null) device.destroyBuffer(buffer);
			capacity = bytes.length;
			buffer = device.createBuffer({size: capacity, usage: Vertex});
		}
		device.writeBuffer(buffer, 0, bytes, 0, n);
		uploaded = n;
		if (count > indexQuads) {
			var q = indexQuads == 0 ? Std.int(capacity / (4 * stride)) : indexQuads;
			while (q < count)
				q *= 2;
			var ib = Bytes.alloc(q * 6 * 4);
			for (k in 0...q) {
				var v = k * 4, o = k * 24;
				ib.setInt32(o, v);
				ib.setInt32(o + 4, v + 1);
				ib.setInt32(o + 8, v + 2);
				ib.setInt32(o + 12, v + 2);
				ib.setInt32(o + 16, v + 1);
				ib.setInt32(o + 20, v + 3);
			}
			if (indices != null) device.destroyBuffer(indices);
			indices = device.createBuffer({size: ib.length, usage: Index, data: ib});
			indexQuads = q;
		}
		return true;
	}

	// (the first n bytes written into the ring's next buffer where they
	// differ from what it holds: the same instances at the start and the
	// end are left, compared a block at a time; a copy of what was written kept)
	function uploadChanged(device:Device, n:Int) {
		var r = current;
		if (ring[r] == null || bytes.length > ringCapacity[r]) {
			// (a new buffer holds nothing)
			if (ring[r] != null) device.destroyBuffer(ring[r]);
			ringCapacity[r] = bytes.length;
			ring[r] = device.createBuffer({size: bytes.length, usage: Vertex});
			ringHeld[r] = Bytes.alloc(bytes.length);
			ringHeldBytes[r] = 0;
		}
		buffer = ring[r];
		var h = ringHeld[r], held = ringHeldBytes[r], block = stride * 16;
		var lo = 0, hi = n, same = held < n ? held : n;
		while (lo < same) {
			var k = same - lo < block ? same - lo : block;
			if (!equal(h, bytes, lo, k)) break;
			lo += k;
		}
		if (lo >= n) hi = lo;
		else if (held == n) while (hi > lo) {
			// (back from the end, where the held bytes are as many)
			var k = hi - lo < block ? hi - lo : block;
			if (!equal(h, bytes, hi - k, k)) break;
			hi -= k;
		}
		if (hi > lo) {
			device.writeBuffer(buffer, lo, bytes, lo, hi - lo);
			h.blit(lo, bytes, lo, hi - lo);
		}
		uploaded = hi - lo;
		if (n > held) ringHeldBytes[r] = n;
	}

	// (whether a and b have the same k bytes at offset o)
	static inline function equal(a:Bytes, b:Bytes, o:Int, k:Int):Bool {
		#if (target.name == "hxmc")
		return hxmc.unsafe.LibC.memcmp(hxmc.unsafe.BytesPtr.of(a, o, k), hxmc.unsafe.BytesPtr.of(b, o, k), k) == 0;
		#else
		return false;
		#end
	}

	// both buffers bound (after upload and the pipeline)
	public function bind(enc:Encoder) {
		if (instanced) enc.setVertexBuffer(0, corners);
		else enc.setVertexBuffer(0, buffer);
		enc.setIndexBuffer(indices, UInt32);
	}

	// the run (0 to draws()) drawn, once bound
	public inline function draw(enc:Encoder, run:Int) {
		if (instanced) {
			enc.setVertexBuffer(1, buffer, runs[run * 3 + 1] * stride);
			enc.drawIndexed(6, runs[run * 3 + 2]);
		} else enc.drawIndexed(runs[run * 3 + 2] * 6, 1, runs[run * 3 + 1] * 6, 0);
	}

	public function dispose(device:Device) {
		if (buffer != null) device.destroyBuffer(buffer);
		if (indices != null) device.destroyBuffer(indices);
		if (corners != null) device.destroyBuffer(corners);
		for (r in 0...RING) {
			if (ring[r] != null && ring[r] != buffer) device.destroyBuffer(ring[r]);
			ring[r] = null;
			ringHeld[r] = null;
			ringCapacity[r] = ringHeldBytes[r] = 0;
		}
		buffer = indices = corners = null;
		capacity = indexQuads = 0;
	}
}
