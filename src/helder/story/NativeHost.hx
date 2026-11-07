package helder.story;

#if !(hxmc.target == "wasm32-wasi")
import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.Surface;
import helder.story.Host;
import helder.story.Story;
import hxmc.unsafe.*;

// The studio's preview host natively (apps/studio: Previews): the
// project's program, a dev build, run once in a process of its own with
// every story mounted in one helder.story.Host, started by the studio with
// helder dev's machinery (HXMC_DEV: the devtools protocol on a connection
// to the studio, HostAgent's methods; HXMC_DEV_SNAPSHOT: its state across
// a rebuild). Each screen drawn goes into a GPU texture the studio's
// process opens and composites without a copy (SharedFrames: helder.gfx's
// shared textures, an IOSurface, a DXGI texture or a dma-buf), else, where
// the GPU shares none (llvmpipe), through shared memory (a file mapped by
// both, the studio copying it into its own texture). It tells
//
//   Host.ready {screens, sharing}          once running: the screens, and how frames come
//   Host.frame {screen, version, width, height, pixelWidth, pixelHeight, buffer, handle}
//                                          a screen's frame (screen: its index; handle: the
//                                          texture to open, or copy:<file> of its pixels)
//   Hot.patched                            a patch's first frame (helder.dev)
//
// and a frame's target is drawn into again once the studio sends
// Host.release for it (it shows a newer one): at most three a screen, so a
// screen drawing every frame never waits on the studio, and one the studio
// is still sampling is never drawn into. The loop: the studio's messages
// (helder.dev.Hot.poll), a turn of the host, the frames told, asleep for
// a millisecond or two when nothing is due.
//
//   // the studio's generated main (bin/studio/<name>/gen/StudioScreens.hx, screens.tsx)
//   helder.story.Screens.run(helder.story.Stories.of("Todo_story"));   // here, natively
class NativeHost {
	public static function run(stories:Array<Story>) {
		#if !hxmc.dev
		throw "helder.story: the preview host runs in a dev build (helder studio's)";
		#else
		var frames = new SharedFrames(Sys.getEnv("HELDER_STUDIO_FRAMES"), Sys.getEnv("HELDER_STUDIO_COPY") == "1");
		var host = new Host(stories, frames);
		frames.host = host;
		helder.devtools.Agent.route = m -> HostAgent.receive(host, m);
		HostAgent.onRelease = frames.release;
		HostAgent.onSnap = frames.snap;
		// (the connection made and the hello sent first)
		helder.dev.Hot.poll();
		// (a reload: the screens the last build had built, built again before the first frame, so that
		// their state comes back, shown or not; the snapshot keeps which)
		var kept:Null<Array<String>> = helder.dev.Hot.load("helder.story.mounted", helder.dev.Hot.typeOf((_ : Array<String>)));
		if (kept != null) for (n in kept) {
			var s = host.screen(n);
			if (s != null) s.mount();
		}
		helder.dev.Hot.onSnapshot(() -> helder.dev.Hot.save("helder.story.mounted", [for (s in host.screens) if (s.ui != null) s.name],
			helder.dev.Hot.typeOf((_ : Array<String>))));
		helder.devtools.Agent.notify("Host.ready", {screens: HostAgent.list(host), sharing: frames.sharing(host.device)});
		while (true) {
			helder.dev.Hot.poll();
			var drawn = host.frame(haxe.Timer.stamp());
			if (drawn > 0) helder.dev.Hot.framed();
			// (nothing due: a nap, the next timer's or the studio's next message's latency)
			if (drawn == 0) Sys.sleep(host.busy() ? 0.001 : Math.max(0.001, Math.min(0.004, host.nextTimer() - haxe.Timer.stamp())));
		}
		#end
	}
}

// The native host's runtime: each screen's frame into a target of its own
// the studio opens (Frame: a shared texture, or a shared memory file of its
// pixels), up to MAX a screen (a target is drawn into again once the studio
// released it)
class SharedFrames implements HostRuntime {
	public var surface(default, null):Surface;
	public var host:Null<Host> = null;

	// "iosurface", "dxgi", "dmabuf" (helder.gfx's), or "copy"
	var kind:Null<String> = null;
	final dir:Null<String>;
	final forceCopy:Bool;
	// each screen's targets (by its index), the one the studio was told last
	final targets = new Map<Int, Array<Frame>>();
	final told = new Map<Int, Frame>();
	var current:Null<Frame> = null;
	var currentScreen = -1;
	var pixels = Bytes.alloc(0);
	var nextId = 1;
	var serial = 0;
	// (this process's files apart from another host's in the same directory)
	final session = StringTools.hex(Std.random(0x7FFFFFFF), 8) + StringTools.hex(Std.int(haxe.Timer.stamp() * 1000) & 0xFFFFFF, 6);

	static inline var MAX = 3;

	public function new(dir:Null<String>, forceCopy:Bool) {
		this.dir = dir == "" ? null : dir;
		this.forceCopy = forceCopy;
		surface = Surface.headless(1, 1);
	}

	public function sharing(device:Device):String {
		if (kind == null) kind = forceCopy || device.sharing == null ? "copy" : device.sharing;
		return kind;
	}

	public function begin(s:HostScreen, device:Device, width:Int, height:Int, changed:Bool):Bool {
		var i = host.screens.indexOf(s), k = sharing(device);
		var last = told.get(i);
		// (the same pixels as the frame the studio has: nothing to draw)
		if (!changed && last != null && last.width == width && last.height == height) return false;
		var list = targets.get(i);
		if (list == null) targets.set(i, list = []);
		var f:Null<Frame> = null;
		for (x in list.copy())
			if (!x.held) {
				if (x.width == width && x.height == height) {
					if (f == null) f = x;
				} else {
					// (another size: the screen zoomed, or not any more)
					x.free(device);
					list.remove(x);
				}
			}
		if (f == null) {
			// (every target held by the studio: drawn when it releases one)
			if (list.length >= (k == "copy" ? 2 : MAX)) return false;
			f = make(device, i, width, height);
			if (f == null) return false;
			list.push(f);
		}
		current = f;
		currentScreen = i;
		if (f.texture != null) device.frameInto(f.texture) else if (surface.width != width || surface.height != height)
			@:privateAccess surface.resized(width, height);
		return true;
	}

	function make(device:Device, i:Int, width:Int, height:Int):Null<Frame> {
		var id = nextId++;
		if (kind != "copy") {
			var s = device.createShared(width, height);
			if (s != null) return new Frame(id, width, height, s.texture, s.handle, null);
			// (the GPU would not share one: copies from now on)
			kind = "copy";
		}
		var path = (dir ?? haxe.io.Path.directory(Sys.programPath())) + '/helder-frame-$session-${++serial}.rgba';
		var file = FrameFile.create(path, width * height * 4);
		return new Frame(id, width, height, null, "copy:" + path, file);
	}

	public function capture(s:HostScreen, device:Device) {
		var f = current;
		if (f == null || f.file == null) return;
		var n = f.width * f.height * 4;
		if (pixels.length < n) pixels = Bytes.alloc(n);
		device.readPixels(pixels);
		f.file.write(pixels, n);
	}

	public function present(s:HostScreen, changed:Bool) {
		var f = current, i = currentScreen;
		current = null;
		if (f == null) return;
		if (f.texture != null) host.device.frameInto(null);
		f.held = true;
		told.set(i, f);
		#if hxmc.dev
		helder.devtools.Agent.notify("Host.frame", {
			screen: i,
			version: s.version,
			width: s.width,
			height: s.height,
			pixelWidth: f.width,
			pixelHeight: f.height,
			buffer: f.id,
			handle: f.handle
		});
		#end
	}

	// the studio shows a newer frame of the screen: this one's target free
	public function release(s:HostScreen, buffer:Int) {
		var list = targets.get(host.screens.indexOf(s));
		if (list != null) for (f in list)
			if (f.id == buffer) f.held = false;
	}

	// a screen's last frame written to path (a 16-byte header, "HLDF", its
	// width and height, then RGBA rows top to bottom): {path, width, height}
	public function snap(s:HostScreen, path:String):Dynamic {
		var f = told.get(host.screens.indexOf(s));
		if (f == null) throw 'no frame of ${s.name} yet';
		var device = host.device, n = f.width * f.height * 4;
		var b = Bytes.alloc(16 + n), px = Bytes.alloc(n);
		if (f.file != null) f.file.read(px, n) else {
			device.frameInto(f.texture);
			var enc = device.beginFrame();
			if (enc == null) throw 'no frame of ${s.name} to read now';
			device.readPixels(px);
			device.endFrame();
			device.frameInto(null);
		}
		b.blit(16, px, 0, n);
		b.blit(0, Bytes.ofString("HLDF"), 0, 4);
		b.setInt32(4, f.width);
		b.setInt32(8, f.height);
		b.setInt32(12, s.version);
		sys.io.File.saveBytes(path, b);
		return {path: path, width: f.width, height: f.height};
	}
}

// A frame's target: a shared texture (handle: helder.gfx's), or a file of
// its pixels mapped by both processes (handle: copy:<path>); held while the
// studio may show it
class Frame {
	public final id:Int;
	public final width:Int;
	public final height:Int;
	public final texture:Null<Texture>;
	public final handle:String;
	public final file:Null<FrameFile>;
	public var held = false;

	public function new(id, width, height, texture, handle, file) {
		this.id = id;
		this.width = width;
		this.height = height;
		this.texture = texture;
		this.handle = handle;
		this.file = file;
	}

	public function free(device:Device) {
		if (texture != null) device.destroyTexture(texture);
		if (file != null) file.remove();
	}
}
#end
