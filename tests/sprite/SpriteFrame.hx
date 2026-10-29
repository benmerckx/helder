import haxe.io.Bytes;
import helder.gfx.*;
import helder.image.Image;
import helder.os.Surface;
import helder.sprite.Atlas;
import helder.sprite.SpriteBatch;

// helder.sprite's SpriteBatch on a GPU, headless (Mesa's llvmpipe on
// Linux): a 4x4 sheet of four colours, its quarters drawn as sprites
// over a dark clear, and the pixels read back: a sprite where it was put
// (trimmed about its source's centre), scaled, turned a quarter, faded
// (alpha over the clear), added (additive on top of another), and two
// textures in one frame (two runs). Exits 1 on a wrong pixel.
class SpriteFrame {
	static inline var W = 64;
	static inline var H = 64;

	static function main() {
		var device = Device.create(Surface.headless(W, H));
		// (the sheet: red, green, blue and white quarters, opaque)
		var px = Bytes.alloc(4 * 4 * 4);
		for (y in 0...4)
			for (x in 0...4) {
				var q = (y < 2 ? 0 : 2) + (x < 2 ? 0 : 1), o = 4 * (y * 4 + x);
				var c = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]][q];
				px.set(o, c[0]);
				px.set(o + 1, c[1]);
				px.set(o + 2, c[2]);
				px.set(o + 3, 255);
			}
		var atlas = Atlas.parse('{"frames":{'
			+ '"red":{"frame":{"x":0,"y":0,"w":2,"h":2},"rotated":false,"spriteSourceSize":{"x":0,"y":0,"w":2,"h":2},"sourceSize":{"w":2,"h":2}},'
			+ '"green":{"frame":{"x":2,"y":0,"w":2,"h":2},"rotated":false,"spriteSourceSize":{"x":0,"y":0,"w":2,"h":2},"sourceSize":{"w":2,"h":2}},'
			+ '"blue":{"frame":{"x":0,"y":2,"w":2,"h":2},"rotated":false,"spriteSourceSize":{"x":0,"y":0,"w":2,"h":2},"sourceSize":{"w":2,"h":2}},'
			+ '"white":{"frame":{"x":2,"y":2,"w":2,"h":2},"rotated":false,"spriteSourceSize":{"x":0,"y":0,"w":2,"h":2},"sourceSize":{"w":2,"h":2}}'
			+ '},"meta":{"size":{"w":4,"h":4}}}');
		var batch = new SpriteBatch(device);
		var sheet = batch.add(new Image(4, 4, px));
		var other = batch.add(new Image(1, 1, Bytes.ofHex("ffff00ff")));
		batch.begin(W, H);
		// (red: 8 units square at 8, 8; green scaled to 16 and turned at 40, 8; blue at half alpha at 8, 40)
		batch.sprite(sheet, atlas.get("red"), 8, 8, 0, 4, 4);
		batch.sprite(sheet, atlas.get("green"), 40, 8, Math.PI / 2, 8, 8);
		batch.sprite(sheet, atlas.get("blue"), 8, 40, 0, 4, 4, 0.5);
		// (red, then green added over it at 40, 40: yellow)
		batch.sprite(sheet, atlas.get("red"), 40, 40, 0, 4, 4);
		batch.sprite(sheet, atlas.get("green"), 40, 40, 0, 4, 4, 1, true);
		// (the other texture: a yellow quad at the bottom right corner)
		batch.image(other, 0, 0, 1, 1, 56, 56, 8, 8);
		var enc = device.beginFrame();
		enc.beginPass({colors: [{load: Clear, clear: new Color(0, 0, 0.2)}]});
		batch.flush(enc);
		enc.endPass();
		var pixels = Bytes.alloc(W * H * 4);
		device.readPixels(pixels);
		device.endFrame();
		var bad = 0;
		function expect(what:String, x:Int, y:Int, r:Int, g:Int, b:Int) {
			var o = 4 * (y * W + x), got = [pixels.get(o), pixels.get(o + 1), pixels.get(o + 2)];
			var ok = Math.abs(got[0] - r) <= 3 && Math.abs(got[1] - g) <= 3 && Math.abs(got[2] - b) <= 3;
			Sys.println((ok ? "ok   " : "FAIL ") + '$what at $x, $y: ${got.join(",")}' + (ok ? "" : ' (want $r,$g,$b)'));
			if (!ok) bad++;
		}
		expect("red sprite", 8, 8, 255, 0, 0);
		expect("clear beside it", 14, 8, 0, 0, 51);
		expect("green, scaled", 40, 8, 0, 255, 0);
		expect("green's extent", 37, 5, 0, 255, 0);
		expect("blue at half alpha", 8, 40, 0, 0, 153);
		expect("green added to red", 40, 40, 255, 255, 0);
		expect("the second texture", 60, 60, 255, 255, 0);
		expect("the clear", 24, 24, 0, 0, 51);
		Sys.println('SpriteFrame: ${batch.quads.count} quads in ${batch.quads.draws()} draws');
		if (batch.quads.draws() != 2) bad++;
		device.dispose();
		if (bad > 0) {
			Sys.println('SpriteFrame: $bad wrong');
			Sys.exit(1);
		}
		Sys.println("SpriteFrame: ok");
	}
}
