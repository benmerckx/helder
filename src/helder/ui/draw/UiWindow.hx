package helder.ui.draw;

import helder.gfx.*;
import helder.os.App;
import helder.os.Event as OsEvent;
import helder.ui.*;
import hxmc.unsafe.*;
import helder.ui.view.UiView;
import helder.view.graph.Graph;
import helder.view.Render;
import helder.view.RootView;

// <Surface>'s props (UiWindow.Surface)
typedef SurfaceProps = {
	// the window's title, its size in points (on the web without a size: the
	// page filled, or the canvas the page gives, at the size its styles make;
	// natively 800 x 600), the ui's theme and background: values or reactive
	// (a signal, a memo, a hole that reads: Read), followed
	?title:helder.view.graph.Read<String>,
	?width:helder.view.graph.Read<Int>,
	?height:helder.view.graph.Read<Int>,
	?theme:helder.view.graph.Read<Dynamic>,
	?background:helder.view.graph.Read<Dynamic>,
	// dark or light (default: the system's appearance, UiWindow.dark)
	?dark:helder.view.graph.Read<Bool>,
	// the window closed by its user (default: closed)
	?onClose:Void->Void,
	// the UiWindow, once made
	?ref:UiWindow->Void,
	// its frames multisampled, 4 samples a pixel (default true; false: one)
	?antialias:Bool,
	?children:UiView
};

// A window showing a UI tree drawn with the GPU: an helder.os Window, its
// gfx Device, a Renderer and the Ui (root: the tree's root node, in the
// window's points). The window's events become the Ui's (pointer, wheel,
// keys, text); a frame lays the tree out and draws it, when there is
// something new to draw (needsFrame: the Ui asked for one, the window was
// resized or lost its pixels). run() is the app loop for every UiWindow
// open, which sleeps while none has a frame to draw. In the browser each
// frame's accessibility tree goes to the mirror in the canvas (WebAccess:
// load src/helder/ui/imports.mjs), on macOS to NSAccessibility (MacAccess),
// on Windows to UI Automation (WinAccess), on Linux to AT-SPI (LinuxAccess),
// and the actions asked for come back.
//
// In markup (helder.view) <Surface> is the root ui draws into: a UiWindow,
// its children ui's markup rendered into its root; several make several
// windows; run(content) opens them (Render.open) and runs the loop:
//
//   UiWindow.run(<Surface title="Todo" width={480} height={560} theme={sheet}>
//     <Todo/>
//   </Surface>);
//
// In a page's markup (helder.web's DOM or static renderer) a <Surface> is
// helder.web's: a canvas running a wasm program whose root is this one.
class UiWindow {
	public final window:helder.os.Window;
	public final device:Device;
	public final renderer:Renderer;
	public final ui:Ui;
	public var background:Color = Color.rgb(0xF4F4F5);
	public var onClose:Null<Void->Void>;
	// after each frame is drawn
	public var onFrame:Null<Void->Void>;
	// when set, the next frame's pixels are read into it before they are
	// presented (RGBA8, rows top to bottom: tests and screenshots)
	public var capture:Null<haxe.io.Bytes>;

	// how long the loop sleeps at most with nothing to draw (seconds): what
	// changes the UI from outside its events shows within it
	public static var idleWait = 0.1;
	// whether the system's appearance is dark (App.prefersDark), asked again
	// every second while the loop runs; each window's Ui.dark follows it
	public static final dark:helder.view.graph.Signal<Bool> = Graph.signalOf(App.prefersDark(), {ownedWrite: true});
	static var darkAsked = 0.0;

	static final open:Array<UiWindow> = [];
	// the last frame drawn: its size and scale (a change needs a frame)
	var redraw = true;
	var drawnW = 0;
	var drawnH = 0;
	var drawnScale = 0.0;
	// the tree sent to the browser's mirror last
	var access:Null<helder.ui.access.AccessTree>;
	// macOS's adapter (a MacAccess; Any: the other targets never reach its type)
	var macAccess:Any = null;
	// Windows' (a WinAccess)
	var winAccess:Any = null;
	// Linux's (a LinuxAccess)
	var linuxAccess:Any = null;
	// the text input area last given to the window ("": off)
	var typing = "";
	final pass:PassDesc = {colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]};
	var buttons = 0;

	// (antialias: the device's frames multisampled, 4 samples a pixel, where the GPU has them)
	public function new(title:String, width:Int, height:Int, ?text:TextEngine, antialias = true) {
		window = new helder.os.Window(title, width, height);
		// (shortcuts labelled as macOS's menus do)
		Shortcut.mac = Mem.os() == 1;
		// (Android: text fields get the soft keyboard and the input method)
		if (Mem.target() >= 9) helder.os.android.TextInput.enable();
		device = Device.create(window.surface, {antialias: antialias});
		renderer = new Renderer(device);
		ui = new Ui(text == null ? new DrawText() : text, width, height);
		ui.clipboard = new SystemClipboard(window);
		ui.dark = dark.peek();
		// (touches and pens as pointers of their own: ui taps and scrolls them itself)
		helder.os.Pointers.emulate = false;
		// (a touch drag the program's where it scrolls something: the page's otherwise)
		window.scrollsAt = (x, y, dx, dy) -> ui.scrollsAt(x / renderer.scale, y / renderer.scale, dx / renderer.scale, dy / renderer.scale);
		// (the browser's own views: native text editors over the canvas)
		if (Mem.os() == 3) ui.platform = WebMirror.views(window.surface.handle.toI64().toInt());
		// (Windows': EDIT controls over the window)
		else if (Mem.os() == 2) ui.platform = new WinViews(window.surface.handle, ui, () -> renderer.scale);
		// (macOS': NSTextFields over the window; not iOS's, whose Mem.os() is macOS's too: no AppKit there)
		else if (Mem.platform() >= 1) {} else if (Mem.os() == 1) ui.platform = new MacViews(window.surface.handle, ui);
		open.push(this);
		#if hxmc.dev_host
		// (helder dev's host, at a hand-over: what the system keeps of this build's code given back)
		helder.dev.Hot.onDispose(handOver);
		#end
	}

	#if hxmc.dev_host
	// (handed over: the window the host's, not closed with its <Surface>'s owner after it)
	var handedOver = false;

	// the native views and the accessibility adapters released (the window
	// and the GPU device stay, the host's): their callbacks are this build's
	// code, which the host unloads; the next build makes its own
	function handOver() {
		handedOver = true;
		if (Mem.platform() >= 1) {} else if (Mem.os() == 1) {
			if (macAccess != null) (cast macAccess : MacAccess).dispose();
			if (ui.platform != null) (cast ui.platform : MacViews).dispose();
		}
		if (Mem.os() == 2) {
			if (winAccess != null) (cast winAccess : WinAccess).dispose();
			if (ui.platform != null) (cast ui.platform : WinViews).dispose();
		}
		macAccess = winAccess = null;
	}
	#end

	public var root(get, never):Node;

	inline function get_root()
		return ui.root;

	// there is something new to draw
	public function needsFrame():Bool
		return redraw || ui.needsFrame || Clock.active || capture != null || device.width != drawnW || device.height != drawnH || window.scale != drawnScale;

	// draws a frame (the loop calls it when needsFrame): the clock ticked
	// first (now: what the frame's events started, Ui.now's, is not after
	// it, as the vsync's time App.frame.time may be)
	public function frame() {
		Clock.tick(haxe.Timer.stamp());
		var s = window.scale;
		renderer.scale = device.width / Math.max(1, Math.round(device.width / s));
		ui.resize(device.width / renderer.scale, device.height / renderer.scale);
		ui.scale = renderer.scale;
		safeArea();
		ui.update();
		// (the clock ticked, nothing changed: the last frame stands, as drawn;
		// an animation off screen, a timer's wait)
		if (!redraw && !ui.needsFrame && capture == null && device.width == drawnW && device.height == drawnH && s == drawnScale) {
			updateTextInput();
			return;
		}
		var enc = device.beginFrame();
		if (enc == null) return;
		redraw = false;
		drawnW = device.width;
		drawnH = device.height;
		drawnScale = s;
		var c = pass.colors[0].clear;
		@:privateAccess {
			c.r = background.r / 255;
			c.g = background.g / 255;
			c.b = background.b / 255;
		}
		// (painted first: the passes a texture drawn needs, a <Scene>'s, recorded before the frame's)
		renderer.begin(device.width, device.height);
		ui.paint(renderer);
		renderer.prepare(enc);
		enc.beginPass(pass);
		renderer.end(enc);
		enc.endPass();
		if (capture != null) {
			device.readPixels(capture);
			capture = null;
		}
		device.endFrame();
		updateTextInput();
		sendAccess();
		if (onFrame != null) onFrame();
	}

	// the window's safe area in UI pixels: the Ui's, and markup's
	// env(safe-area-inset-*) from the first window's (SafeArea), when it changed
	function safeArea() {
		var k = renderer.scale, s = ui.safeArea;
		var t = window.safeTop / k, r = window.safeRight / k, b = window.safeBottom / k, l = window.safeLeft / k;
		if (s.top != t || s.right != r || s.bottom != b || s.left != l) {
			ui.safeArea = new helder.ui.Edges(t, r, b, l);
			ui.requestFrame();
		}
		if (open[0] == this) helder.ui.SafeArea.set(t, r, b, l);
	}

	// the window's text input: on at the focus's caret while it takes text
	// (the input method's place), else off; told when it changes
	function updateTextInput() {
		var a = ui.textInputArea(), k = renderer.scale;
		var x = 0, y = 0, w = 0, h = 0;
		if (a != null) {
			x = Math.round(a.x * k);
			y = Math.round(a.y * k);
			w = Math.round(Math.max(1, a.width * k));
			h = Math.round(a.height * k);
		}
		var now = a == null ? "" : '$x,$y,$w,$h';
		if (now == typing) return;
		if (a == null) {
			window.stopTextInput();
			// (which takes the keyboard's focus back from a native editor that just took it)
			if (ui.focus != null) @:privateAccess ui.focus.refocusNative();
		} else window.startTextInput(x, y, w, h);
		typing = now;
	}

	// the tree's changes to the browser's mirror or to macOS (the guards inside: an
	// instance method is compiled whether called or not, and the browser's
	// imports must stay out of the other targets)
	function sendAccess() {
		if (Mem.os() == 3) {
			var t = ui.accessTree();
			var json = t.changesJson(access);
			access = t;
			if (json != null) WebMirror.send(window.surface.handle.toI64().toInt(), json);
		} else if (Mem.platform() >= 1) {} else if (Mem.os() == 1) {
			if (macAccess == null) macAccess = new MacAccess(window, ui);
			(cast macAccess : MacAccess).update();
		} else if (Mem.os() == 2) {
			if (winAccess == null) winAccess = new WinAccess(window, ui);
			(cast winAccess : WinAccess).update();
		} else if (Mem.os() == 0) {
			// (not Android's: AT-SPI is the Linux desktop's)
			if (Mem.target() < 9) {
				if (linuxAccess == null) linuxAccess = new LinuxAccess(window, ui);
				(cast linuxAccess : LinuxAccess).update();
			}
		}
	}

	// the actions assistive technology asked for (the browser's), done
	function pollAccess() {
		if (Mem.os() == 3) {
			if (access != null) WebMirror.poll(ui);
		} else if (Mem.os() == 0) {
			if (Mem.target() < 9) {
				if (linuxAccess != null) LinuxAccess.dispatch();
			}
		}
	}

	// the window's cursor: the Ui's (helder.os.Cursor has Default for Auto first)
	function updateCursor()
		window.cursor = cast Std.int(Math.max(0, (ui.cursor() : Int) - 1));

	// one of the window's events
	public function handle(e:OsEvent) {
		var k = renderer.scale;
		switch e.kind {
			case Close:
				if (onClose != null) onClose() else close();
			case MouseMove:
				ui.pointerMove(e.x / k, e.y / k);
			case Scroll:
				// (Shift turns a vertical wheel sideways, as browsers do)
				var dx = e.deltaX, dy = e.deltaY;
				if (e.mods & helder.os.Event.Mods.SHIFT != 0 && dx == 0) {
					dx = dy;
					dy = 0;
				}
				ui.wheel(e.x / k, e.y / k, dx / k, dy / k);
			case MouseDown:
				ui.pointerDown(e.x / k, e.y / k, e.button);
			case MouseUp:
				ui.pointerUp(e.x / k, e.y / k, e.button);
			// (fingers and pens: the mouse's are its Mouse* events above)
			case PointerDown if (e.pointer.type != helder.os.PointerType.Mouse):
				var p = e.pointer;
				// (a press on the ui's own nodes is the ui's: a game's controls leave it alone)
				if (ui.pointerDown(p.x / k, p.y / k, 1, p.id, p.type, p.pressure)) p.owner = helder.os.PointerOwner.Ui;
			case PointerMove if (e.pointer.type != helder.os.PointerType.Mouse):
				ui.pointerMove(e.pointer.x / k, e.pointer.y / k, e.pointer.id, e.pointer.pressure);
			case PointerUp if (e.pointer.type != helder.os.PointerType.Mouse):
				ui.pointerUp(e.pointer.x / k, e.pointer.y / k, 1, e.pointer.id);
			case PointerCancel if (e.pointer.type != helder.os.PointerType.Mouse):
				ui.pointerCancel(e.pointer.id);
			case KeyDown:
				ui.keyDown(e.key, e.mods);
			case KeyUp:
				ui.keyUp(e.key, e.mods);
			case TextInput:
				ui.textInput(e.text);
			case TextEditing:
				ui.composition(e.text, e.x);
			case Resize | Redraw:
				redraw = true;
			case _:
		}
		updateCursor();
	}

	// (once: a <Surface>'s owner closes it too)
	public function close() {
		if (open.indexOf(this) < 0) return;
		#if hxmc.dev_host
		if (handedOver) return;
		#end
		// (nested: only a constant condition drops the branch)
		if (Mem.platform() >= 1) {} else if (Mem.os() == 1) {
			if (macAccess != null) (cast macAccess : MacAccess).dispose();
		}
		if (Mem.os() == 2) {
			if (winAccess != null) (cast winAccess : WinAccess).dispose();
		}
		if (Mem.os() == 0) {
			if (Mem.target() < 9) {
				if (linuxAccess != null) (cast linuxAccess : LinuxAccess).dispose();
			}
		}
		window.close();
		open.remove(this);
		device.dispose();
	}

	// the app loop: every UiWindow's frames and events until the last closes
	// (on the web it returns, the frames going on); content, when given, opened first
	@:typescript public static function run(?content:RootView) {
		if (content != null) Render.open(content);
		App.run(() -> {
			var now = haxe.Timer.stamp();
			if (now - darkAsked > 1) {
				darkAsked = now;
				var d = App.prefersDark();
				if (d != dark.peek()) {
					dark(d);
					for (w in open)
						w.ui.dark = d;
				}
			}
			var drew = false;
			for (w in open.copy())
				w.pollAccess();
			for (w in open.copy())
				if (w.needsFrame()) {
					w.frame();
					drew = true;
				}
			if (!drew) App.wait(idleWait);
		}, e -> for (w in open.copy()) if (w.window == e.window) w.handle(e));
	}

	// <Surface>: a window (a canvas on the web), its children rendered into its ui's root; closed with its owner
	@:typescript public static function Surface(props:SurfaceProps):RootView {
		var web = Mem.os() == 3;
		var width:Null<Int> = Render.read(props.width), height:Null<Int> = Render.read(props.height);
		var title:Null<String> = Render.read(props.title);
		var w = new UiWindow(title ?? "helder", width ?? (web ? 0 : 800), height ?? (web ? 0 : 600), null, props.antialias != false);
		// (each reactive prop followed after its first value)
		follow(props.title, (v:String) -> w.window.title = v);
		follow(props.width, (_:Int) -> resize(w, props));
		follow(props.height, (_:Int) -> resize(w, props));
		if (props.theme != null) Graph.renderEffect(() -> Render.read(props.theme), v -> w.ui.theme = v);
		if (props.background != null) Graph.renderEffect(() -> Render.read(props.background), v -> {
			w.background = v;
			w.ui.requestFrame();
		});
		if (props.dark != null) Graph.renderEffect(() -> Render.read(props.dark), v -> w.ui.dark = v);
		if (props.onClose != null) w.onClose = props.onClose;
		// (in this owner: what is above the root, contexts, seen inside)
		Render.insert(props.children, w.root, null);
		Graph.onCleanup(w.close);
		if (props.ref != null) props.ref(w);
		return null;
	}

	static function follow<T>(v:Dynamic, set:T->Void) {
		if (!Render.isReactive(v)) return;
		var first = true;
		Graph.renderEffect(() -> (Render.read(v) : T), (x:T) -> {
			if (!first) set(x);
			first = false;
		});
	}

	static function resize(w:UiWindow, props:SurfaceProps) {
		var width:Null<Int> = Render.read(props.width), height:Null<Int> = Render.read(props.height);
		if (width != null && height != null) w.window.resize(width, height);
	}
}

// the system's clipboard (helder.os.Clipboard) for a window's Ui
class SystemClipboard implements ClipboardHost {
	final window:helder.os.Window;

	public function new(window:helder.os.Window)
		this.window = window;

	public function write(text:String)
		helder.os.Clipboard.write(window, text);

	public function read(callback:Null<String>->Void)
		helder.os.Clipboard.read(window, callback);
}

// the browser's accessibility mirror (WebAccess), apart: its imports are
// reached only from the browser's branches
class WebMirror {
	public static function views(canvas:Int):PlatformViews
		return new WebViews(canvas);

	public static function send(canvas:Int, json:String)
		Arena.scoped(a -> WebAccess.access_update(canvas, a.cstring(json)));

	public static function poll(ui:Ui)
		Arena.scoped(a -> {
			var p:Ptr<Int32> = a.alloc(8);
			while (WebAccess.access_action(p) != 0)
				ui.accessAction(p[0], p[1]);
		});
}
