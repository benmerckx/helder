// A console program for the cli lane: a count that helder.dev.Hot keeps
// across a reload, ticking ten times a second; `Tally <n>` stops at n
// (a release build, which has no dev loop).
class Tally {
	static function main() {
		var stop = Std.parseInt(Sys.args()[0] ?? "") ?? -1;
		var state = helder.dev.Hot.keep("state", () -> {count: 0});
		#if hxmc.dev_host
		// (in the dev host: its process, the same for every build)
		Sys.println("start pid=" + helder.dev.Hosted.pid());
		#end
		while (alive() && state.count != stop) {
			state.count++;
			Sys.println("v1 count=" + state.count);
			#if hxmc.dev
			helder.dev.Hot.framed();
			#end
			Sys.sleep(0.1);
		}
	}

	// (the dev server's messages: false once this build handed over)
	static function alive():Bool {
		#if hxmc.dev
		return helder.dev.Hot.poll();
		#else
		return true;
		#end
	}
}
