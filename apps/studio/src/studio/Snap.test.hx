package studio;

import helder.test.Test;

function tests() {
	describe("Snap", () -> {
		final all = {left: true, right: true, top: true, bottom: true};
		test("a moved box: its edge to the nearest line, a guide across both", () -> {
			var s = Snap.box({x: 36, y: 103, width: 50, height: 20}, all, [{x: 0, y: 0, width: 100, height: 100}], 6);
			equals(s.box, {x: 36, y: 100, width: 50, height: 20});
			equals(s.guides, [{vertical: false, at: 100, from: 0, to: 100}]);
		});
		test("a moved box's centre to a centre", () -> {
			var s = Snap.box({x: 23, y: 200, width: 50, height: 20}, all, [{x: 0, y: 0, width: 100, height: 100}], 6);
			equals(s.box.x, 25);
			equals(s.guides[0].at, 50);
		});
		test("a resized edge: only it snaps, the box's size changed", () -> {
			var s = Snap.box({x: 10, y: 10, width: 86, height: 20}, {left: false, right: true, top: false, bottom: false}, [{x: 0, y: 0, width: 100, height: 100}], 6);
			equals(s.box, {x: 10, y: 10, width: 90, height: 20});
			var l = Snap.box({x: 4, y: 10, width: 86, height: 20}, {left: true, right: false, top: false, bottom: false}, [{x: 0, y: 0, width: 100, height: 100}], 6);
			equals(l.box, {x: 0, y: 10, width: 90, height: 20});
		});
		test("nothing near: as it was, no guide", () -> {
			var s = Snap.box({x: 30, y: 30, width: 10, height: 10}, all, [{x: 0, y: 0, width: 100, height: 100}], 6);
			equals(s.box, {x: 30, y: 30, width: 10, height: 10});
			equals(s.guides.length, 0);
		});
		test("the nearest of several lines", () -> {
			equals(Snap.axis([10], [5, 12, 30], 6), {by: 2, at: 12});
			equals(Snap.axis([10], [30], 6), null);
		});
	});
}
