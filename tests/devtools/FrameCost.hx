import helder.devtools.*;

// The Frame domain's cost a frame (the devtools lane, a dev build natively):
// Hot's two calls a turn (Agent.turn, Agent.frame) with Frame disabled, then
// enabled (a frame recorded: the clock, the GC counters, five columns), and
// a batch of 6 frames sent (60 fps at 10 batches a second; no dev server,
// so the line is built, not written); the GC bytes each allocates.
@:access(helder.devtools.Frames)
class FrameCost {
	static inline var N = 1000000;

	static function main() {
		var off = time(() -> for (_ in 0...N) {
			Agent.turn();
			Agent.frame();
		});
		Frames.enable(1e9);
		var on = time(() -> for (_ in 0...N) {
			Agent.turn();
			Agent.frame();
			// (no batch: the columns' end kept away)
			if (Frames.n == 200) Frames.n = 0;
		});
		var batches = Std.int(N / 100);
		var sent = time(() -> for (_ in 0...batches) {
			Frames.n = 6;
			Frames.flush(Agent.now());
		});
		Frames.disable();
		Sys.println('frame disabled: ${ns(off.secs, N)} ns, ${off.bytes} GC bytes in $N frames');
		Sys.println('frame enabled: ${ns(on.secs, N)} ns, ${on.bytes} GC bytes in $N frames');
		Sys.println('a batch of 6 frames: ${ns(sent.secs, batches)} ns, ${Math.round(sent.bytes / batches)} GC bytes (the agent\'s)');
		Sys.println('at 60 fps enabled: ${Math.round((ns(on.secs, N) * 60 + ns(sent.secs, batches) * 10) / 100) / 10} us a second');
		if (off.bytes != 0 || on.bytes != 0) {
			Sys.println("FAIL a frame recorded allocates");
			Sys.exit(1);
		}
	}

	static function time(f:Void->Void):{secs:Float, bytes:Float} {
		var b0 = GcCounters.bytes(), t0 = Agent.now();
		f();
		var t = Agent.now() - t0;
		return {secs: t, bytes: GcCounters.bytes() - b0};
	}

	static function ns(secs:Float, n:Int):Float
		return Math.round(secs / n * 1e10) / 10;
}
