package viewer;

import helder.async.Async;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.ui.view.UiFlow.VirtualList;
import helder.ui.view.UiFlow.MenuBarView;
import viewer.Decode.Decoded;
import viewer.ViewerActions;

// The viewer's window: the image view filling it on the dark background,
// a message in place of the image (none open, loading, an error), the
// status line (I), the picker (Mod+O: a folder's listing in a card), the
// title "name · 3 / 128 · W×H"; files dropped on it opened; fullscreen
// (F11, Enter; Escape leaves); its size and place kept between runs
// (helder.os.Store "helder-viewer"); decodes as helder.jobs' jobs, the
// folder watched every second.
class Shell implements Markup {
	public static function main(args:Array<String>) {
		var mac = hxmc.unsafe.Mem.os() == 1;
		var store = try helder.os.Store.open("helder-viewer") catch (_:Dynamic) null;
		inline function num(k:String, d:Int):Int {
			var v = store == null ? null : Std.parseInt(store.get(k) ?? "");
			return v == null ? d : v;
		}
		fallbackFont();
		// (a decode's IDCT, upsampling and colours over two threads: the pool decodes two files at once)
		helder.image.JpegDecoder.threads = 2;
		var viewer = new Viewer(jobDecode);
		viewer.mod = mac ? "Cmd" : "Ctrl";
		// (the keymap: secondary as this platform's; the user's file over the defaults, beside the store)
		helder.ui.actions.Keymap.mac = mac;
		helder.ui.menu.Menus.appName = "Viewer";
		ViewerActions.defaults(helder.ui.actions.Keymap.global);
		if (store != null) helder.ui.actions.Keymap.global.loadUser(haxe.io.Path.join([haxe.io.Path.directory(store.path), "helder-viewer-keymap.json"]));
		if (helder.ui.actions.Keymap.global.error != null) Sys.println("viewer: " + helder.ui.actions.Keymap.global.error);
		// (File's Open Recent: the last eight files opened, kept in the store)
		var recent = store == null || store.get("recent") == null ? [] : [for (r in store.get("recent").split("\n")) if (r != "") r];
		var bar:Null<helder.ui.menu.Menus.MenuBar> = null;
		viewer.onOpened = p -> {
			var full = try sys.FileSystem.fullPath(p) catch (_:Dynamic) p;
			if (sys.FileSystem.isDirectory(full)) return;
			recent.remove(full);
			recent.unshift(full);
			if (recent.length > 8) recent.resize(8);
			if (store != null) store.set("recent", recent.join("\n"));
			if (bar != null) bar.setMenus(ViewerActions.menus(recent));
		};
		viewer.statusOn(num("status", 0) == 1);
		// (--exit-after s: the window closed after s seconds, the title and
		// state printed: a smoke run of the real window and GPU, CI's)
		// (--report file: that line written there too, for a launch whose output is the system's: open -a)
		var valued = ["--exit-after", "--report"];
		inline function arg(name:String):Null<String>
			return args.indexOf(name) >= 0 ? args[args.indexOf(name) + 1] : null;
		var exitAfter = arg("--exit-after") != null ? Std.parseFloat(arg("--exit-after")) : -1.0, report = arg("--report");
		if (args.contains("--version")) {
			Sys.println("Viewer " + Version.NAME);
			return;
		}
		var path = [for (i in 0...args.length) if (!StringTools.startsWith(args[i], "-") && (i == 0 || !valued.contains(args[i - 1]))) args[i]][0];
		// (--register: the file types registered for this user, "Open with"; then done)
		if (args.contains("--register")) {
			for (w in helder.os.FileTypes.register(mac ? "org.helder.viewer" : "helder-viewer", "Viewer", sys.FileSystem.fullPath(Sys.programPath()), TYPES))
				Sys.println("registered: " + w);
			return;
		}
		// (another viewer running: the file handed to it, this one done; --new: a viewer of its own)
		if (path != null && !args.contains("--new")) {
			var full = sys.FileSystem.fullPath(path);
			var taken = false;
			Async.run(_ -> taken = Instance.handOver(full));
			if (taken) {
				Sys.println("viewer: handed to the running viewer: " + full);
				return;
			}
		}
		if (!args.contains("--new")) Instance.serve(p -> {
			viewer.open(p);
			helder.view.graph.Graph.flush();
			for (w in helder.os.App.windows) w.raise();
		});
		// (macOS's: Finder's "Open With", the Dock's icon)
		helder.os.App.onOpen = paths -> {
			viewer.open(paths[0]);
			helder.view.graph.Graph.flush();
		};
		// (Ctrl+O: the system's dialog where there is one, else the picker)
		viewer.openDialog = () -> {
			if (!helder.os.FileDialog.available() || helder.os.App.windows.length == 0) return false;
			var picked = helder.os.FileDialog.open(helder.os.App.windows[0], "Open an image", [{name: "Images", extensions: [for (t in TYPES) for (x in t.extensions) x]}]);
			if (picked != null) viewer.open(picked);
			return true;
		};
		if (path != null) viewer.open(path) else @:privateAccess viewer.empty();
		var window:Null<UiWindow> = null;
		UiWindow.run(<Surface title={viewer.title} width={num("width", 1100)} height={num("height", 760)} background="#161618" dark={true}
			onDrop={(files, x, y) -> if (files.length > 0) viewer.open(files[0])}
			onClose={() -> {
				save(store, window, viewer);
				if (!args.contains("--new")) Instance.leave();
				window.close();
			}}
			ref={w -> {
				window = w;
				w.window.setMinSize(320, 240);
				var placed = store != null && store.exists("x") && store.exists("y");
				if (placed) w.window.moveTo(num("x", 0), num("y", 0));
				asked = {x: placed ? num("x", 0) : null, y: placed ? num("y", 0) : null, width: num("width", 1100), height: num("height", 760)};
				attach(w.ui.root, viewer);
				effect(() -> viewer.fullscreen(), on -> w.window.fullscreen = on);
				// (the window's size and place kept as they change, not only at its close: macOS's Quit, a crash, a logout)
				Async.launch(_ -> while (!w.window.closed) {
					Async.delay(1);
					if (!w.window.closed) save(store, w, viewer);
				});
				if (exitAfter >= 0) Async.launch(_ -> {
					Async.delay(exitAfter);
					var line = 'viewer: ${viewer.title.peek()} (${viewer.state.peek()}${viewer.message.peek() == "" ? "" : ": " + viewer.message.peek()}, ${viewer.camera.percent()}%, ${w.window.width}x${w.window.height})';
					Sys.println(line);
					if (report != null) try sys.io.File.saveContent(report, line + "\n") catch (_:Dynamic) {}
					save(store, w, viewer);
					if (!args.contains("--new")) Instance.leave();
					w.close();
				});
			}}>
			<MenuBarView menus={ViewerActions.menus(recent)} ref={b -> bar = b}/>
			{view(viewer)}
		</Surface>);
	}

	// the types it opens (helder.webmanifest's file_handlers too: a macOS bundle's)
	public static final TYPES = [
		{mime: "image/jpeg", extensions: ["jpg", "jpeg", "jfif"]},
		{mime: "image/png", extensions: ["png", "apng"]},
		{mime: "image/gif", extensions: ["gif"]},
		{mime: "image/webp", extensions: ["webp"]},
		{mime: "application/pdf", extensions: ["pdf"]},
		// (the system's decoders': WIC, ImageIO, Linux's libtiff, libheif and libavif where installed)
		{mime: "image/tiff", extensions: ["tif", "tiff"]},
		{mime: "image/heic", extensions: ["heic", "heif"]},
		{mime: "image/avif", extensions: ["avif"]}
	];

	// the viewer's own font (DejaVu Sans, a subset: fonts/README.md), added
	// only when the system has none it finds (a bare Wine prefix, a minimal
	// container): never stopped for lack of one
	public static function fallbackFont() {
		var fonts = helder.text.SystemFonts.get();
		if (fonts.match("sans-serif") == null) fonts.add(helder.asset.Asset.embed("fonts/DejaVuSans-viewer.ttf"));
	}

	// (the decode on a pool's thread: Decode.job)
	static function jobDecode(path:String, side:Int, done:Decoded->Void)
		Async.launch(_ -> done(Decode.job(path, side)));

	// (what the window was made with, and what it then measured: a menu bar
	// in the window (Windows'), a frame the place counts or not; kept the
	// same at the next start, so that size and place do not creep run by run)
	static var asked:Null<{x:Null<Int>, y:Null<Int>, width:Int, height:Int}> = null;
	static var offset:Null<{x:Int, y:Int, width:Int, height:Int}> = null;

	static function save(store:Null<helder.os.Store>, w:Null<UiWindow>, viewer:Viewer) {
		if (store == null || w == null) return;
		store.set("status", viewer.statusOn.peek() ? "1" : "0");
		if (viewer.fullscreen.peek()) return;
		var k = w.window.scale > 0 ? w.window.scale : 1;
		var p = w.window.position();
		var width = Math.round(w.window.width / k), height = Math.round(w.window.height / k);
		if (offset == null && asked != null) offset = {
			x: p == null || asked.x == null ? 0 : p.x - asked.x,
			y: p == null || asked.y == null ? 0 : p.y - asked.y,
			width: width - asked.width,
			height: height - asked.height
		};
		var o = offset ?? {x: 0, y: 0, width: 0, height: 0};
		if (p != null) {
			store.set("x", Std.string(p.x - o.x));
			store.set("y", Std.string(p.y - o.y));
		}
		store.set("width", Std.string(width - o.width));
		store.set("height", Std.string(height - o.height));
	}

	// the viewer's actions on the root (its key context "Viewer", with
	// picker and fullscreen while they are; ViewerActions' default keymap in
	// the app's), the folder watched
	public static function attach(root:Node, viewer:Viewer, watch = true) {
		ViewerActions.defaults(helder.ui.actions.Keymap.global);
		renderEffect(() -> "Viewer" + (viewer.pickerOpen() ? " picker" : "") + (viewer.fullscreen() ? " fullscreen" : "") + (viewer.pagesSignal() > 1 ? " pdf" : "")
			+ (viewer.gotoOpen() ? " goto" : "") + (viewer.aboutOpen() ? " about" : ""),
			c -> root.keyContext = helder.ui.actions.KeyContext.parse(c));
		root.on(ViewerAction, a -> switch a {
			case CopyPath:
				if (root.ui != null && viewer.folder.current != null) root.ui.clipboard.write(viewer.folder.current);
				true;
			case ShowInFolder:
				if (viewer.folder.current != null) reveal(viewer.folder.current);
				true;
			case OpenWithDefault:
				if (viewer.folder.current != null) openDefault(viewer.folder.current);
				true;
			case _: viewer.perform(a);
		}, viewer.actionState);
		// (Help's About, macOS's application menu's: the about card)
		root.on(helder.ui.actions.Actions.StandardAction, a -> switch a {
			case About:
				viewer.aboutOpen(true);
				true;
			case _: false;
		}, a -> a == About ? Enabled : Unhandled);
		if (watch) Async.launch(_ -> while (true) {
			Async.delay(1);
			viewer.watch();
		});
	}

	// (the system's file manager at the file: Finder, Explorer, the FileManager1 portal's caller, else the folder opened)
	static function reveal(path:String) {
		var os = Sys.systemName();
		if (os == "Mac") spawn("open", ["-R", path]) else if (os == "Windows") spawn("explorer", ["/select," + path]) else
			spawn("dbus-send", ["--session", "--dest=org.freedesktop.FileManager1", "--type=method_call", "/org/freedesktop/FileManager1",
				"org.freedesktop.FileManager1.ShowItems", "array:string:file://" + path, "string:"], () -> spawn("xdg-open", [haxe.io.Path.directory(path)]));
	}

	static function openDefault(path:String) {
		var os = Sys.systemName();
		if (os == "Mac") spawn("open", [path]) else if (os == "Windows") spawn("cmd", ["/c", "start", "", path]) else spawn("xdg-open", [path]);
	}

	// (a program run, not waited for by the window; failed: otherwise)
	static function spawn(cmd:String, args:Array<String>, ?otherwise:Void->Void)
		Async.launch(_ -> {
			var code = try {
				var p = new helder.async.Process(cmd, args);
				var c = p.wait();
				p.close();
				c;
			} catch (_:Dynamic) -1;
			if (code != 0 && otherwise != null) otherwise();
		});

	// the window's content
	public static function view(viewer:Viewer):View {
		var image = new ImageView(viewer);
		image.onContextMenu = (x, y) -> if (image.ui != null) helder.ui.menu.Menus.popup(image.ui, ViewerActions.context, x, y, image);
		image.style.position = Absolute;
		image.style.left = image.style.top = image.style.right = image.style.bottom = 0;
		// (to assistive technology an image, named as the window is: the file, its place, its size)
		image.semantics = {role: helder.ui.access.Role.Image, label: viewer.title.peek()};
		renderEffect(() -> viewer.title(), t -> image.semantics.label = t);
		// (a change drawn; an animation or a glide ticked on the clock while it lasts)
		var ticking = false, last = -1.0;
		renderEffect(() -> viewer.version(), _ -> {
			image.redraw();
			if (ticking) return;
			ticking = true;
			last = -1;
			Clock.add(t -> {
				var dt = last < 0 ? 0 : Math.min(0.1, t - last);
				last = t;
				var more = viewer.tick(t, dt);
				image.redraw();
				if (!more) ticking = false;
				return more;
			});
		});
		// (Loading… only once a decode takes a moment: no flash on the first frame, nor on a flip to one about to land)
		var slow = signal(false), waitFrom = -1.0;
		renderEffect(() -> viewer.state() == Loading, loading -> {
			slow(false);
			if (!loading || waitFrom >= 0) return;
			waitFrom = 0;
			Clock.add(t -> {
				if (waitFrom == 0) waitFrom = t;
				if (viewer.state.peek() != Loading) {
					waitFrom = -1;
					return false;
				}
				if (t - waitFrom < 0.25) return true;
				waitFrom = -1;
				slow(true);
				return false;
			});
		});
		return <view tag="viewer" grow={1} background="#161618" color="#e4e4e7" font-size={13}>
			{image}
			<Show when={viewer.state() != Shown && (viewer.state() != Loading || slow())}>
				<view tag="message" position="absolute" inset={0} align-items="center" justify="center" row-gap={8} padding={24} pointer-events="none">
					<text tag="title" font-size={17} color={viewer.state() == Failed ? "#fca5a5" : "#e4e4e7"} text-align="center">{viewer.message}</text>
					<text tag="detail" color="#a1a1aa" text-align="center">{viewer.detail}</text>
				</view>
			</Show>
			<Show when={viewer.statusOn() && viewer.status() != ""}>
				<view tag="status" position="absolute" left={0} right={0} bottom={0} padding="6 12" background="#000000b3" direction="row">
					<text color="#d4d4d8">{viewer.status}</text>
				</view>
			</Show>
			<Show when={viewer.pickerOpen()}>
				<view tag="picker-backdrop" position="absolute" inset={0} background="#00000099" align-items="center" justify="center"
					onClick={_ -> viewer.pickerOpen(false)}>
					<view tag="picker" width={420} padding={12} row-gap={8} radius={10} background="#232326" border-width={1} border-color="#3f3f46"
						shadow="0 8px 30px rgba(0, 0, 0, 0.5)" onClick={e -> e.stop()}>
						<text tag="picker-dir" color="#a1a1aa" text-overflow="ellipsis" max-lines={1}>{viewer.pickerDir}</text>
						<VirtualList each={viewer.pickerEntries} itemHeight={28} height={360}>{(entry, i) ->
							<view:button tag={"entry-" + i} role="button" focusable height={28} padding="0 8" justify="center" radius={6}
								background={i % 2 == 0 ? "#26262a" : "#232326"} onPress={() -> viewer.pick(entry())}>
								<text color={StringTools.endsWith(entry(), "/") ? "#93c5fd" : "#e4e4e7"} max-lines={1} dir={helder.ui.Dir.Ltr}>{entry()}</text>
							</view:button>
						}</VirtualList>
					</view>
				</view>
			</Show>
			<Show when={viewer.aboutOpen()}>
				<view tag="about-backdrop" position="absolute" inset={0} background="#00000099" align-items="center" justify="center"
					onClick={_ -> viewer.aboutOpen(false)}>
					<view tag="about" width={340} padding={20} row-gap={6} radius={12} background="#232326" border-width={1} border-color="#3f3f46"
						align-items="center" shadow="0 8px 30px rgba(0, 0, 0, 0.5)">
						<image src={helder.image.Image.decode(helder.asset.Asset.embed("about-icon.png"))} width={72} height={72}/>
						<text tag="about-name" font-size={18} color="#f4f4f5">Viewer</text>
						<text tag="about-version" color="#a1a1aa">{"Version " + Version.NAME}</text>
						<text color="#d4d4d8" text-align="center">helder's image viewer: PNG, JPEG, GIF, WebP, PDF and the system's formats</text>
						<text color="#71717a" text-align="center">MIT License · github.com/benmerckx/helder</text>
					</view>
				</view>
			</Show>
			<Show when={viewer.gotoOpen()}>
				<view tag="goto-backdrop" position="absolute" inset={0} background="#00000066" align-items="center" justify="center"
					onClick={_ -> viewer.gotoOpen(false)}>
					<view tag="goto" width={260} padding={12} row-gap={8} radius={10} background="#232326" border-width={1} border-color="#3f3f46"
						shadow="0 8px 30px rgba(0, 0, 0, 0.5)" onClick={e -> e.stop()}>
						<text color="#a1a1aa">{"Go to page (1–" + viewer.pagesSignal() + ")"}</text>
						<field tag="goto-field" value={viewer.gotoText} placeholder={Std.string(viewer.pageSignal() + 1)} label="Page number" height={28} padding="0 8"
							radius={6} background="#18181b" border-width={1} border-color="#52525b" onInput={e -> viewer.gotoText(e.text)}
							onKeyDown={e -> if (e.key == helder.ui.Key.ENTER) {
								viewer.goToTyped((cast e.current : helder.ui.widgets.TextField).text);
								e.stop();
							}}
							ref={n -> helder.ui.Clock.add(_ -> {
								n.focus();
								false;
							})}/>
					</view>
				</view>
			</Show>
		</view>;
	}
}
