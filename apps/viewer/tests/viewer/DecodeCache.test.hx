package viewer;

import haxe.io.Bytes;
import helder.test.Test;
import viewer.Decode.Decoded;

// DecodeCache: the wanted decoded nearest first, a few at a time; over
// the budget the farthest go (the unwanted first), never the one shown;
// a budget too small for every neighbour does not decode them again and
// again; a dropped file decoded again
function tests() {
	describe("DecodeCache", () -> {
		// (decodes that land when told: each a frame of size bytes)
		var pending:Array<{path:String, done:Decoded->Void}> = [];
		var decoded:Array<String> = [];
		function decode(path:String, side:Int, done:Decoded->Void) {
			decoded.push(path);
			pending.push({path: path, done: done});
		}
		function land(?path:String) {
			var i = 0;
			if (path != null) for (k in 0...pending.length) if (pending[k].path == path) i = k;
			var p = pending.splice(i, 1)[0];
			p.done(image(100));
		}
		beforeEach(() -> {
			pending = [];
			decoded = [];
		});
		test("nearest first, two at a time", () -> {
			var c = new DecodeCache(decode, 1000);
			c.want(["a", "b", "c", "d"]);
			equals(decoded, ["a", "b"]);
			land("a");
			equals(decoded, ["a", "b", "c"]);
			land();
			land();
			equals(decoded, ["a", "b", "c", "d"]);
			assert(c.get("a") != null);
		});
		test("over the budget: the unwanted, then the farthest; never the one shown", () -> {
			var c = new DecodeCache(decode, 350);
			c.want(["a", "b", "c"]);
			land();
			land();
			land();
			equals(c.used, 300.0);
			// (the next image: a is now the farthest, x the one shown)
			c.want(["b", "c", "x", "a"]);
			land("x");
			equals(c.used, 300.0);
			equals(c.get("a"), null);
			assert(c.get("b") != null && c.get("c") != null && c.get("x") != null);
			// (an unwanted one goes before a far wanted one)
			c.want(["b", "x"]);
			c.budget = 250;
			c.want(["b", "x"]);
			equals(c.get("c"), null);
			assert(c.get("b") != null && c.get("x") != null);
			// (the one shown stays even alone over the budget)
			c.budget = 50;
			c.want(["x"]);
			assert(c.get("x") != null);
			equals(c.get("b"), null);
		});
		test("a budget too small for the neighbours: no decode loop", () -> {
			var c = new DecodeCache(decode, 250);
			c.want(["a", "b", "c"]);
			land();
			land();
			land();
			equals(decoded, ["a", "b", "c"]);
			equals(pending.length, 0);
			equals(c.used <= 250, true);
		});
		test("refine: decoded again at a larger side, the smaller one kept meanwhile", () -> {
			var sides = [];
			var c = new DecodeCache((path, side, done) -> {
				sides.push(side);
				var w = side == 0 ? 1000 : side;
				done({width: 1000, height: 1000, pixelsWidth: w, pixelsHeight: w, frames: [{pixels: hxmc.unsafe.IoBuffer.alloc(16), delay: 0.0}], repetitions: 0, format: "JPEG", fileSize: 1, error: null, errorKind: ""});
			}, 1000);
			c.side = 250;
			c.want(["a"]);
			equals(c.get("a").pixelsWidth, 250);
			equals(c.refine("a", 200), false);
			equals(c.refine("a", 500), true);
			equals(c.get("a").pixelsWidth, 500);
			equals(c.refine("a", 0), true);
			equals(c.get("a").pixelsWidth, 1000);
			equals(c.refine("a", 0), false);
			equals(sides, [250, 500, 0]);
		});
		test("dropped (changed on disk): decoded again when wanted", () -> {
			var c = new DecodeCache(decode, 1000);
			c.want(["a"]);
			land();
			c.drop("a");
			equals(c.get("a"), null);
			c.want(["a"]);
			equals(decoded, ["a", "a"]);
		});
	});
}

private function image(bytes:Int):Decoded
	return {
		width: 1, height: 1, pixelsWidth: 1, pixelsHeight: 1, frames: [{pixels: hxmc.unsafe.IoBuffer.alloc(bytes), delay: 0.0}], repetitions: 0,
		format: "PNG", fileSize: bytes, error: null, errorKind: ""
	};
