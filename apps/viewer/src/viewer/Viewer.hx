package viewer;

import helder.image.AnimatedImage;
import helder.view.graph.Graph;
import helder.view.graph.Signal;
import viewer.Decode.Decoded;
import viewer.ViewerActions;

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
	// a PDF's page shown (from 0) and its pages (1: an image's, or not known
	// yet); as signals for the window (its key context, the go to page card)
	public var page(default, null) = 0;
	public var pages(default, null) = 1;
	public final pageSignal = Graph.signal(0);
	public final pagesSignal = Graph.signal(1);
	// go to page: its card open, the number typed
	public final gotoOpen = Graph.signal(false);
	public final gotoText = Graph.signal("");

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
		cache.onReady = p -> if (p == key()) show();
		empty();
	}

	// a file or a folder (the command line's, a drop's, the picker's)
	public function open(path:String):Bool {
		pickerOpen(false);
		gotoOpen(false);
		setPage(0);
		setPages(1);
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
		if (onOpened != null) onOpened(path);
		return true;
	}

	// a file opened (the shell's recent files)
	public var onOpened:Null<String->Void> = null;

	public function next():Bool
		return go(folder.go(1));

	public function previous():Bool
		return go(folder.go(-1));

	public function first():Bool
		return go(folder.first());

	public function last():Bool
		return go(folder.last());

	function go(moved:Bool):Bool {
		if (moved) {
			setPage(0);
			setPages(1);
			refresh();
		}
		return moved;
	}

	// --- a PDF's pages: the next, the previous, the first, the last, one by its number (from 1)

	public function nextPage():Bool
		return toPage(page + 1);

	public function previousPage():Bool
		return toPage(page - 1);

	public function toPage(p:Int):Bool {
		if (folder.current == null || p < 0 || p >= pages || p == page) return false;
		setPage(p);
		refresh();
		return true;
	}

	// the go-to-page card's number (from 1, clamped to the pages): taken, the card closed
	public function goToTyped(typed:String):Bool {
		var n = Std.parseInt(StringTools.trim(typed));
		gotoOpen(false);
		if (n == null) return false;
		return toPage(Std.int(Math.max(1, Math.min(n, pages))) - 1);
	}

	function setPage(p:Int) {
		page = p;
		pageSignal(p);
	}

	function setPages(n:Int) {
		pages = n;
		pagesSignal(n);
	}

	// the decode shown's key (its page's, a PDF's: Decode.key)
	public function key():Null<String>
		return folder.current == null ? null : Decode.key(folder.current, page);

	// the folder read again (the watch): new and removed files, the one
	// shown decoded again when it changed on disk
	public function watch() {
		if (folder.dir == "") return;
		var r = folder.rescan();
		for (p in r.modified)
			cache.dropFile(p);
		if (r.listChanged || r.modified.length > 0) {
			if (folder.index < 0) open(folder.dir) else refresh();
		}
	}

	// (what is shown and what is decoded ahead: JPEGs at the view's size, its larger side)
	function refresh() {
		// (before the window's first frame its size is not known: a screen's)
		var side = Std.int(Math.max(camera.viewWidth, camera.viewHeight));
		cache.side = side <= 1 ? 1920 : side;
		cache.want(wanted());
		show();
	}

	// (the page shown, then a PDF's next and previous page, then the folder's neighbours' first)
	function wanted():Array<String> {
		var around = folder.around(prefetch);
		if (around.length == 0) return [];
		var cur = folder.path(around[0]), p = page, n = pages;
		var out = [Decode.key(cur, p)];
		if (p + 1 < n) out.push(Decode.key(cur, p + 1));
		if (p > 0) out.push(Decode.key(cur, p - 1));
		for (i in around.slice(1))
			out.push(folder.path(i));
		return out;
	}

	function show() {
		var path = key();
		if (path == null) return;
		var d = cache.get(path);
		// (a PDF's page count, known once one of its pages landed: its next page decoded ahead)
		if (d != null && d.pages > 0 && d.pages != pages) {
			setPages(d.pages);
			cache.want(wanted());
		}
		if (d == null) {
			if (shownPath != path) {
				shown = null;
				state(Loading);
				message("Loading " + folder.name + (page > 0 ? ", page " + (page + 1) : "") + "…");
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
		var paged = pages > 1 ? 'page ${page + 1} / ${pages}' : "";
		if (paged != "") parts.push(paged) else if (d != null) parts.push('${d.width}×${d.height}');
		title(parts.join(" · "));
		if (d == null) {
			status(parts.join(" · "));
			return;
		}
		var pdf = d.format == "PDF";
		status('${camera.percent()}% · ' + (paged != "" ? paged : pdf ? "1 page" : '${d.width}×${d.height}') + ' · ${d.format}'
			+ (d.frames.length > 1 ? ' · ${d.frames.length} frames' : "")
			+ (!pdf && d.pixelsWidth < d.width ? ' · decoded at 1/${Math.round(d.width / d.pixelsWidth)}' : "") + ' · ${size(d.fileSize)} · ${folder.index + 1} / $n');
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
		// (a PDF's pages first, then the folder's next or previous file)
		if (dir > 0) {
			if (!nextPage()) next();
		} else if (!previousPage()) previous();
	}

	// --- actions (ViewerActions: the keymap's and the menus'): true when taken

	public function perform(a:ViewerAction):Bool {
		switch a {
			case Open:
				if (openDialog == null || !openDialog()) openPicker(folder.dir);
			case OpenRecent(path):
				open(path);
			case Next: next();
			case Previous: previous();
			case First: first();
			case Last: last();
			case ZoomIn: zoomStep(1);
			case ZoomOut: zoomStep(-1);
			case Fit: fit();
			case ActualSize: actual();
			case ToggleFullscreen: fullscreen(!fullscreen.peek());
			case LeaveFullscreen: fullscreen(false);
			case ToggleStatus: statusOn(!statusOn.peek());
			case ClosePicker: pickerOpen(false);
			case NextPage: nextPage();
			case PreviousPage: previousPage();
			case FirstPage: toPage(0);
			case LastPage: toPage(pages - 1);
			case GoToPage:
				if (pages < 2) return false;
				gotoText("");
				gotoOpen(true);
			case CloseGoTo: gotoOpen(false);
			case CopyPath | ShowInFolder | OpenWithDefault: return false;
		}
		return true;
	}

	// what a menu shows it as
	public function actionState(a:ViewerAction):helder.ui.actions.Actions.ActionState
		return switch a {
			case Next | Previous | First | Last: folder.index >= 0 ? Enabled : Disabled;
			case ZoomIn | ZoomOut | Fit | ActualSize: state.peek() == Shown ? Enabled : Disabled;
			case NextPage | LastPage: page + 1 < pages ? Enabled : Disabled;
			case PreviousPage | FirstPage: page > 0 && pages > 1 ? Enabled : Disabled;
			case GoToPage: pages > 1 ? Enabled : Disabled;
			case CopyPath | ShowInFolder | OpenWithDefault: shownPath != "" || folder.current != null ? Enabled : Disabled;
			case ToggleFullscreen: fullscreen.peek() ? Checked : Unchecked;
			case ToggleStatus: statusOn.peek() ? Checked : Unchecked;
			case _: Enabled;
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
