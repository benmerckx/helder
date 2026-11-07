package helder.ui;

import helder.test.Test;

// HeightIndex against a naive model (an array of heights, NaN for a row
// not measured): random inserts, removes, measures, forgets and estimate
// changes, each checked by every row's offset and the rows at offsets
// (between rows, at their starts, past the ends), seeded; a million rows
// measured in part, its lookups and an insert in the middle.
@:test.interp
function tests() {
	describe("HeightIndex", () -> {
		test("offsets and rows of a small list", () -> {
			var h = new HeightIndex(10, 5);
			equals(h.total(), 50.0);
			equals(h.offsetOf(3), 30.0);
			equals(h.rowAt(0), 0);
			equals(h.rowAt(29.5), 2);
			equals(h.rowAt(30), 3);
			equals(h.rowAt(-4), 0);
			equals(h.rowAt(1e9), 4);
			h.set(1, 25);
			equals(h.offsetOf(2), 35.0);
			equals(h.rowAt(34), 1);
			equals(h.total(), 65.0);
			equals(h.mean(), 25.0);
			h.estimate = 20;
			equals(h.total(), 105.0);
			equals(h.offsetOf(2), 45.0);
			h.forget(1);
			equals(h.total(), 100.0);
			equals(h.measuredCount, 0);
		});
		test("empty", () -> {
			var h = new HeightIndex(44);
			equals(h.rowAt(10), -1);
			equals(h.total(), 0.0);
			h.insert(0, 3);
			equals(h.length, 3);
			h.remove(0, 3);
			equals(h.length, 0);
			equals(h.total(), 0.0);
			h.insert(0, 1);
			equals(h.offsetOf(1), 44.0);
		});
		for (seed in [1, 2, 3, 7, 42]) test('random edits against a model (seed $seed)', () -> {
			var rand = new Rand(seed), model:Array<Float> = [], est = 20.0;
			var h = new HeightIndex(est);
			function height():Float
				return 4 + rand.int(120) * 0.25;
			for (step in 0...1500) {
				var r = rand.int(100);
				if (r < 30 || model.length == 0) {
					var at = rand.int(model.length + 1), n = rand.int(4) == 0 ? 1 + rand.int(400) : 1 + rand.int(3);
					for (_ in 0...n)
						model.insert(at, Math.NaN);
					h.insert(at, n);
				} else if (r < 45) {
					var at = rand.int(model.length), n = rand.int(5) == 0 ? 1 + rand.int(300) : 1;
					if (at + n > model.length) n = model.length - at;
					model.splice(at, n);
					h.remove(at, n);
				} else if (r < 90) {
					var at = rand.int(model.length), v = height();
					model[at] = v;
					h.set(at, v);
				} else if (r < 95) {
					var at = rand.int(model.length);
					model[at] = Math.NaN;
					h.forget(at);
				} else {
					est = 8 + rand.int(80);
					h.estimate = est;
				}
				if (step % 50 == 49) check(h, model, est, rand);
			}
			check(h, model, est, rand);
		});
		test("a million rows: lookups, measures, an insert and a remove in the middle", () -> {
			var h = new HeightIndex(44, 1000000);
			equals(h.total(), 44000000.0);
			equals(h.rowAt(44 * 999999 + 1), 999999);
			for (i in 0...2000)
				h.set(i * 499, i % 3 == 0 ? 30 : 60);
			var model = 0.0;
			for (i in 0...2000)
				model += (i % 3 == 0 ? 30 : 60) - 44;
			approx(h.total(), 44000000.0 + model);
			var y = h.offsetOf(654321);
			equals(h.rowAt(y), 654321);
			equals(h.rowAt(y - 0.01), 654320);
			h.insert(500000, 3);
			equals(h.length, 1000003);
			equals(h.rowAt(h.offsetOf(654324)), 654324);
			approx(h.offsetOf(654324) - y, 132.0);
			h.remove(10, 600000);
			equals(h.length, 400003);
			assert(h.bytes() < 400003 * 8, 'bytes ${h.bytes()}');
		});
	});
}

// (every row's offset and height, the rows at their starts, inside them and past the ends)
private function check(h:HeightIndex, model:Array<Float>, est:Float, rand:Rand) {
	equals(h.length, model.length, "length");
	var y = 0.0, starts = [];
	for (i in 0...model.length) {
		starts.push(y);
		var v = Math.isNaN(model[i]) ? est : model[i];
		if (Math.abs(h.offsetOf(i) - y) > 1e-6) fail('offsetOf($i): ${h.offsetOf(i)}, the model $y');
		if (h.heightOf(i) != v) fail('heightOf($i): ${h.heightOf(i)}, the model $v');
		if (h.isMeasured(i) == Math.isNaN(model[i])) fail('isMeasured($i)');
		y += v;
	}
	approx(h.total(), y, 1e-6, "total");
	approx(h.offsetOf(model.length), y, 1e-6, "the end's offset");
	if (model.length == 0) return;
	equals(h.rowAt(-1), 0);
	equals(h.rowAt(y + 5), model.length - 1);
	for (_ in 0...200) {
		var i = rand.int(model.length), v = Math.isNaN(model[i]) ? est : model[i];
		if (v <= 0) continue;
		var at = starts[i] + v * rand.float();
		var want = i;
		// (a row at its start: the first of the rows there, empty rows passed over)
		if (h.rowAt(at) != want && !(at == starts[i] && h.offsetOf(h.rowAt(at)) == at)) fail('rowAt($at): ${h.rowAt(at)}, the model $want');
	}
}

// (a seeded generator: the same edits on every target)
private class Rand {
	var s:Int;

	public function new(seed:Int)
		s = seed * 0x9E3779B1 + 1;

	public function int(n:Int):Int {
		s = (s * 1103515245 + 12345) & 0x7fffffff;
		return n <= 0 ? 0 : (s >> 4) % n;
	}

	public function float():Float
		return int(1 << 20) / (1 << 20);
}
