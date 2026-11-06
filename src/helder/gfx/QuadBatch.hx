package helder.gfx;

import haxe.io.Bytes;

// Quads, four vertices of stride bytes each, in one vertex buffer, drawn
// as two triangles each by a shared index buffer (0 1 2, 2 1 3 from each
// quad's first vertex), in runs: the quads in order with one key (a
// texture, its sampling), a draw each. The batcher helder.ui's Renderer
// (its UiShader's vertices) and helder.sprite's SpriteBatch (SpriteQuads)
// are layers over, each writing its own vertices at the offset add gives.
// The vertices and runs need no device (a test's); upload writes them
// into the buffer, grown when they outgrew it, bind binds it and the
// index buffer, draw draws a run. Kept between frames: clear empties it, the buffers
// stay (a steady frame allocates nothing).
class QuadBatch {
	public final stride:Int;
	public var bytes(default, null):Bytes;
	// the quads since clear
	public var count(default, null) = 0;
	// the runs: key, first quad, quads; three ints each
	public final runs:Array<Int> = [];

	var buffer:Null<Buffer> = null;
	var capacity = 0;
	var indices:Null<Buffer> = null;
	var indexQuads = 0;

	public function new(stride:Int, quads = 1024) {
		this.stride = stride;
		bytes = Bytes.alloc(quads * 4 * stride);
	}

	public function clear() {
		count = 0;
		runs.resize(0);
	}

	// the number of runs (draws)
	public inline function draws():Int
		return Std.int(runs.length / 3);

	// a quad more, of key (a run of its own where the key changes): the
	// offset of its first vertex in bytes, which may have grown
	public inline function add(key:Int):Int {
		var o = count * 4 * stride, n = runs.length;
		if (o + 4 * stride > bytes.length) grow(o);
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
		if (buffer == null || bytes.length > capacity) {
			if (buffer != null) device.destroyBuffer(buffer);
			capacity = bytes.length;
			buffer = device.createBuffer({size: capacity, usage: Vertex});
		}
		device.writeBuffer(buffer, 0, bytes, 0, count * 4 * stride);
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

	// both buffers bound (after upload and the pipeline)
	public function bind(enc:Encoder) {
		enc.setVertexBuffer(0, buffer);
		enc.setIndexBuffer(indices, UInt32);
	}

	// the run (0 to draws()) drawn, once bound
	public inline function draw(enc:Encoder, run:Int)
		enc.drawIndexed(runs[run * 3 + 2] * 6, 1, runs[run * 3 + 1] * 6, 0);

	public function dispose(device:Device) {
		if (buffer != null) device.destroyBuffer(buffer);
		if (indices != null) device.destroyBuffer(indices);
		buffer = indices = null;
		capacity = indexQuads = 0;
	}
}
