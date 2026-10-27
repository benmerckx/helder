import haxe.io.Bytes;
import helder.image.*;

// helder.image's tests, on Eval and natively (bun run test image):
// png/*.png decoded (every colour type and depth, tRNS, the filters, Adam7;
// png-cases.mjs writes them and the pixels expected); jpeg/*.jpg and
// gif/*.gif against Chromium's pixels (jpeg-cases.mjs, gif-cases.mjs);
// webp/*.webp against libwebp's (webp-cases.mjs); apng/*.png's frames
// against Chromium's (apng-cases.mjs); an AnimatedImage played on a clock
// ticked by hand.
//   ImageTest [dir]   (dir: tests/image by default)
class ImageTest {
	static var checks = 0;
	static var failed = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('ImageTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var here = Sys.args()[0] ?? "tests/image";
		var clock = new TestClock();
		var dir = here + "/png";
		var names = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".png")) f.substr(0, f.length - 4)];
		names.sort(Reflect.compare);
		check("images: the cases", names.length >= 20, '${names.length}');
		// (the file kept as it was, for a writer to embed; gone once the pixels change)
		var file = sys.io.File.getBytes(dir + "/" + names[0] + ".png"), kept = Image.decode(file);
		var had = kept.source != null && kept.source.type == "png" && kept.source.bytes == file;
		kept.changed();
		check("images: the file it was decoded from, until its pixels change", had && kept.source == null && new Image(1, 1).source == null);
		for (n in names) {
			var want = sys.io.File.getBytes(dir + "/" + n + ".rgba");
			var img = try Image.decode(sys.io.File.getBytes(dir + "/" + n + ".png")) catch (e:Dynamic) {
				check("images: " + n, false, Std.string(e));
				continue;
			}
			var first = -1;
			for (i in 0...want.length)
				if (img.pixels.get(i) != want.get(i)) {
					first = i;
					break;
				}
			check("images: " + n, img.width == 13 && img.height == 11 && first < 0,
				first < 0 ? '${img.width}x${img.height}' : 'pixel ${first >> 2} channel ${first & 3}: ${img.pixels.get(first)}, not ${want.get(first)}');
		}
		// JPEG and GIF: jpeg/*.jpg and gif/*.gif against the pixels Chromium
		// decoded (jpeg-cases.mjs, gif-cases.mjs)
		for (kind in [{dir: "jpeg", ext: ".jpg", least: 15}, {dir: "gif", ext: ".gif", least: 8}, {dir: "webp", ext: ".webp", least: 25}, {dir: "apng", ext: ".png", least: 3}]) {
		var jdir = here + "/" + kind.dir;
		var cases:Array<{name:String, width:Int, height:Int, ?durations:Array<Float>, ?repetition:Int}> = haxe.Json.parse(sys.io.File.getContent(jdir + "/cases.json"));
		check(kind.dir + ": the cases", cases.length >= kind.least, '${cases.length}');
		for (c in cases) {
			// (an animation: every frame as Chromium's ImageDecoder composes it, its duration, the repetitions)
			if (c.durations != null) {
				var want = sys.io.File.getBytes(jdir + "/" + c.name + ".frames.rgba");
				var bytes = sys.io.File.getBytes(jdir + "/" + c.name + kind.ext);
				var a = try kind.dir == "webp" ? WebpDecoder.frames(bytes) : kind.dir == "apng" ? PngDecoder.frames(bytes) : GifDecoder.frames(bytes) catch (e:Dynamic) {
					check(kind.dir + ": " + c.name, false, Std.string(e));
					continue;
				}
				var size = c.width * c.height * 4, bad = [];
				for (k in 0...a.frames.length)
					if (k * size + size > want.length || a.frames[k].rgba.compare(want.sub(k * size, size)) != 0) bad.push(k);
				check(kind.dir + ": " + c.name + ", its frames", a.width == c.width && a.frames.length == c.durations.length && bad.length == 0
					&& [for (f in a.frames) f.delay].join(",") == c.durations.join(",") && a.repetitions == c.repetition,
					'${a.frames.length} frames, wrong: ${bad.join(",")}; ' + [for (f in a.frames) f.delay].join(",") + ' ${a.repetitions}');
				// (an APNG's default image: libpng's, whether in the animation or not)
				if (kind.dir == "apng")
					check("apng: " + c.name + ", its default image", Image.decode(bytes).pixels.compare(sys.io.File.getBytes(jdir + "/" + c.name + ".rgba")) == 0);
				continue;
			}
			var want = sys.io.File.getBytes(jdir + "/" + c.name + ".rgba");
			var img = try Image.decode(sys.io.File.getBytes(jdir + "/" + c.name + kind.ext)) catch (e:Dynamic) {
				check(kind.dir + ": " + c.name, false, Std.string(e));
				continue;
			}
			var differ = 0, most = 0, first = -1;
			if (img.pixels.length == want.length)
				for (i in 0...want.length) {
					var d = img.pixels.get(i) - want.get(i);
					if (d != 0) {
						if (first < 0) first = i;
						differ++;
						if (d < 0) d = -d;
						if (d > most) most = d;
					}
				}
			check(kind.dir + ": " + c.name, img.width == c.width && img.height == c.height && differ == 0,
				'${img.width}x${img.height}' + (differ > 0 ? ': $differ values differ, by at most $most (first: pixel ${first >> 2} channel ${first & 3})' : ""));
		}
		}
		// an animation played on a clock: frames by their delays, three plays (two repetitions), then the last frame stays
		var anim = AnimatedImage.decode(sys.io.File.getBytes(here + "/gif/anim-background.gif"));
		var shown = [];
		anim.play(clock.add);
		for (t in [10.0, 10.1, 10.2, 10.35, 10.5, 11.1, 11.4, 12.0]) {
			clock.tick(t);
			shown.push(anim.frame);
		}
		check("animation: frames by their delays, played three times", shown.join(",") == "0,0,1,2,0,1,2,2" && !anim.playing && !clock.active, shown.join(","));
		check("animation: the image shows the frame", anim.image.pixels.compare(anim.frames[2].rgba) == 0 && anim.image.version > 0);
		var zero = AnimatedImage.decode(sys.io.File.getBytes(here + "/gif/anim-transparent.gif"));
		zero.play(clock.add);
		var z = [];
		for (t in [20.0, 20.05, 20.15, 20.25]) {
			clock.tick(t);
			z.push(zero.frame);
		}
		zero.stop();
		check("animation: a delay of 0 shows for 100 ms, forever", z.join(",") == "0,0,1,0" && !zero.playing, z.join(","));
		clock.tick(21);
		check("animation: stopped, nothing more animates", !clock.active);
		var threw = try {
			Image.decode(haxe.io.Bytes.ofString("GIF89a"));
			false;
		} catch (e:Dynamic) true;
		check("images: not a PNG file", threw);
		Sys.println('ImageTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}

// (an animation clock ticked by hand: its steps called with the time until they return false)
class TestClock {
	final steps:Array<Float->Bool> = [];

	public var active(get, never):Bool;

	public function new() {}

	inline function get_active()
		return steps.length > 0;

	public function add(step:Float->Bool)
		steps.push(step);

	public function tick(t:Float) {
		var i = 0;
		while (i < steps.length)
			if (steps[i](t)) i++ else steps.splice(i, 1);
	}
}
