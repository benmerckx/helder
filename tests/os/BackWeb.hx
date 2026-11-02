import helder.os.*;

// App.onBack and App.backDepth in a browser (`bun run test touch-web`:
// back-web.mjs): the key "d" goes a step deeper (App.backDepth + 1), each
// back a step up while deep ("back 1": taken, at depth 1 now), at 0 not
// taken ("back 0 home", then the page's own back); every frame with a
// change its depth ("depth 2"). haxe.Timer.delay in the browser's App.run:
// one made in the first frame, "timer 1" after 50 ms, then "timer 2" from a
// delay made in its callback.
class BackWeb {
	static function main() {
		var w = new Window("BackWeb", 200, 100);
		var depth = 0, last = -1;
		App.onBack = () -> {
			if (depth == 0) {
				Sys.println("back 0 home");
				return false;
			}
			depth--;
			App.backDepth = depth;
			Sys.println('back $depth');
			return true;
		};
		var timed = false;
		App.run(() -> {
			// (made in a frame, main returned: the loop's turns run it)
			if (!timed) {
				timed = true;
				haxe.Timer.delay(() -> {
					Sys.println("timer 1");
					haxe.Timer.delay(() -> Sys.println("timer 2"), 20);
				}, 50);
			}
			if (depth != last) {
				last = depth;
				Sys.println('depth $depth');
			}
			App.wait(0.05);
		}, e -> {
			if (e.kind == KeyDown && e.key == "d".code) {
				depth++;
				App.backDepth = depth;
			}
			if (e.kind == KeyDown && e.key == "h".code) {
				depth = 0;
				App.backDepth = 0;
			}
		});
	}
}
