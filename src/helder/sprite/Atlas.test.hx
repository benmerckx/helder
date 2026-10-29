package helder.sprite;

import helder.test.Test;

// TexturePacker's two formats read alike: a frame's rectangle, its trim,
// its source, a rotated one
function tests() {
	describe("Atlas", () -> {
		var array = '{"frames":[{"filename":"ship","frame":{"x":10,"y":20,"w":30,"h":40},"rotated":false,"trimmed":true,'
			+ '"spriteSourceSize":{"x":2,"y":3,"w":30,"h":40},"sourceSize":{"w":34,"h":48}}],"meta":{"image":"sheet.png","size":{"w":256,"h":128}}}';
		var hash = '{"frames":{"ship":{"frame":{"x":10,"y":20,"w":30,"h":40},"rotated":true,"trimmed":false,'
			+ '"spriteSourceSize":{"x":0,"y":0,"w":30,"h":40},"sourceSize":{"w":30,"h":40}}},"meta":{"size":{"w":256,"h":128}}}';
		test("the array format", () -> {
			var a = Atlas.parse(array);
			var f = require(a.get("ship"));
			equals([f.x, f.y, f.w, f.h, f.trimX, f.trimY, f.sourceW, f.sourceH], [10, 20, 30, 40, 2, 3, 34, 48]);
			equals(f.rotated, false);
			equals([a.width, a.height], [256, 128]);
			equals(a.image, "sheet.png");
		});
		test("the hash format, rotated", () -> {
			var f = require(Atlas.parse(hash).get("ship"));
			equals([f.x, f.y, f.w, f.h, f.sourceW], [10, 20, 30, 40, 30]);
			assert(f.rotated);
		});
		test("a missing frame is null", () -> assert(Atlas.parse(array).get("nope") == null));
	});
}
