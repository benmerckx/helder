import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.ui.*;
import hxmc.ui.draw.*;
import hxmc.view.*;
import hxmc.view.Flow.*;
import hxmc.view.Reactive.*;
import hxmc.ui.widgets.Widgets.*;

// A list of ROWS rows in markup (a checkbox, a label, a number and a button
// each, in a scroll view), drawn headless: the time of each step of a UI's
// life (mounting, the first layout and frame, a change to one row, a scroll,
// an added row, frames with nothing changed), and checks that a change lays
// out again only what it touched (make ui-stress):
//   StressTest [rows]
class StressTest implements Markup {
	static inline var W = 800;
	static inline var H = 600;

	final rows:Array<Row> = [];
	final list = signal(new Array<Row>());

	function new(n:Int) {
		for (i in 0...n)
			rows.push(new Row(i));
		list.value = rows.copy();
	}

	function view():View
		// (min-height 0: as in CSS, a flex item holding a scroller is otherwise as tall as all its rows)
		return <view grow={1} min-height={0} padding={12} row-gap={8} font-family="DejaVu Sans" font-size={13} color="#18181b" background="#fafafa">
			<text font-size={18} font-weight={700}>{() -> list.value.length + " rows"}</text>
			<scroll tag="list" grow={1} min-height={0} row-gap={2} background="#ffffff" border-width={1} border-color="#e4e4e7" radius={8} padding={6}>
				<For each={list} render={(r:Row) -> <view direction="row" align-items="center" column-gap={10} padding="3 6" radius={4}
					background={() -> r.done.value ? "#eff6ff" : "#ffffff"}>
					<Checkbox checked={r.done}/>
					<text grow={1}>{() -> r.label.value}</text>
					<text color="#71717a">{"#" + r.id}</text>
					<Button label="Open"/>
				</view>}/>
			</scroll>
		</view>;

	static function count(n:Node):Int {
		var c = 1;
		for (k in n.children)
			c += count(k);
		return c;
	}

	static var failed = 0;

	static function check(what:String, ok:Bool) {
		if (!ok) {
			failed++;
			Sys.println('StressTest: FAIL: $what');
		}
	}

	static function main() {
		var n = Sys.args().length > 0 ? Std.parseInt(Sys.args()[0]) : 1000;
		var device = Device.create(Surface.headless(W, H));
		var ui = new Ui(new DrawText(), W, H);
		ui.theme = Plain.sheet;
		var r = new Renderer(device);
		var pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 1, 1)}]};
		var pixels = Bytes.alloc(W * H * 4);
		var times:Array<String> = [];
		var t = haxe.Timer.stamp();
		function lap(what:String) {
			var now = haxe.Timer.stamp();
			times.push('$what ${Math.round((now - t) * 10000) / 10}');
			t = now;
		}
		function frame(?read:Bool) {
			ui.update();
			var enc = device.beginFrame();
			enc.beginPass(pass);
			r.begin(W, H);
			ui.paint(r);
			r.end(enc);
			enc.endPass();
			if (read) device.readPixels(pixels);
			device.endFrame();
		}
		var app = new StressTest(n);
		lap("start");
		times.resize(0);
		// (the fonts found and loaded: once, apart from the layout)
		ui.text.layout("fonts", new Font("DejaVu Sans", 13, 400, false, 1.25), Math.NaN);
		lap("fonts");
		Render.render(app.view(), ui.root);
		lap("mount");
		ui.update();
		lap("layout");
		frame(true);
		lap("frame");
		var nodes = count(ui.root);
		check("one row of nodes per item", nodes > n * 8);
		var list = ui.root.find("list");
		// a frame with nothing changed: nothing laid out
		frame(true);
		lap("idle frame");
		// one row changed
		app.rows[5].done.value = true;
		lap("toggle");
		frame(true);
		lap("frame after toggle");
		app.rows[7].label.value = "A longer label, typed into row seven";
		lap("relabel");
		frame(true);
		lap("frame after relabel");
		// scrolled half way
		ui.wheel(400, 300, 0, list.contentHeight / 2);
		frame(true);
		lap("scrolled frame");
		check("scrolled", list.scrollY > 0);
		// a row added at the end
		app.list.value = app.list.value.concat([new Row(n)]);
		lap("append");
		frame(true);
		lap("frame after append");
		check("the row added", count(ui.root) > nodes);
		// frames with nothing changed: the update, the paint (vertices) and the GPU's part
		var tu = 0.0, tp = 0.0, tg = 0.0;
		for (i in 0...20) {
			var a = haxe.Timer.stamp();
			ui.update();
			var b = haxe.Timer.stamp();
			var enc = device.beginFrame();
			enc.beginPass(pass);
			r.begin(W, H);
			ui.paint(r);
			var c = haxe.Timer.stamp();
			r.end(enc);
			enc.endPass();
			device.endFrame();
			device.readPixels(pixels);
			var d = haxe.Timer.stamp();
			tu += b - a;
			tp += c - b;
			tg += d - c;
		}
		inline function ms(v:Float)
			return Math.round(v / 20 * 10000) / 10;
		times.push('steady frame: update ${ms(tu)}, paint ${ms(tp)}, gpu ${ms(tg)}');
		// the accessibility tree a window builds each frame for assistive technology, and its changes
		var ta = 0.0, prev = ui.accessTree();
		for (i in 0...20) {
			var a = haxe.Timer.stamp();
			var t = ui.accessTree();
			t.changes(prev);
			prev = t;
			ta += haxe.Timer.stamp() - a;
		}
		times.push('access tree ${ms(ta)}');
		Sys.println('StressTest: $n rows, $nodes nodes; ms: ' + times.join(", "));
		device.dispose();
		Sys.println("StressTest: " + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}

class Row {
	public final id:Int;
	public final label:Signal<String>;
	public final done = signal(false);

	public function new(id:Int) {
		this.id = id;
		label = signal("Row " + id + ": " + ["alpha", "beta", "gamma", "delta", "epsilon"][id % 5] + " item");
	}
}
