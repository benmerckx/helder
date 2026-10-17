import hxmc.os.*;
import hxmc.os.x11.Xlib;
import hxmc.unsafe.*;

// hxmc.os's text input on X11 (make ui-draw-check, under Xvfb): key presses
// typed through the input method (Xutf8LookupString), with the keyboard's
// last three keycodes given other symbols (XChangeKeyboardMapping, which
// every client hears of: MappingNotify): a Cyrillic letter (beyond Latin-1)
// and a dead key's compose sequence (dead_acute then e: one "é").
//   TextInputTest
class TextInputTest {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('TextInputTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var w = new Window("TextInputTest", 64, 64);
		var d = w.surface.display, id = w.surface.handle.toI64();
		var last = Arena.scopedValue(a -> {
			var lo:Ptr<Int32> = a.alloc(4), hi:Ptr<Int32> = a.alloc(4);
			Xlib.XDisplayKeycodes(d, lo, hi);
			hi.value;
		});
		var first = last - 2;
		// Cyrillic_a, dead_acute, e
		Arena.scoped(a -> {
			var ks:Ptr<Int64> = a.alloc(24);
			ks[0] = 0x6c1;
			ks[1] = 0xfe51;
			ks[2] = 0x65;
			Xlib.XChangeKeyboardMapping(d, first, 1, ks, 3);
		});
		Xlib.XSync(d, 0);
		function press(code:Int)
			Arena.scoped(a -> {
				var raw = a.alloc(X.EVENT_SIZE);
				for (i in 0...X.EVENT_SIZE)
					(raw : Ptr<UInt8>)[i] = 0;
				var k:Ptr<XKeyEvent> = raw;
				k.value.type = X.KeyPress;
				k.value.display = d;
				k.value.window = id;
				k.value.keycode = code;
				k.value.same_screen = 1;
				Xlib.XSendEvent(d, id, 0, X.KeyPressMask, raw);
			});
		var typed = [];
		var keys = 0;
		var sent = false;
		var start = haxe.Timer.stamp();
		App.run(() -> {
			if (!sent) {
				// (after the MappingNotify's arrival: the next frame)
				sent = true;
				press(first);
				press(first + 1);
				press(first + 2);
				Xlib.XFlush(d);
			}
			if (typed.length >= 2 || haxe.Timer.stamp() - start > 5) w.close();
			App.wait(0.01);
		}, e -> switch e.kind {
			case TextInput: typed.push(e.text);
			case KeyDown: keys++;
			case _:
		});
		check("a Cyrillic letter typed", typed[0] == "а", typed[0]);
		check("a dead key composed with the next key: one character", typed[1] == "é", typed[1]);
		check("nothing else typed", typed.length == 2, typed.join("|"));
		// (the dead key goes to the input method, not the program)
		check("the keys the program sees", keys == 2, '$keys');
		Sys.println('TextInputTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
