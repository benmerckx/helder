package hxmc.ui.native.dom;

import hxmc.ui.*;
import hxmc.ui.native.*;
import hxmc.unsafe.*;

// NativeBackend in the browser (WebAssembly): the page's own controls
// (button, input, progress; a span for a label) placed absolutely in a
// container (WebNative, packages/ui/imports.mjs), measured by the browser.
// The browser owns the loop: start runs the hosts' steps on
// requestAnimationFrame, their events drained first.
class DomBackend implements NativeBackend {
	static final hosts:Array<NativeHost> = [];

	final nodes = new Map<Int, Node>();
	var host:Null<NativeHost>;
	var container = 0;
	var open = false;
	var lastWidth = 0;
	var lastHeight = 0;

	public function new() {}

	public function openWindow(title:String, width:Int, height:Int, host:NativeHost) {
		this.host = host;
		container = Arena.scopedValue(a -> WebNative.native_open(a.cstring(title), width, height));
		open = true;
		lastWidth = windowWidth();
		lastHeight = windowHeight();
	}

	public function closeWindow() {
		if (!open) return;
		open = false;
		WebNative.native_destroy(container);
	}

	public function windowWidth():Int
		return WebNative.native_width(container);

	public function windowHeight():Int
		return WebNative.native_height(container);

	public function create(n:Node):Int {
		var kind:Int = Std.isOfType(n, Control) ? (cast n : Control).kind : (ControlKind.Label : Int);
		var h = WebNative.native_create(container, kind);
		nodes.set(h, n);
		return h;
	}

	public function update(h:Int, n:Node) {
		var p:Dynamic = {};
		if (Std.isOfType(n, Control)) {
			var c:Control = cast n;
			p = {
				text: c.text,
				placeholder: c.placeholder,
				checked: c.checked,
				value: c.value,
				min: c.min,
				max: c.max,
				step: c.step,
				enabled: c.enabled
			};
		} else if (Std.isOfType(n, TextNode)) {
			var t:TextNode = cast n;
			var col = t.textColor();
			p = {
				text: t.text,
				font: font(t.font()),
				color: 'rgba(${col.r}, ${col.g}, ${col.b}, ${Math.round(col.a / 255 * 1000) / 1000})',
				align: switch t.textAlign() {
					case Center: "center";
					case Right: "right";
					case _: "left";
				}
			};
		}
		var json = haxe.Json.stringify(p);
		Arena.scoped(a -> WebNative.native_update(h, a.cstring(json)));
	}

	static function font(f:Font):String
		return (f.italic ? "italic " : "") + f.weight + " " + f.size + "px \"" + f.family + "\"";

	public function place(h:Int, x:Float, y:Float, width:Float, height:Float)
		WebNative.native_place(h, x, y, width, height);

	public function destroy(h:Int) {
		WebNative.native_destroy(h);
		nodes.remove(h);
	}

	public function measure(c:Control, width:Float):Size
		return Arena.scopedValue(a -> {
			var p:Ptr<Float> = a.alloc(16);
			WebNative.native_measure(c.handle, p);
			new Size(p[0], p[1]);
		});

	public function measureText(text:String, f:Font, maxWidth:Float):Size
		return Arena.scopedValue(a -> {
			var p:Ptr<Float> = a.alloc(16);
			WebNative.native_measure_text(a.cstring(text), a.cstring(font(f)), Math.isNaN(maxWidth) ? -1 : maxWidth, p);
			new Size(Math.ceil(p[0]), Math.ceil(p[1]));
		});

	public function pump(block:Bool):Bool {
		if (!open) return false;
		Arena.scoped(a -> {
			var p:Ptr<Int32> = a.alloc(12);
			while (WebNative.native_next(p) != 0) {
				var n = nodes.get(p[0]);
				if (!Std.isOfType(n, Control)) continue;
				var c:Control = cast n;
				switch p[1] {
					case 0: c.platformClick();
					case 1: c.platformText(take(p[2]));
					case 2: c.platformSubmit();
					case 3: c.platformChecked(p[2] != 0);
					case 4: c.platformValue(Std.parseFloat(take(p[2])));
					case _:
				}
			}
		});
		// (the container resized by the page)
		var w = windowWidth(), h = windowHeight();
		if ((w != lastWidth || h != lastHeight) && host != null) {
			lastWidth = w;
			lastHeight = h;
			@:privateAccess host.windowResized();
		}
		return open;
	}

	static function take(h:Int):String {
		var n = WebNative.native_string_length(h);
		var b = haxe.io.Bytes.alloc(n);
		Arena.scoped(a -> {
			var p = a.alloc(n + 1, 1);
			WebNative.native_string_take(h, p);
			BytesPtr.copyIn(b, 0, p, n);
		});
		return b.toString();
	}

	// the browser's loop for a host: its events, then a step, each animation frame
	public static function start(host:NativeHost) {
		hosts.push(host);
		if (hosts.length == 1) WebNative.native_start(Callback.addr(frame));
	}

	@:hxmc.callback static function frame():Int {
		for (h in hosts.copy()) {
			if (h.closed || !h.backend.pump(false)) {
				hosts.remove(h);
				continue;
			}
			h.step();
		}
		Sys.stdout().flush();
		return hosts.length > 0 ? 1 : 0;
	}
}
