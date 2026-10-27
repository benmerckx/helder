import helder.os.App;
import helder.os.Event.Mods;
import helder.ui.*;
import helder.ui.draw.UiWindow;

// A touch fling in a drawn UI on Android (CI's android job: android-touch.sh
// swipes with adb and reads the lines from logcat): a header over a scroll
// box of 200 rows (helder.ui's UiWindow in NativeActivity's window). The
// swipe starts in the box and ends over the header: the drag's scrolls
// (Mods.TOUCH) all come at where it started (helder.os.TouchDrag), so the box
// follows the finger the whole way (it scrolled by all of them when let
// go); the release is a scroll of nothing without Mods.TOUCH, then the
// glide's scrolls carry the box on. Checked once it settled; Back closes.
//   haxe -lib helder -cp tests/os -main AndroidTouchTest
//     --custom-target hxmc=AndroidTouchTest.apk -D hxmc.target=android-x86_64 -D hxmc.android-package=org.hxmc.touchtest
class AndroidTouchTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail:String) {
		if (!ok) failed++;
		Sys.println('AndroidTouchTest: ${ok ? "ok" : "FAIL"}: $what ($detail)');
	}

	static function main() {
		Sys.println("AndroidTouchTest: start");
		var w = new UiWindow("AndroidTouchTest", 0, 0);
		var root = w.root;
		root.style.set({direction: Column});
		var header = new Node("header");
		header.style.set({height: 160, shrink: 0, background: Color.rgb(0x18181B)});
		root.append(header);
		var list = new Node("list");
		list.style.set({grow: 1, minHeight: 0, overflow: Scroll});
		for (i in 0...200) {
			var row = new Node("row" + i);
			row.style.set({height: 48, shrink: 0, background: Color.rgb(i % 2 == 0 ? 0xF4F4F5 : 0xD4D4D8)});
			list.append(row);
		}
		root.append(list);
		// (the touch scrolls: how many, where, by how much in all (points);
		// the box when let go, its glide's scrolls, its last change)
		var touches = 0, at = "", sum = 0.0, start = 0.0, released = -1.0, glides = 0, changed = 0.0, last = 0.0, ready = false, done = false;
		App.run(() -> {
			if (w.needsFrame()) w.frame() else App.wait(0.05);
			var now = haxe.Timer.stamp();
			if (!ready && w.device.width > 0 && list.height > 0) {
				ready = true;
				var k = w.renderer.scale;
				Sys.println('AndroidTouchTest: ready ${w.device.width}x${w.device.height}, scale $k, list at ${Math.round(list.absY * k)}');
			}
			if (list.scrollY != last) {
				last = list.scrollY;
				changed = now;
			}
			if (released >= 0 && !done && now - changed > 1.5) {
				done = true;
				Sys.println('AndroidTouchTest: settled at ${Math.round(list.scrollY)}, let go at ${Math.round(released)}, $glides glide scrolls');
				check("the drag's scrolls at where it started", touches > 1 && at != "moved", '$touches at $at');
				check("the box followed the finger the whole drag", Math.abs(released - start - sum) < 2, 'scrolled ${Math.round(released - start)} of ${Math.round(sum)}');
				check("the fling glides on once let go", glides >= 3 && list.scrollY > released + 100, '${Math.round(released)} -> ${Math.round(list.scrollY)}');
				Sys.println('AndroidTouchTest: ' + (failed == 0 ? "ok" : '$failed FAILED'));
			}
		}, e -> {
			if (e.kind == Scroll) {
				if (e.mods & Mods.TOUCH != 0) {
					if (touches == 0) start = list.scrollY;
					touches++;
					var p = '${e.x},${e.y}';
					if (at == "") at = p else if (at != p) at = "moved";
					sum += e.deltaY / w.renderer.scale;
				} else if (e.deltaX == 0 && e.deltaY == 0) {
					if (touches > 0 && released < 0) {
						released = list.scrollY;
						Sys.println('AndroidTouchTest: let go at ${Math.round(released)} after $touches touch scrolls');
					}
				} else if (released >= 0) glides++;
			}
			// (Back is Escape)
			if (e.kind == Close || (e.kind == KeyDown && e.key == 0xFF1B)) w.close() else w.handle(e);
		});
		Sys.println("AndroidTouchTest: done");
	}
}
