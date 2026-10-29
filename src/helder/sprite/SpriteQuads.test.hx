package helder.sprite;

import helder.sprite.Atlas.AtlasFrame;
import helder.test.Test;

// SpriteBatch's CPU half: a sprite's corners about its source's centre
// (trimmed, scaled, turned), its texels, its premultiplied colour (no
// alpha when additive), the runs by texture, nothing drawn when clear,
// nothing allocated by a frame once grown (offline: no device)
function tests() {
	describe("SpriteQuads", () -> {
		inline function at(q:SpriteQuads, quad:Int, corner:Int, f:Int):Float
			return q.bytes.getFloat((quad * 4 + corner) * SpriteQuads.STRIDE + f * 4);
		// (a 20x10 sprite, trimmed from a 24x16 source at 1, 2: its centre at 12, 8)
		var frame = new AtlasFrame("s", 64, 32, 20, 10, false, 1, 2, 24, 16);
		test("a sprite's corners about its source's centre", () -> {
			var q = new SpriteQuads(4);
			q.sprite(0, 256, 128, frame, 100, 50, 0, 1, 1, 1);
			equals([at(q, 0, 0, 0), at(q, 0, 0, 1)], [100 - 11.0, 50 - 6.0]);
			equals([at(q, 0, 3, 0), at(q, 0, 3, 1)], [100 + 9.0, 50 + 4.0]);
			equals([at(q, 0, 0, 2), at(q, 0, 0, 3), at(q, 0, 3, 2), at(q, 0, 3, 3)], [64 / 256, 32 / 128, 84 / 256, 42 / 128]);
		});
		test("scaled and turned a quarter (clockwise, y down)", () -> {
			var q = new SpriteQuads(4);
			q.sprite(0, 256, 128, new AtlasFrame("c", 0, 0, 10, 10, false, 0, 0, 10, 10), 0, 0, Math.PI / 2, 2, 2, 1);
			// (the top left -5, -5, scaled to -10, -10, turned to 10, -10)
			approx(at(q, 0, 0, 0), 10, 1e-9);
			approx(at(q, 0, 0, 1), -10, 1e-9);
		});
		test("premultiplied, additive without alpha", () -> {
			var q = new SpriteQuads(4);
			q.sprite(0, 256, 128, frame, 0, 0, 0, 1, 1, 0.5);
			q.sprite(0, 256, 128, frame, 0, 0, 0, 1, 1, 0.5, true);
			equals([for (i in 4...8) at(q, 0, 0, i)], [0.5, 0.5, 0.5, 0.5]);
			equals([for (i in 4...8) at(q, 1, 0, i)], [0.5, 0.5, 0.5, 0.0]);
		});
		test("a rotated frame's texels read a quarter turned", () -> {
			var q = new SpriteQuads(4);
			q.sprite(0, 100, 100, new AtlasFrame("r", 0, 0, 20, 10, true, 0, 0, 20, 10), 0, 0, 0, 1, 1, 1);
			// (stored 10 wide, 20 high: the sprite's top left is the region's top right)
			approx(at(q, 0, 0, 2), 0.1, 1e-6);
			approx(at(q, 0, 0, 3), 0, 1e-6);
			approx(at(q, 0, 3, 2), 0, 1e-6);
			approx(at(q, 0, 3, 3), 0.2, 1e-6);
		});
		test("runs by texture, in order", () -> {
			var q = new SpriteQuads(4);
			for (t in [0, 0, 1, 1, 1, 0])
				q.sprite(t, 256, 128, frame, 0, 0, 0, 1, 1, 1);
			equals(q.runs, [0, 0, 2, 1, 2, 3, 0, 5, 1]);
			equals(q.draws(), 3);
			q.sprite(0, 256, 128, frame, 0, 0, 0, 1, 1, 0);
			equals(q.count, 6);
		});
		test("grown, then a frame allocates nothing", () -> {
			var q = new SpriteQuads(2);
			for (_ in 0...2) {
				q.clear();
				for (i in 0...100)
					q.sprite(i % 3, 256, 128, frame, i, i, 0.1 * i, 1, 1, 1);
			}
			equals(q.count, 100);
			var before = q.bytes;
			q.clear();
			for (i in 0...100)
				q.sprite(i % 3, 256, 128, frame, i, i, 0.1 * i, 1, 1, 1);
			assert(q.bytes == before);
		});
	});
}
