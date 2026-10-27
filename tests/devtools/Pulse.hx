// A console program for the devtools lane: 60 frames a second, as App's
// loop has them (Hot.poll at a turn's start, Hot.framed at its end), a trace
// once a second, ALLOC small arrays of garbage a frame (0: none); its frame
// count kept across a reload.
class Pulse {
	static inline var ALLOC = 0;

	static final sink:Array<Array<Int>> = [for (_ in 0...16) null];

	static function main() {
		var state = helder.dev.Hot.keep("state", () -> {frames: 0});
		trace("v1 start");
		#if hxmc.dev
		while (helder.dev.Hot.poll()) {
			for (i in 0...ALLOC) sink[i & 15] = [i, i, i, i];
			if (++state.frames % 60 == 0) trace("v1 frames=" + state.frames);
			helder.dev.Hot.framed();
			Sys.sleep(1 / 60);
		}
		#end
	}
}
