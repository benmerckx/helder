package helder.text;

import helder.test.Test;

// FontEncoder's fonts read back by FontFile: names, metrics, the character
// map, advances, kerning and the outlines' segments
function tests() {
	describe("FontEncoder", () -> {
		var box = [[{x: 50.0, y: 0.0, on: true}, {x: 50.0, y: 700.0, on: true}, {x: 450.0, y: 700.0, on: true}, {x: 450.0, y: 0.0, on: true}]];
		var bowl = [[
			{x: 300.0, y: 0.0, on: true},
			{x: 50.0, y: 0.0, on: false},
			{x: 50.0, y: 250.0, on: true},
			{x: 50.0, y: 500.0, on: false},
			{x: 300.0, y: 500.0, on: true},
			{x: 550.0, y: 500.0, on: false},
			{x: 550.0, y: 250.0, on: true},
			{x: 550.0, y: 0.0, on: false}
		]];
		var bytes = FontEncoder.encode({
			family: "Test Sans",
			unitsPerEm: 1000,
			ascender: 800,
			descender: -200,
			xHeight: 500,
			capHeight: 700,
			glyphs: [
				{codes: [], advance: 500, contours: box},
				{codes: [32], advance: 250, contours: []},
				{codes: [65, 66], advance: 520, contours: box},
				{codes: [111], advance: 600, contours: bowl}
			],
			kerning: [{left: 2, right: 3, value: -40}]
		});
		var f = FontFile.parse(bytes);
		test("names and metrics", () -> {
			equals(f.family, "Test Sans");
			equals(f.subfamily, "Regular");
			equals(f.unitsPerEm, 1000);
			equals(f.ascender, 800);
			equals(f.descender, -200);
			equals(f.numGlyphs, 4);
		});
		test("characters, advances and kerning", () -> {
			equals([f.glyph(32), f.glyph(65), f.glyph(66), f.glyph(111), f.glyph(120)], [1, 2, 2, 3, 0]);
			equals([f.advance(1), f.advance(2), f.advance(3)], [250.0, 520.0, 600.0]);
			equals(f.kerning(2, 3), -40);
			equals(f.kerning(3, 2), 0);
		});
		test("outlines: lines, and quadratics with implied points", () -> {
			var a = new Segments(), o = new Segments();
			f.outline(2, a);
			f.outline(3, o);
			equals(a.log.join(" "), "M50,0 L50,700 L450,700 L450,0 L50,0 Z");
			equals(o.log.join(" "), "M300,0 Q50,0 50,250 Q50,500 300,500 Q550,500 550,250 Q550,0 300,0 Z");
			equals(f.bounds(3), [50, 0, 550, 500]);
		});
	});
}

private class Segments implements Outline {
	public final log:Array<String> = [];

	public function new() {}

	public function moveTo(x:Float, y:Float)
		log.push('M$x,$y');

	public function lineTo(x:Float, y:Float)
		log.push('L$x,$y');

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		log.push('Q$cx,$cy $x,$y');

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float)
		log.push('C$c1x,$c1y $c2x,$c2y $x,$y');

	public function close()
		log.push("Z");
}
