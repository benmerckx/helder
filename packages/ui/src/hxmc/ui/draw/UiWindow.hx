package hxmc.ui.draw;

import hxmc.gfx.*;
import hxmc.os.App;
import hxmc.os.Event as OsEvent;
import hxmc.ui.*;

// A window showing a UI tree drawn with the GPU: an hxmc.os Window, its
// gfx Device, a Renderer and the Ui (root: the tree's root node, in the
// window's points). The window's events become the Ui's (pointer, wheel,
// keys, text); each frame lays the tree out and draws it. run() is the app
// loop for every UiWindow open.
class UiWindow {
	public final window:hxmc.os.Window;
	public final device:Device;
	public final renderer:Renderer;
	public final ui:Ui;
	public var background:Color = Color.rgb(0xF4F4F5);
	public var onClose:Null<Void->Void>;

	static final open:Array<UiWindow> = [];
	final pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 1, 1)}]};
	var buttons = 0;

	public function new(title:String, width:Int, height:Int, ?text:TextEngine) {
		window = new hxmc.os.Window(title, width, height);
		device = Device.create(window.surface);
		renderer = new Renderer(device);
		ui = new Ui(text == null ? new DrawText() : text, width, height);
		open.push(this);
	}

	public var root(get, never):Node;

	inline function get_root()
		return ui.root;

	// draws a frame (the loop calls it)
	public function frame() {
		var s = window.scale;
		renderer.scale = device.width / Math.max(1, Math.round(device.width / s));
		ui.resize(device.width / renderer.scale, device.height / renderer.scale);
		ui.update();
		var enc = device.beginFrame();
		if (enc == null) return;
		var c = pass.colors[0].clear;
		@:privateAccess {
			c.r = background.r / 255;
			c.g = background.g / 255;
			c.b = background.b / 255;
		}
		enc.beginPass(pass);
		renderer.begin(device.width, device.height);
		ui.paint(renderer);
		renderer.end(enc);
		enc.endPass();
		device.endFrame();
	}

	// one of the window's events
	public function handle(e:OsEvent) {
		var k = renderer.scale;
		switch e.kind {
			case Close:
				if (onClose != null) onClose() else close();
			case MouseMove:
				ui.pointerMove(e.x / k, e.y / k);
			case MouseDown if (e.button == 4 || e.button == 5):
				ui.wheel(e.x / k, e.y / k, 0, e.button == 4 ? -40 : 40);
			case MouseDown:
				ui.pointerDown(e.x / k, e.y / k, e.button);
			case MouseUp if (e.button == 4 || e.button == 5):
			case MouseUp:
				ui.pointerUp(e.x / k, e.y / k, e.button);
			case KeyDown:
				ui.keyDown(e.key, 0);
			case KeyUp:
				ui.keyUp(e.key, 0);
			case _:
		}
	}

	public function close() {
		window.close();
		open.remove(this);
		device.dispose();
	}

	// the app loop: every UiWindow's frames and events until the last closes
	public static function run() {
		App.run(() -> for (w in open.copy()) w.frame(), e -> for (w in open.copy()) if (w.window == e.window) w.handle(e));
	}
}
