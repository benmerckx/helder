import helder.os.App;
import helder.ui.*;
import helder.ui.draw.UiWindow;

// A touch fling in a drawn UI on Android (CI's android job: android-touch.sh
// swipes with adb and reads the lines from logcat): a header over a scroll
// box of 200 rows (helder.ui's UiWindow in NativeActivity's window). The
// swipe starts in the box and ends over the header: the finger is a
// pointer (PointerDown, PointerMove, PointerUp) and nothing else (no
// Scroll, no mouse event: a touch is its pointer's alone); ui's own drag
// (helder.ui.gesture.TouchScroll) scrolls the box at where it started, so
// it follows the finger the whole way (scrolled by the finger's travel
// when let go), then glides on. Checked once it settled; Back closes.
//   helder build tests/os/AndroidTouchTest.hx --target android-x86_64 -o AndroidTouchTest.apk
//   (the app org.helder.androidtouchtest)
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
		// (the finger: its pointer's events, where it went down and lifted
		// (pixels); the box when it went down and when let go, the frames it
		// moved after, its last change; what else came: scrolls, mouse events)
		var downs = 0, ups = 0, moves = 0, downY = 0.0, upY = 0.0, start = 0.0, released = -1.0, glides = 0, changed = 0.0, last = 0.0;
		var others = 0, ready = false, done = false;
		var diagAt = -100.0, diagLast = 0.0;
		App.run(() -> {
			var t0 = haxe.Timer.stamp();
			var drew = w.needsFrame();
			if (drew) w.frame() else App.wait(0.05);
			if (t0 - diagAt < 3) Sys.println('AndroidTouchTest: diag turn ${drew ? "frame" : "wait"} ${Math.round((haxe.Timer.stamp() - t0) * 1000)} ms, gap ${Math.round((t0 - diagLast) * 1000)}, scroll ${Math.round(list.scrollY)}');
			diagLast = t0;
			var now = haxe.Timer.stamp();
			if (!ready && w.device.width > 0 && list.height > 0) {
				ready = true;
				var k = w.renderer.scale;
				Sys.println('AndroidTouchTest: ready ${w.device.width}x${w.device.height}, scale $k, list at ${Math.round(list.absY * k)}');
			}
			if (list.scrollY != last) {
				last = list.scrollY;
				changed = now;
				if (released >= 0) glides++;
			}
			if (released >= 0 && !done && now - changed > 1.5) {
				done = true;
				var travel = (downY - upY) / w.renderer.scale;
				Sys.println('AndroidTouchTest: settled at ${Math.round(list.scrollY)}, let go at ${Math.round(released)}, $glides glide frames');
				check("the finger: its pointer's events alone", downs == 1 && ups == 1 && moves > 1 && others == 0,
					'$downs down, $moves moves, $ups up, $others scrolls or mouse events');
				check("the box followed the finger the whole drag", Math.abs(released - start - travel) < 2, 'scrolled ${Math.round(released - start)} of ${Math.round(travel)}');
				check("the fling glides on once let go", glides >= 3 && list.scrollY > released + 100, '${Math.round(released)} -> ${Math.round(list.scrollY)}');
				Sys.println('AndroidTouchTest: ' + (failed == 0 ? "ok" : '$failed FAILED'));
			}
		}, e -> {
			if (e.kind == PointerDown || e.kind == PointerMove || e.kind == PointerUp) {
				diagAt = haxe.Timer.stamp();
				var p = e.pointer;
				Sys.println('AndroidTouchTest: diag ${e.kind} y ${Math.round(p.y)} t ${Math.round(p.time)} samples ${p.samples}' + [for (i in 0...p.samples) ' ${Math.round(p.sampleY(i))}'].join(""));
			}
			switch e.kind {
				case PointerDown if (e.pointer.type == Touch):
					downs++;
					downY = e.pointer.y;
					start = list.scrollY;
				case PointerMove if (e.pointer.type == Touch):
					moves++;
				case PointerUp if (e.pointer.type == Touch):
					ups++;
					upY = e.pointer.y;
				case Scroll | MouseDown | MouseUp | MouseMove:
					others++;
				case _:
			}
			// (Back is Escape)
			if (e.kind == Close || (e.kind == KeyDown && e.key == 0xFF1B)) w.close() else w.handle(e);
			// (let go: the box as the release left it, before its glide's frames)
			if (e.kind == PointerUp && e.pointer.type == Touch && released < 0) {
				released = list.scrollY;
				Sys.println('AndroidTouchTest: let go at ${Math.round(released)} after $moves moves');
			}
		});
		Sys.println("AndroidTouchTest: done");
	}
}
