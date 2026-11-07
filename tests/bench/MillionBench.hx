import CodeBench.NullCanvas;
import haxe.Timer;
import helder.ui.*;
import helder.ui.draw.DrawText;
import helder.view.Render;

// helder.ui's VirtualList's own work a frame, without the GPU renderer:
// examples/million (a million messages of their own heights) in a Ui of
// helder.text's engine painted into a canvas that draws nothing, natively,
// each frame timed and its GC bytes counted (GcStats): the first frame,
// the wheel over rows made the first time and over rows made before (back
// and forth within the rows kept), jumps far into the list, three rows put
// in above the view (the list's diff and splice; the program's copy of a
// million items timed apart), the keyboard's Down, a frame with nothing
// changed; then what it holds (the height index's bytes, the rows made).
//   MillionBench
class MillionBench {
	static var ui:Ui;
	static final canvas = new NullCanvas();

	static function main() {
		var text = new DrawText();
		// (the fonts and the program warmed: a Ui of ten rows drawn first, let go)
		ui = new Ui(text, 480, 640);
		var warm = new Million(10);
		var dispose = Render.render(warm.view(), ui.root);
		ui.update();
		ui.paint(canvas);
		dispose();
		ui = new Ui(text, 480, 640);
		var t0 = Timer.stamp(), b0 = GcStats.bytes();
		var app = new Million();
		var made = Timer.stamp();
		Sys.println('million-bench: a million items (the program\'s array): ${ms(made - t0)} ms, ${Std.int(GcStats.bytes() - b0)} GC bytes');
		b0 = GcStats.bytes();
		Render.render(app.view(), ui.root);
		ui.update();
		ui.paint(canvas);
		var list:VirtualScroll = cast ui.root.find("rows");
		Sys.println('million-bench: the first frame (the view made, ${list.rows().length} rows made and measured, laid out, painted): ${ms(Timer.stamp() - made)} ms, ${Std.int(GcStats.bytes() - b0)} GC bytes');
		// (warm)
		for (_ in 0...30)
			wheel(40);
		for (_ in 0...30)
			wheel(-40);
		run("wheel, rows made the first time (60 px a frame)", 400, () -> wheel(60));
		// (back and forth over 1,200 px: the rows kept)
		var k = 0;
		for (_ in 0...40)
			wheel(k++ % 40 < 20 ? 60 : -60);
		run("wheel over rows made before (back and forth)", 400, () -> wheel(k++ % 40 < 20 ? 60 : -60));
		run("  the same, the frame's update alone (no paint)", 400, () -> {
			ui.wheel(240, 300, 0, k++ % 40 < 20 ? 60 : -60);
			Clock.tick(Clock.now + 1 / 60);
			ui.update();
		});
		run("  the same, scrolled without an event: the update alone", 400, () -> {
			ui.scrollTo(list, 0, list.scrollY + (k++ % 40 < 20 ? 60 : -60));
			Clock.tick(Clock.now + 1 / 60);
			ui.update();
		});
		run("  scrolled by 60 px without an event", 400, () -> {
			ui.scrollTo(list, 0, list.scrollY + (k++ % 40 < 20 ? 60 : -60));
			frame();
		});
		var r = 12345;
		run("a jump far into the list (scrollToIndex, a frame)", 100, () -> {
			r = (r * 1103515245 + 12345) & 0x7fffffff;
			list.scrollToIndex(r % list.count, "start");
			frame();
		});
		run("a jump to the last row (End: focusIndex, a frame)", 50, () -> {
			list.focusIndex(0);
			frame();
			list.focusIndex(list.count - 1);
			frame();
		}, 2);
		list.scrollToIndex(500000, "start");
		frame();
		var copy = [];
		run("  the program's copy of a million items with three put in", 20, () -> {
			var next = app.items().copy();
			for (j in 0...3)
				next.insert(list.firstVisible(), 2000000 + j);
			copy = next;
		});
		var extra = 3000000;
		run("three rows put in above the view (the diff, the splice, a frame)", 50, () -> {
			app.items(copy);
			frame();
		}, 1, () -> {
			var next = app.items().copy();
			var at = list.firstVisible();
			for (_ in 0...3)
				next.insert(at, extra++);
			copy = next;
		});
		list.focusIndex(list.firstVisible());
		frame();
		run("the keyboard's Down (the focus moved, a frame)", 300, () -> {
			ui.keyDown(Key.DOWN, 0);
			ui.keyUp(Key.DOWN, 0);
			frame();
		});
		run("a frame with nothing changed", 200, () -> frame());
		run("  its update alone", 200, () -> ui.update());
		run("  its paint alone", 200, () -> ui.paint(canvas));
		run("  the list's settle alone", 200, () -> @:privateAccess list.settle());
		run("  the list's place alone", 200, () -> @:privateAccess list.place());
		var nodes = 0;
		function count(n:Node) {
			nodes++;
			for (c in n.children)
				count(c);
		}
		count(ui.root);
		Sys.println('million-bench: ${list.count} rows, ${list.heights.measuredCount} measured; the height index ${list.heights.bytes()} bytes (${Math.round(list.heights.bytes() / list.count * 100) / 100} a row); ${list.rows().length} rows made (${list.end - list.first} in the window), ${nodes} nodes in the tree; ${list.made} rows made in all, ${list.dropped} let go');
	}

	static function wheel(dy:Float) {
		ui.wheel(240, 300, 0, dy);
		frame();
	}

	static function frame() {
		Clock.tick(Clock.now + 1 / 60);
		ui.update();
		ui.paint(canvas);
	}

	// (n runs of f, each timed alone; before, untimed, before each)
	static function run(name:String, n:Int, f:Void->Void, per = 1, ?before:Void->Void) {
		var times = [], bytes = [];
		var gc0 = GcStats.collections();
		for (_ in 0...n) {
			if (before != null) before();
			var b0 = GcStats.bytes(), t0 = Timer.stamp();
			f();
			times.push((Timer.stamp() - t0) * 1000 / per);
			bytes.push((GcStats.bytes() - b0) / per);
		}
		times.sort(Reflect.compare);
		bytes.sort(Reflect.compare);
		inline function at(a:Array<Float>, p:Float):Float
			return a[Std.int(Math.min(a.length - 1, Math.floor(p * (a.length - 1) + 0.5)))];
		Sys.println('million-bench: ${StringTools.rpad(name, " ", 62)} median ${round(at(times, 0.5))} ms, p95 ${round(at(times, 0.95))} ms, max ${round(times[times.length - 1])} ms; '
			+ '${Std.int(at(bytes, 0.5))} GC bytes a frame (max ${Std.int(bytes[bytes.length - 1])}), ${GcStats.collections() - gc0} GCs');
	}

	static inline function ms(s:Float):Float
		return round(s * 1000);

	static inline function round(x:Float):Float
		return Math.round(x * 1000) / 1000;
}
