package helder.canvas;

import helder.test.Test;

// PathOps' booleans and PathEffects' effects (the test lane): areas as the
// rasterizer covers them, lengths, counts, the same jitter from a seed
function tests() {
	describe("PathOps", () -> {
		var a = new Path(), b = new Path();
		a.rect(0, 0, 10, 10);
		b.rect(5, 5, 10, 10);
		test("union, intersect, difference, xor of two squares: their areas", () -> {
			approx(area(PathOps.union(a, b)), 175, 0.5);
			approx(area(PathOps.intersect(a, b)), 25, 0.5);
			approx(area(PathOps.difference(a, b)), 75, 0.5);
			approx(area(PathOps.xor(a, b)), 150, 0.5);
			// (the union one contour: no seams between bands)
			var u = PathOps.union(a, b), closes = 0;
			for (i in 0...u.verbCount)
				if (u.verbs[i] == Path.CLOSE) closes++;
			equals(closes, 1);
			equals(u.verbCount, 9);
		});
		test("a circle minus a square, a self-intersecting star simplified by even-odd", () -> {
			var c = new Path();
			c.arc(10, 10, 8, 0, Math.PI * 2);
			var sq = new Path();
			sq.rect(10, 0, 20, 20);
			approx(area(PathOps.difference(c, sq)), Math.PI * 64 / 2, 1.0);
			var star = new Path();
			for (i in 0...5) {
				var t = -Math.PI / 2 + i * 4 * Math.PI / 5;
				if (i == 0) star.moveTo(20 + 18 * Math.cos(t), 20 + 18 * Math.sin(t)) else star.lineTo(20 + 18 * Math.cos(t), 20 + 18 * Math.sin(t));
			}
			star.close();
			var eo = new Canvas(40, 40);
			eo.fill(star, Paint.solid(0xFF000000), true);
			approx(area(PathOps.simplify(star, true)), coverage(eo), 2.0);
		});
	});
	describe("PathEffects", () -> {
		var line = new Path();
		line.moveTo(0, 0);
		line.lineTo(100, 0);
		test("trim, dash, round, jitter", () -> {
			var t = PathEffects.trim(line, 0.25, 0.5);
			approx(t.points[0], 25, 1e-9);
			approx(t.points[2], 50, 1e-9);
			var d = PathEffects.dash(line, [10, 5]);
			var moves = 0;
			for (i in 0...d.verbCount)
				if (d.verbs[i] == Path.MOVE) moves++;
			equals(moves, 7);
			var sq = new Path();
			sq.rect(0, 0, 20, 20);
			var r = PathEffects.round(sq, 5);
			approx(area(r), 400 - (4 - Math.PI) * 25, 2.0);
			var j1 = PathEffects.jitter(line, 10, 3, 7), j2 = PathEffects.jitter(line, 10, 3, 7);
			equals(j1.pointCount, j2.pointCount);
			equals(j1.points[5], j2.points[5]);
		});
	});
}

// (the area a path covers, by the CPU rasterizer)
private function area(p:Path):Float {
	var c = new Canvas(64, 64);
	c.translate(16, 16);
	c.fill(p, Paint.solid(0xFF000000));
	return coverage(c);
}

private function coverage(c:Canvas):Float {
	var s = 0.0;
	for (i in 0...c.width * c.height)
		s += c.bitmap.pixels.get(i * 4 + 3) / 255;
	return s;
}
