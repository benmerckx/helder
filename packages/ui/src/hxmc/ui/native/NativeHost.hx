package hxmc.ui.native;

import haxe.ds.ObjectMap;
import hxmc.ui.*;
import hxmc.unsafe.Mem;

// A window of platform controls: a Ui whose Controls are the platform's
// widgets and whose TextNodes are its labels, measured by the platform,
// laid out by hxmc.ui's flexbox and placed absolutely in the window
// (the design's native backend: hxmc/UI.md, section 6). Plain nodes only
// lay out (their paint properties are not drawn); scrolling is not done.
// step lays out and brings the widgets in step with the tree after a
// change; run is the loop (in the browser it returns, and
// requestAnimationFrame runs the steps). The backends: GTK 3 on Linux
// (glibc mode), Win32's controls on Windows, AppKit's on macOS, the DOM in
// the browser.
class NativeHost {
	public final backend:NativeBackend;
	public final ui:Ui;
	public var closed(default, null) = false;

	public var root(get, never):Node;

	inline function get_root()
		return ui.root;

	// the widgets by node (a Control, or a TextNode: a label), and what each label shows
	final widgets = new ObjectMap<Node, Int>();
	final labels = new Map<Int, String>();
	// each control's natural size when last measured (a state, a theme may change it)
	final natural = new Map<Int, String>();
	var resized = true;

	static final hosts:Array<NativeHost> = [];

	public function new(title:String, width:Int, height:Int, ?backend:NativeBackend) {
		this.backend = backend != null ? backend : platform();
		this.backend.openWindow(title, width, height, this);
		ui = new Ui(new NativeText(this.backend), this.backend.windowWidth(), this.backend.windowHeight());
		hosts.push(this);
	}

	// the platform's backend (none yet on Windows and macOS)
	// (one chain of constant tests: only the target's branch is compiled)
	static function platform():NativeBackend {
		return if (Mem.os() == 3) new hxmc.ui.native.dom.DomBackend() else if (Mem.os() == 1) new hxmc.ui.native.appkit.AppKitBackend() else
			if (Mem.os() == 2) new hxmc.ui.native.win32.Win32Backend() else new hxmc.ui.native.gtk.GtkBackend();
	}

	// the backend of the host a Ui belongs to (null: none)
	public static function backendFor(ui:Null<Ui>):Null<NativeBackend> {
		var h = hostFor(ui);
		return h == null ? null : h.backend;
	}

	public static function hostFor(ui:Null<Ui>):Null<NativeHost> {
		if (ui == null) return null;
		for (h in hosts)
			if (h.ui == ui) return h;
		return null;
	}

	// the platform resized the window (also while it opens: Win32's WM_SIZE,
	// before the Ui is made)
	@:allow(hxmc.ui.native) function windowResized() {
		resized = true;
		if (ui != null) ui.requestFrame();
	}

	@:allow(hxmc.ui.native) function windowClosed() {
		closed = true;
		hosts.remove(this);
	}

	// the widget of a Control, made (and given its properties) when it has none
	public function ensure(c:Control):Int {
		var h = widgets.get(c);
		if (h == null) {
			h = backend.create(c);
			widgets.set(c, h);
			c.setHandle(h);
			c.stale = true;
		}
		if (c.stale) {
			backend.update(h, c);
			c.stale = false;
		}
		return h;
	}

	// lays the tree out and brings the widgets in step, when something changed
	public function step() {
		if (closed) return;
		if (resized) {
			ui.resize(backend.windowWidth(), backend.windowHeight());
			resized = false;
		}
		if (!ui.needsFrame) return;
		ui.update();
		sync();
		ui.paint(new NoCanvas());
	}

	function sync() {
		var seen = new ObjectMap<Node, Bool>();
		function walk(n:Node) {
			if (n.style.display == None) return;
			if (Std.isOfType(n, Control)) {
				var c:Control = cast n;
				var h = ensure(c);
				backend.place(h, n.absX, n.absY, n.width, n.height);
				seen.set(n, true);
				// (measured again: a size changed lays the tree out again)
				var m = backend.measure(c, Math.NaN), key = m.width + "x" + m.height;
				var was = natural.get(h);
				natural.set(h, key);
				if (was != null && was != key) c.markDirty();
			} else if (Std.isOfType(n, TextNode)) {
				var t:TextNode = cast n;
				var h = widgets.get(n);
				if (h == null) {
					h = backend.create(n);
					widgets.set(n, h);
				}
				var f = t.font(), col = t.textColor();
				var key = t.text + "\x00" + f.family + f.size + f.weight + f.italic + (col : Int) + t.textAlign();
				if (labels.get(h) != key) {
					backend.update(h, n);
					labels.set(h, key);
				}
				var be = n.style.borderEdges;
				backend.place(h, n.absX + be.left + n.style.padding.left, n.absY + be.top + n.style.padding.top,
					Math.max(0, n.width - be.horizontal - n.style.padding.horizontal), Math.max(0, n.height - be.vertical - n.style.padding.vertical));
				seen.set(n, true);
			}
			for (c in n.children)
				walk(c);
		}
		walk(ui.root);
		for (n in [for (k in widgets.keys()) k])
			if (!seen.exists(n)) {
				var h = widgets.get(n);
				backend.destroy(h);
				widgets.remove(n);
				labels.remove(h);
				natural.remove(h);
				if (Std.isOfType(n, Control)) (cast n : Control).setHandle(0);
			}
	}

	// the loop: the platform's events, a step after them, until the window closes
	public function run() {
		if (Mem.os() == 3) {
			hxmc.ui.native.dom.DomBackend.start(this);
			return;
		}
		while (!closed) {
			if (!backend.pump(false)) break;
			step();
			if (!ui.needsFrame && !Clock.active && !backend.pump(true)) break;
		}
	}

	public function close() {
		if (closed) return;
		backend.closeWindow();
		windowClosed();
	}
}

// (paint's frame done: the platform draws)
private class NoCanvas implements Canvas {
	public function new() {}

	public function translate(dx:Float, dy:Float) {}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {}

	public function popClip() {}

	public function pushOpacity(alpha:Float) {}

	public function popOpacity() {}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {}

	public function popTransform() {}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges) {}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners) {}

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {}
}
