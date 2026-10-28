package helder.test;

import haxe.io.Bytes;
import helder.test.Test;

private enum Shape {
	Circle(r:Float);
	Rect(w:Float, h:Float);
	Group(items:Array<Shape>);
}

private class Point {
	public var x:Int;
	public var y:Int;

	public function new(x, y) {
		this.x = x;
		this.y = y;
	}
}

// Equal's deep equality and its literals (on interp too: helder.test runs
// there for the files that opt in, as this one)
@:test.interp
function tests() {
	describe("diff", () -> {
		test("scalars", () -> {
			assert(Equal.diff(1, 1) == null);
			assert(Equal.diff(1, 1.0) == null, "an Int and a Float");
			assert(Equal.diff(1, 2) == "");
			assert(Equal.diff("a", "a") == null);
			assert(Equal.diff(null, 0) == "");
			assert(Equal.diff(Math.NaN, Math.NaN) == null, "NaN equals NaN");
		});
		test("arrays", () -> {
			equals([1, 2, 3], [1, 2, 3]);
			equals(Equal.diff([1, 2, 3], [1, 2, 4]), "[2]");
			equals(Equal.diff([1, 2], [1, 2, 3]), ".length");
			equals(Equal.diff([[1], [2]], [[1], [3]]), "[1][0]");
		});
		test("structures", () -> {
			equals({a: 1, b: {c: "x"}}, {b: {c: "x"}, a: 1});
			equals(Equal.diff({a: 1, b: {c: "x"}}, {a: 1, b: {c: "y"}}), ".b.c");
			equals(Equal.diff({a: 1}, {a: 1, b: 2}), ".b");
		});
		test("maps", () -> {
			equals(["a" => 1, "b" => 2], ["b" => 2, "a" => 1]);
			equals(Equal.diff(["a" => 1], ["a" => 2]), '["a"]');
			equals(Equal.diff([1 => "x"], [2 => "x"]), "[1]");
		});
		test("enums", () -> {
			equals(Group([Circle(1), Rect(2, 3)]), Group([Circle(1), Rect(2, 3)]));
			notEquals(Circle(1), Circle(2));
			notEquals(Circle(1), Rect(1, 1));
			equals(Equal.diff(Group([Circle(1)]), Group([Circle(2)])), "(Group #0)[0](Circle #0)");
		});
		test("bytes, instances, dates", () -> {
			equals(Bytes.ofString("abc"), Bytes.ofString("abc"));
			notEquals(Bytes.ofString("abc"), Bytes.ofString("abd"));
			equals(new Point(1, 2), new Point(1, 2));
			equals(Equal.diff(new Point(1, 2), new Point(1, 3)), ".y");
			equals(new Date(2020, 1, 2, 3, 4, 5), new Date(2020, 1, 2, 3, 4, 5));
		});
	});
	describe("show", () -> {
		test("literals", () -> {
			equals(Equal.show("a\"b\n"), '"a\\"b\\n"');
			equals(Equal.show([1, null, "x"]), '[1, null, "x"]');
			equals(Equal.show({b: 1, a: [true]}), "{a: [true], b: 1}");
			equals(Equal.show(Rect(1, 2.5)), "Rect(1, 2.5)");
			equals(Equal.show(["k" => 1]), '["k" => 1]');
			equals(Equal.show(Bytes.ofHex("00ff")), "Bytes(2: 00ff)");
		});
	});
}
