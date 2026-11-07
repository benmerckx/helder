package helder.story;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.Surface;
import helder.story.Story;
import helder.ui.*;
import helder.ui.draw.*;
import helder.view.Render;

// Many stories in one program, each mounted as a root of its own: the
// studio's preview host (apps/studio). The program runs once; each screen
// (a story) has a Ui of its story's size and a ScreenContext of its own
// (its clock and timers, keymap, safe area, dark or light, settings), so
// screens animate, bind keys and keep settings apart, and a screen off
// screen stops all of it.
//
// What draws: only the screens shown (show: the names in view). The
// focused one (focus: the screen zoomed into) draws every frame; the
// others when something in them changed (their Ui asks for a frame, their
// clock animates). A screen hidden is suspended (its clock and timers
// stop) and keeps its last frame where it was shown (the studio's), and a
// screen never shown is never built: a project of fifty screens builds the
// ones in view. All screens draw with one GPU device, one Renderer and one
// text engine (their glyph atlas and image pages shared), each frame into
// the runtime's target at the screen's size, handed over as it is drawn.
//
// The runtime is the host's way to pixels (HostRuntime): headless natively
// (HeadlessHost: an offscreen surface, each frame read back), an
// OffscreenCanvas in a web worker (helder.story.web.WorkerHost: each frame
// an ImageBitmap posted to the page), the studio's native preview process
// (helder.story.NativeHost's SharedFrames: each frame drawn into a GPU
// texture the studio's process opens, or copied through shared memory).
//
//   var host = new Host(Stories.of("Todo_story"), new HeadlessHost((s, pixels) -> ...));
//   host.show([for (s in host.screens) s.name]);
//   while (true) host.frame(haxe.Timer.stamp());
class Host {
	public final screens:Array<HostScreen> = [];
	public final runtime:HostRuntime;
	public final text:TextEngine;
	public final device:Device;
	public final renderer:Renderer;
	// pixels per point of every screen's frames
	public var scale(default, null) = 1.0;
	// the colour under a screen's tree (a window's default, as UiWindow's)
	public var background:Color = Color.rgb(0xF4F4F5);
	public var focused(default, null):Null<HostScreen> = null;
	// frames drawn, of every screen
	public var frames(default, null) = 0;
	// told: a screen's frame drawn and handed over
	public var onFrame:Null<HostScreen->Void> = null;

	final pass:PassDesc = {colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]};

	public function new(stories:Array<Story>, runtime:HostRuntime, scale = 1.0) {
		this.runtime = runtime;
		this.scale = scale;
		// (helder.text's own shaping: a screen looks the same everywhere)
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		text = new DrawText();
		device = Device.create(runtime.surface, {antialias: false});
		renderer = new Renderer(device);
		for (s in stories)
			if (s != null) screens.push(new HostScreen(this, s));
		if (screens.length == 0) throw "helder.story.Host: no stories (a release build has none)";
	}

	public function screen(name:String):Null<HostScreen>
		return Lambda.find(screens, s -> s.name == name);

	// the screens in view (the others suspended, their last frames kept where they were shown)
	public function show(names:Array<String>) {
		for (s in screens) {
			var on = names.contains(s.name);
			if (on && !s.visible) s.redraw = true;
			s.visible = on;
			s.context.suspended = !on;
		}
	}

	// the screen drawn every frame (null: none; every one shown draws on
	// change), at its own pixels per point (the studio's zoom into it: its
	// frames sharp at the canvas' scale; the others at the host's)
	public function focus(name:Null<String>, ?scale:Float) {
		var next = name == null ? null : screen(name);
		if (focused != null && focused != next && focused.scale != this.scale) {
			focused.scale = this.scale;
			focused.redraw = true;
		}
		focused = next;
		if (focused == null) return;
		var k = scale ?? this.scale;
		if (k != focused.scale) focused.scale = k;
		focused.redraw = true;
	}

	// one turn at now (seconds): each screen shown built the first time,
	// its clock ticked, laid out, and drawn when it changed (the focused one
	// always): how many were drawn
	public function frame(now:Float):Int {
		var drawn = 0;
		for (s in screens) {
			if (!s.visible) continue;
			s.mount();
			var ui = s.ui;
			var changed = s.context.run(() -> {
				Clock.tick(now);
				ui.update();
				ui.needsFrame || s.context.animating;
			});
			if (changed || s.redraw || s == focused) {
				draw(s, changed || s.redraw);
				drawn++;
			}
		}
		return drawn;
	}

	// whether anything shown would draw in the next turn (else the loop may sleep until the next event or timer)
	public function busy():Bool {
		for (s in screens)
			if (s.visible && (s.ui == null || s.redraw || s == focused || s.ui.needsFrame || s.context.animating)) return true;
		return false;
	}

	// the earliest timer of the screens shown (Clock's time; infinity: none)
	public function nextTimer():Float {
		var t = Math.POSITIVE_INFINITY;
		for (s in screens)
			if (s.visible) t = Math.min(t, s.context.nextTimer());
		return t;
	}

	// a screen's frame: the target at its size, its tree painted, handed over
	// (changed: something in it changed since its last frame; else the focused one's frame of every turn)
	function draw(s:HostScreen, changed:Bool) {
		var scale = s.scale;
		var w = Math.round(s.width * scale), h = Math.round(s.height * scale);
		// (not now: the runtime has no target free for it, or the same pixels are there; again at a next turn when it changed)
		if (!runtime.begin(s, device, w, h, changed)) {
			if (changed) s.redraw = true;
			return;
		}
		var enc = device.beginFrame();
		if (enc == null) {
			s.redraw = true;
			return;
		}
		s.redraw = false;
		var c = pass.colors[0].clear;
		@:privateAccess {
			c.r = background.r / 255;
			c.g = background.g / 255;
			c.b = background.b / 255;
		}
		renderer.scale = scale;
		var ui = s.ui;
		ui.scale = scale;
		s.context.run(() -> {
			renderer.begin(device.width, device.height);
			ui.paint(renderer);
			renderer.prepare(enc);
		});
		enc.beginPass(pass);
		renderer.end(enc);
		enc.endPass();
		runtime.capture(s, device);
		device.endFrame();
		s.version++;
		frames++;
		runtime.present(s, changed);
		if (onFrame != null) onFrame(s);
	}
}

// One screen of a host: its story, its context, its Ui (made when first shown)
class HostScreen {
	public final host:Host;
	public final story:Story;
	public final name:String;
	public final context:ScreenContext;
	// its size in points (the story's, a phone's without)
	public final width:Int;
	public final height:Int;
	public var ui(default, null):Null<Ui> = null;
	public var controls(default, null):Null<Controls> = null;
	public var visible = false;
	// its frames' pixels per point (the host's, or its focus's)
	public var scale:Float;
	// frames drawn
	@:allow(helder.story.Host) public var version(default, null) = 0;
	// (shown again, focused: a frame due whatever changed)
	@:allow(helder.story.Host) var redraw = true;
	// when it was built (haxe.Timer.stamp; -1: not yet)
	public var mountedAt(default, null) = -1.0;

	public function new(host:Host, story:Story) {
		this.host = host;
		this.story = story;
		name = story.name;
		width = story.width ?? Stories.WIDTH;
		height = story.height ?? Stories.HEIGHT;
		context = new ScreenContext(name);
		scale = host.scale;
	}

	// built: its Ui made in its context, its story's view rendered into the root
	public function mount() {
		if (ui != null) return;
		mountedAt = haxe.Timer.stamp();
		// (its state's keys in a scope of its name: kept across a reload whichever screens mount first, helder.dev.Hot)
		context.run(() -> helder.dev.Hot.scope(name, () -> {
			var u = new Ui(host.text, width, height);
			u.dark = context.dark.peek();
			ui = u;
			controls = new Controls(story.seed);
			Render.render(story.build(controls), u.root);
			true;
		}));
	}

	// something to do in it (an event's handling, a devtools method): f with its context current
	public inline function run<T>(f:Void->T):T
		return context.run(f);
}

// A host's way to pixels: its target (a surface the device renders to),
// made ready for each screen's frame (begin: the surface sized, or a texture
// the frame goes into; false: no frame of it now, changed or not: drawn
// later; changed: whether anything in it changed since its last frame, else
// the focused screen's frame of every turn, the same pixels), each frame
// read (capture: before it is presented) and handed over (present: after)
interface HostRuntime {
	var surface(default, null):Surface;
	function begin(s:HostScreen, device:Device, width:Int, height:Int, changed:Bool):Bool;
	function capture(s:HostScreen, device:Device):Void;
	function present(s:HostScreen, changed:Bool):Void;
}

// Natively, offscreen: each screen's frame read back into its pixels
// (RGBA8, rows top to bottom), handed to frame
class HeadlessHost implements HostRuntime {
	public var surface(default, null):Surface;
	// each screen's last frame
	public final pixels = new Map<String, Bytes>();
	final framed:Null<(s:HostScreen, pixels:Bytes) -> Void>;

	public function new(?framed:(s:HostScreen, pixels:Bytes) -> Void) {
		this.framed = framed;
		surface = Surface.headless(1, 1);
	}

	public function begin(s:HostScreen, device:Device, width:Int, height:Int, changed:Bool):Bool {
		if (surface.width != width || surface.height != height) @:privateAccess surface.resized(width, height);
		return true;
	}

	public function capture(s:HostScreen, device:Device) {
		var n = device.width * device.height * 4;
		var b = pixels.get(s.name);
		if (b == null || b.length != n) {
			b = Bytes.alloc(n);
			pixels.set(s.name, b);
		}
		device.readPixels(b);
	}

	public function present(s:HostScreen, changed:Bool)
		if (framed != null) framed(s, pixels.get(s.name));
}
