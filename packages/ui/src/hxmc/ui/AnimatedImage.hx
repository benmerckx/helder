package hxmc.ui;

import haxe.io.Bytes;

// An animation's frames (a GIF's, WebP's or animated PNG's:
// GifDecoder.frames, WebpDecoder.frames, PngDecoder.frames) played on the Clock:
// image is the frame shown, its pixels written over at each change of
// frame (a renderer uploads them again). Played as browsers play it: each
// frame for its delay, one of 10 ms or less as 100 ms, the whole the
// repetitions' times after the first (-1: forever), then the last frame
// stays. In markup, an image element's src takes one and plays it.
class AnimatedImage {
	public final image:Image;
	public final frames:Array<{rgba:Bytes, delay:Float}>;
	public final repetitions:Int;
	public var frame(default, null) = 0;
	public var playing(default, null) = false;

	var started = Math.NaN;
	var run = 0;

	public function new(width:Int, height:Int, frames:Array<{rgba:Bytes, delay:Float}>, repetitions:Int) {
		if (frames.length == 0) throw "AnimatedImage: no frames";
		this.frames = frames;
		this.repetitions = repetitions;
		image = new Image(width, height, frames[0].rgba.sub(0, frames[0].rgba.length));
	}

	// a GIF, WebP or PNG file's animation (by its signature)
	public static function decode(bytes:Bytes):AnimatedImage {
		var a = bytes.length >= 12 && bytes.getString(0, 4) == "RIFF" && bytes.getString(8, 4) == "WEBP" ? WebpDecoder.frames(bytes) : bytes.length >= 8
			&& bytes.get(0) == 0x89 && bytes.getString(1, 3) == "PNG" ? PngDecoder.frames(bytes) : GifDecoder.frames(bytes);
		return new AnimatedImage(a.width, a.height, a.frames, a.repetitions);
	}

	// how long a frame shows (seconds)
	public static inline function duration(delay:Float):Float
		return delay <= 0.01 ? 0.1 : delay;

	// from the first frame, on the Clock's next tick
	public function play() {
		stop();
		show(0);
		if (frames.length < 2) return;
		playing = true;
		started = Math.NaN;
		var mine = ++run;
		Clock.add(t -> mine == run && step(t));
	}

	// the frame shown stays
	public function stop() {
		playing = false;
		run++;
	}

	function step(t:Float):Bool {
		if (Math.isNaN(started)) started = t;
		var total = 0.0;
		for (f in frames)
			total += duration(f.delay);
		var e = t - started;
		if (repetitions >= 0 && e >= total * (repetitions + 1)) {
			show(frames.length - 1);
			playing = false;
			return false;
		}
		var r = e % total, k = 0;
		while (k < frames.length - 1 && r >= duration(frames[k].delay)) {
			r -= duration(frames[k].delay);
			k++;
		}
		show(k);
		return true;
	}

	function show(k:Int) {
		if (k == frame) return;
		frame = k;
		image.pixels.blit(0, frames[k].rgba, 0, image.pixels.length);
		image.changed();
	}
}
