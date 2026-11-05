package viewer;

import helder.image.AnimatedImage;
import helder.ui.Key;
import helder.view.graph.Graph;
import helder.view.graph.Signal;
import viewer.Decode.Decoded;

using StringTools;

enum abstract ViewState(String) to String {
	var Empty = "empty";
	var Loading = "loading";
	var Shown = "shown";
	var Failed = "failed";
}

// The viewer without its window: the folder, the decodes, the camera, and
// what the window shows as signals (its title, the state and its message,
// the status line, the picker), driven by keys, the wheel and the pointer
// the shell passes on. Headless in tests (a decode of its own, no GPU).
class Viewer {
	public final folder = new FolderModel();
	public final cache:DecodeCache;
	public final camera = new ViewCamera();

	public final title = Graph.signal("Viewer");
	public final state = Graph.signal(Empty);
	public final message = Graph.signal("No image open");
	public final detail = Graph.signal("");
	public final status = Graph.signal("");
	public final statusOn = Graph.signal(false);
	public final fullscreen = Graph.signal(false);
	// a change the image view draws (a new image, frame or camera)
	public final version = Graph.signal(0);
	// the picker: open, its folder, its entries (folders end in "/")
	public final pickerOpen = Graph.signal(false);
	public final pickerDir = Graph.signal("");
	public final pickerEntries:Signal<Array<String>> = Graph.signal([]);

	// the image shown (its decode, its path), the animation's frame
	public var shown(default, null):Null<Decoded> = null;
	public var shownPath(default, null) = "";
	public var frame(default, null) = 0;

	// how many neighbours each side are decoded ahead
	public var prefetch = 2;
	// Mod's name for the hints: Ctrl, or Cmd on macOS
	public var mod = "Ctrl";
	// the system's open dialog (Mod+O; the shell's: helder.os.FileDialog):
	// true when it showed one, else the picker
	public var openDialog:Null<Void->Bool> = null;

	var frameAt = 0.0;
	var played = 0;
	var wheelAcc = 0.0;
	var wheelAt = -1.0;

	public function new(decode:(path:String, side:Int, done:Decoded->Void) -> Void, ?budget:Float) {
		cache = new DecodeCache(decode, budget ?? 768 * 1048576.0);
		cache.onReady = p -> if (p == folder.current) show();
		empty();
	}

	// a file or a folder (the command line's, a drop's, the picker's)
	public function open(path:String):Bool {
		pickerOpen(false);
		if (!folder.open(path)) {
			fail("unreadable", "Cannot open " + path, "No such file or folder");
			return false;
		}
		if (folder.index < 0) {
			cache.clear();
			shown = null;
			shownPath = "";
			state(Empty);
			message("No images in " + folder.dir);
			detail("Drop an image here, or press " + mod + "+O");
			updateTitle();
			return true;
		}
		refresh();
		return true;
	}

	public function next():Bool
		return go(folder.go(1));

	public function previous():Bool
		return go(folder.go(-1));

	public function first():Bool
		return go(folder.first());

	public function last():Bool
		return go(folder.last());

	function go(moved:Bool):Bool {
		if (moved) refresh();
		return moved;
	}

	// the folder read again (the watch): new and removed files, the one
	// shown decoded again when it changed on disk
	public function watch() {
		if (folder.dir == "") return;
		var r = folder.rescan();
		for (p in r.modified)
			cache.drop(p);
		if (r.listChanged || r.modified.length > 0) {
			if (folder.index < 0) open(folder.dir) else refresh();
		}
	}

	// (what is shown and what is decoded ahead: JPEGs at the view's size, its larger side)
	function refresh() {
		// (before the window's first frame its size is not known: a screen's)
		var side = Std.int(Math.max(camera.viewWidth, camera.viewHeight));
		cache.side = side <= 1 ? 1920 : side;
		cache.want([for (i in folder.around(prefetch)) folder.path(i)]);
		show();
	}

	function show() {
		var path = folder.current;
		if (path == null) return;
		var d = cache.get(path);
		if (d == null) {
			if (shownPath != path) {
				shown = null;
				state(Loading);
				message("Loading " + folder.name + "…");
				detail("");
			}
		} else if (d.error != null) {
			shown = null;
			shownPath = path;
			state(Failed);
			message(d.error);
			detail(folder.name + (d.format != "" ? " · " + d.format : "") + (d.fileSize > 0 ? " · " + size(d.fileSize) : ""));
		} else if (shown != d) {
			var same = shownPath == path;
			shown = d;
			shownPath = path;
			frame = 0;
			played = 0;
			frameAt = -1;
			if (!same) camera.setImage(d.width, d.height) else camera.setView(camera.viewWidth, camera.viewHeight);
			state(Shown);
			message("");
			detail("");
		}
		updateTitle();
		changed();
	}

	function fail(kind:String, m:String, d:String) {
		shown = null;
		state(Failed);
		message(m);
		detail(d);
		updateTitle();
	}

	function empty() {
		state(Empty);
		message("No image open");
		detail("Drop an image here, or press " + mod + "+O");
	}

	function updateTitle() {
		if (folder.index < 0) {
			title("Viewer");
			status("");
			return;
		}
		var n = folder.files.length, d = shown;
		var parts = [folder.name, '${folder.index + 1} / $n'];
		if (d != null) parts.push('${d.width}×${d.height}');
		title(parts.join(" · "));
		status(d == null ? parts.slice(0, 2).join(" · ") : '${camera.percent()}% · ${d.width}×${d.height} · ${d.format}' + (d.frames.length > 1 ? ' · ${d.frames.length} frames' : "") + (d.pixelsWidth < d.width ? ' · decoded at 1/${Math.round(d.width / d.pixelsWidth)}' : "") + ' · ${size(d.fileSize)} · ${folder.index + 1} / $n');
	}

	// (the camera or the frame moved: the view draws again; zoomed past the
	// pixels a smaller decode has, the whole of it asked for)
	function changed() {
		var d = shown;
		if (d != null && d.pixelsWidth < d.width && camera.scale * d.width / d.pixelsWidth > 1.01) {
			var need = Math.ceil(Math.max(d.width, d.height) * camera.scale);
			cache.refine(shownPath, need >= Math.max(d.width, d.height) ? 0 : need);
		}
		updateTitle();
		version(v -> v + 1);
	}

	// --- zoom and pan (device pixels)

	public function fit() {
		camera.fit();
		changed();
	}

	public function actual() {
		camera.actual();
		changed();
	}

	public function zoomStep(dir:Int) {
		if (shown == null) return;
		camera.step(dir);
		changed();
	}

	public function toggleZoom(x:Float, y:Float) {
		if (shown == null) return;
		camera.toggle(x, y);
		changed();
	}

	public function pan(dx:Float, dy:Float) {
		camera.pan(dx, dy);
		changed();
	}

	// the wheel or a trackpad at (x, y) by dy pixels: with Control (a pinch)
	// a zoom about the point; without, while fitted, the next or previous
	// image (a notch each, at most five a second), else a zoom
	public function wheel(x:Float, y:Float, dy:Float, control:Bool, now:Float) {
		if (dy == 0) return;
		if (control || (shown != null && !camera.fitted)) {
			if (shown == null) return;
			camera.zoomBy(Math.exp(-dy * Math.log(1.25) / 40), x, y);
			changed();
			return;
		}
		if (wheelAcc * dy < 0) wheelAcc = 0;
		wheelAcc += dy;
		if (Math.abs(wheelAcc) < 40 || (wheelAt >= 0 && now - wheelAt < 0.2)) return;
		wheelAt = now;
		var dir = wheelAcc > 0 ? 1 : -1;
		wheelAcc = 0;
		if (dir > 0) next() else previous();
	}

	// --- keys: true when taken

	public function key(key:Int, mods:Int):Bool {
		if (pickerOpen.peek()) {
			if (key == Key.ESCAPE) {
				pickerOpen(false);
				return true;
			}
			return false;
		}
		if (mods & (Key.MOD_CONTROL | Key.MOD_META) != 0) {
			if (key == "o".code) {
				if (openDialog != null && openDialog()) return true;
				openPicker(folder.dir);
				return true;
			}
			return false;
		}
		return switch key {
			case Key.RIGHT | Key.DOWN | Key.PAGE_DOWN | Key.SPACE: next(); true;
			case Key.LEFT | Key.UP | Key.PAGE_UP | Key.BACKSPACE: previous(); true;
			case Key.HOME: first(); true;
			case Key.END: last(); true;
			case v if (v == Key.F1 + 10 || v == Key.ENTER):
				fullscreen(!fullscreen.peek());
				true;
			case Key.ESCAPE if (fullscreen.peek()):
				fullscreen(false);
				true;
			case "i".code:
				statusOn(!statusOn.peek());
				true;
			case _: false;
		}
	}

	// the zoom's keys, as typed (a layout's own + and -): true when taken
	public function typed(text:String):Bool {
		if (pickerOpen.peek()) return false;
		switch text {
			case "+" | "=": zoomStep(1);
			case "-" | "_": zoomStep(-1);
			case "0": fit();
			case "1": actual();
			case _: return false;
		}
		return true;
	}

	// --- the frame: an animation's next frame, a glide; true when it moved

	public function tick(now:Float, dt:Float):Bool {
		var moved = false;
		if (camera.gliding) {
			camera.glide(dt);
			moved = true;
		}
		var d = shown;
		if (d != null && d.frames.length > 1 && (d.repetitions < 0 || played <= d.repetitions)) {
			// (the first tick, or a clock that went back: from now)
			if (frameAt < 0 || now < frameAt) frameAt = now;
			var due = AnimatedImage.duration(d.frames[frame].delay);
			// (late by more than a frame: caught up, not raced through)
			while (now - frameAt >= due) {
				frameAt += due;
				if (now - frameAt > 1) frameAt = now;
				if (frame + 1 < d.frames.length) frame++ else if (d.repetitions < 0 || played < d.repetitions) {
					frame = 0;
					played++;
				} else {
					played++;
					break;
				}
				moved = true;
				due = AnimatedImage.duration(d.frames[frame].delay);
			}
		}
		if (moved) changed();
		return moved || (d != null && d.frames.length > 1) || camera.gliding;
	}

	// --- the picker: a folder's subfolders and images

	public function openPicker(dir:String) {
		var d = dir == "" ? Sys.getCwd() : dir;
		var names = try sys.FileSystem.readDirectory(d) catch (_:Dynamic) [];
		var dirs = [], images = [];
		for (n in names) {
			if (n.startsWith(".")) continue;
			var p = FolderModel.join(d, n);
			if (try sys.FileSystem.isDirectory(p) catch (_:Dynamic) false) dirs.push(n + "/") else if (FolderModel.isImage(n)) images.push(n);
		}
		dirs.sort(FolderModel.compare);
		images.sort(FolderModel.compare);
		pickerDir(d);
		pickerEntries(["../"].concat(dirs).concat(images));
		pickerOpen(true);
	}

	// an entry picked: a folder entered, an image opened
	public function pick(entry:String) {
		var d = pickerDir.peek();
		if (entry == "../") {
			var up = haxe.io.Path.directory(haxe.io.Path.removeTrailingSlashes(d));
			openPicker(up == "" ? "/" : up);
		} else if (entry.endsWith("/")) openPicker(FolderModel.join(d, entry.substr(0, entry.length - 1))) else open(FolderModel.join(d, entry));
	}

	public static function size(bytes:Int):String
		return bytes >= 1048576 ? Std.string(Math.round(bytes / 104857.6) / 10) + " MB" : bytes >= 1024 ? Math.round(bytes / 1024) + " KB" : bytes + " B";
}
