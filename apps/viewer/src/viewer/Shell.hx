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
import viewer.Decode.Decoded;

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
		viewer.statusOn(num("status", 0) == 1);
		// (--exit-after s: the window closed after s seconds, the title and
		// state printed: a smoke run of the real window and GPU, CI's)
		var exitAfter = args.indexOf("--exit-after") >= 0 ? Std.parseFloat(args[args.indexOf("--exit-after") + 1]) : -1.0;
		var path = [for (i in 0...args.length) if (!StringTools.startsWith(args[i], "-") && (i == 0 || args[i - 1] != "--exit-after")) args[i]][0];
		if (path != null) viewer.open(path) else @:privateAccess viewer.empty();
		var window:Null<UiWindow> = null;
		UiWindow.run(<Surface title={viewer.title} width={num("width", 1100)} height={num("height", 760)} background="#161618" dark={true}
			onDrop={(files, x, y) -> if (files.length > 0) viewer.open(files[0])}
			onClose={() -> {
				save(store, window, viewer);
				window.close();
			}}
			ref={w -> {
				window = w;
				w.window.setMinSize(320, 240);
				if (store != null && store.exists("x") && store.exists("y")) w.window.moveTo(num("x", 0), num("y", 0));
				attach(w.ui.root, viewer);
				effect(() -> viewer.fullscreen(), on -> w.window.fullscreen = on);
				if (exitAfter >= 0) Async.launch(_ -> {
					Async.delay(exitAfter);
					Sys.println('viewer: ${viewer.title.peek()} (${viewer.state.peek()}${viewer.message.peek() == "" ? "" : ": " + viewer.message.peek()}, ${viewer.camera.percent()}%, ${w.window.width}x${w.window.height})');
					w.close();
				});
			}}>
			{view(viewer)}
		</Surface>);
	}

	// the viewer's own font (DejaVu Sans, a subset: fonts/README.md), added
	// only when the system has none it finds (a bare Wine prefix, a minimal
	// container): never stopped for lack of one
	public static function fallbackFont() {
		var fonts = helder.text.SystemFonts.get();
		if (fonts.match("sans-serif") == null) fonts.add(helder.asset.Asset.embed("fonts/DejaVuSans-viewer.ttf"));
	}

	// (the decode on a pool's thread: Decode.job)
	static function jobDecode(path:String, done:Decoded->Void)
		Async.launch(_ -> done(Decode.job(path)));

	static function save(store:Null<helder.os.Store>, w:Null<UiWindow>, viewer:Viewer) {
		if (store == null || w == null) return;
		store.set("status", viewer.statusOn.peek() ? "1" : "0");
		if (viewer.fullscreen.peek()) return;
		var k = w.window.scale > 0 ? w.window.scale : 1;
		var p = w.window.position();
		if (p != null) {
			store.set("x", Std.string(p.x));
			store.set("y", Std.string(p.y));
		}
		store.set("width", Std.string(Math.round(w.window.width / k)));
		store.set("height", Std.string(Math.round(w.window.height / k)));
	}

	// the keys reaching the root (no focused node took them), the folder watched
	public static function attach(root:Node, viewer:Viewer, watch = true) {
		root.onKeyDown = e -> if (viewer.key(e.key, e.mods)) e.preventDefault();
		root.onTextInput = e -> if (viewer.typed(e.text)) e.preventDefault();
		if (watch) Async.launch(_ -> while (true) {
			Async.delay(1);
			viewer.watch();
		});
	}

	// the window's content
	public static function view(viewer:Viewer):View {
		var image = new ImageView(viewer);
		image.style.position = Absolute;
		image.style.left = image.style.top = image.style.right = image.style.bottom = 0;
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
		return <view tag="viewer" grow={1} background="#161618" color="#e4e4e7" font-size={13}>
			{image}
			<Show when={viewer.state() != Shown}>
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
								<text color={StringTools.endsWith(entry(), "/") ? "#93c5fd" : "#e4e4e7"} max-lines={1}>{entry()}</text>
							</view:button>
						}</VirtualList>
					</view>
				</view>
			</Show>
		</view>;
	}
}
