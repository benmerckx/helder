package helder.story;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.story.Story;
import helder.ui.*;
import helder.ui.draw.*;
import helder.view.*;

// The screenshots of the stories with store: true, the one place an app's
// screenshots come from: the stores' and helder.run's. Each rendered
// offscreen on the GPU (helder.gfx's headless surface: Mesa's llvmpipe on
// Linux) at a size as a real layout (the size in points, the screen's
// scale), text in the system's fonts (DrawText), in a ScreenContext of its
// own whose clock is the shot's alone (Ui.now reads it): brought to its
// moment frame by frame (Stories.settle: a story that plays, Controls.play,
// laid out and painted each frame, its last one drawn), so a 3D scene
// mid-play comes out as it would on a screen, whatever the machine's speed.
// Written as opaque RGB PNGs (no alpha channel: Apple's rule).
//
// - The stores' (store): at each store's size (SIZES), the story's caption
//   (StoreOptions) in a band over it: <dir>/<size>/<story>.png; the first
//   story with feature: true also as Google Play's feature graphic
//   (FEATURE, no band): <dir>/android-feature/<story>.png.
// - helder.run's (web): at one size (a window's, 1280x800, or a phone's,
//   390x844 at 2x, for a portrait app), no band (helder.run's page shows
//   plain frames), in the stories' order, at most a number of them:
//   <dir>/shot-<n>.png.
//
// Either way <dir>/shots.json lists them (each file's size, story, caption,
// SHA-256 and MD5, which helder publish compares with the stores'). helder
// publish --screenshots and --run build a program of the project's story
// files around main (helder.cli.Shots); a TypeScript project's calls shots
// (helder/story) with its stories.
class StoreShots implements Markup {
	// the stores' sizes (portrait; landscape apps' swapped): App Store
	// Connect's display types, Google Play's image types
	public static final SIZES:Array<{name:String, width:Int, height:Int, scale:Float, store:String, type:String}> = [
		{name: "iphone-6.9", width: 1320, height: 2868, scale: 3, store: "ios", type: "APP_IPHONE_67"},
		{name: "iphone-6.5", width: 1284, height: 2778, scale: 3, store: "ios", type: "APP_IPHONE_65"},
		{name: "ipad-13", width: 2064, height: 2752, scale: 2, store: "ios", type: "APP_IPAD_PRO_3GEN_129"},
		{name: "android-phone", width: 1080, height: 1920, scale: 2.5, store: "android", type: "phoneScreenshots"},
	];
	// Google Play's feature graphic (landscape whatever the app's orientation)
	public static final FEATURE = {name: "android-feature", width: 1024, height: 500, scale: 1.6, store: "android", type: "featureGraphic"};

	// the program's arguments: <dir> portrait|landscape (the stores'), or
	// <dir> web <width>x<height> <scale> <at most> (helder.run's), after the
	// story files' stories are added (Stories.add)
	public static function main() {
		var args = Sys.args();
		var dir = args[0] ?? "bin/store";
		if (args[1] == "web") {
			var size = (args[2] ?? "1280x800").split("x");
			web(dir, Std.parseInt(size[0]) ?? 1280, Std.parseInt(size[1] ?? "") ?? 800, Std.parseFloat(args[3] ?? "1"), Std.parseInt(args[4] ?? "") ?? 8);
		} else
			store(dir, args[1] == "landscape");
	}

	// (TypeScript's shots(stories): main over them; helder/story)
	public static function run(stories:Array<Story>) {
		for (s in stories)
			if (s != null) Stories.add(s);
		main();
	}

	// the stories with store: true, in the order added
	public static function stories():Array<Story>
		return [for (s in Stories.all) if (s.screenshot != null) s];

	// the stores' screenshots: each story at each size, its caption in a band
	public static function store(dir:String, landscape:Bool) {
		var stories = stories();
		if (stories.length == 0) throw "helder.story: no story with store: true (a store screenshot)";
		var list = [];
		for (size in SIZES) {
			var w = landscape ? size.height : size.width, h = landscape ? size.width : size.height;
			for (s in stories) {
				var path = '${size.name}/${s.slug()}.png';
				mkdirs('$dir/${size.name}');
				list.push(save(dir, path, s, shot(s, w, h, size.scale), w, h, {size: size.name, store: size.store, type: size.type}));
			}
		}
		var f = Lambda.find(stories, s -> s.screenshot?.feature == true);
		if (f != null) {
			var path = '${FEATURE.name}/${f.slug()}.png';
			mkdirs('$dir/${FEATURE.name}');
			list.push(save(dir, path, f, shot(f, FEATURE.width, FEATURE.height, FEATURE.scale, false), FEATURE.width, FEATURE.height, {size: FEATURE.name, store: FEATURE.store, type: FEATURE.type}));
		}
		sys.io.File.saveContent('$dir/shots.json', haxe.Json.stringify(list, null, "  "));
	}

	// helder.run's: the first max stories at width x height pixels (scale: pixels a point), no band;
	// none with store: true, an empty list (helder publish --run takes one of the program instead)
	public static function web(dir:String, width:Int, height:Int, scale:Float, max:Int) {
		var list = [], n = 0;
		mkdirs(dir);
		for (s in stories()) {
			if (n >= max) break;
			var path = 'shot-${++n}.png';
			list.push(save(dir, path, s, shot(s, width, height, scale, false), width, height, {size: "web", store: "run", type: null}));
		}
		sys.io.File.saveContent('$dir/shots.json', haxe.Json.stringify(list, null, "  "));
	}

	static function save(dir:String, path:String, s:Story, png:Bytes, w:Int, h:Int, at:{size:String, store:String, type:Null<String>}):Dynamic {
		sys.io.File.saveBytes('$dir/$path', png);
		Sys.println('store: $path ${w}x$h');
		return {
			file: path,
			size: at.size,
			store: at.store,
			type: at.type,
			story: s.name,
			caption: s.screenshot?.caption,
			width: w,
			height: h,
			sha256: haxe.crypto.Sha256.make(png).toHex(),
			md5: haxe.crypto.Md5.make(png).toHex()
		};
	}

	// (a directory and those above it: an absolute path's too, a drive's on
	// Windows, /'s elsewhere; createDirectory makes the missing parents)
	static function mkdirs(d:String)
		if (!sys.FileSystem.exists(d)) sys.FileSystem.createDirectory(d);

	// (one device, renderer and text engine for every shot, each shot's frames drawn into a target of its size)
	static var gpu:Null<{device:Device, renderer:Renderer, text:DrawText}>;

	// a story at width x height pixels (scale: pixels a point), opaque, as a
	// PNG; caption: its store caption in a band over it (when it has one)
	public static function shot(s:Story, width:Int, height:Int, scale:Float, caption = true):Bytes {
		var g = gpu;
		if (g == null) {
			var d = Device.create(helder.os.Surface.headless(1, 1));
			g = gpu = {device: d, renderer: new Renderer(d), text: new DrawText()};
		}
		final device = g.device, r = g.renderer, text = g.text;
		var target = device.createTexture({width: width, height: height, renderTarget: true});
		device.frameInto(target);
		// (its own clock: the shot's frames, not the machine's)
		var context = new ScreenContext(s.name), now = Ui.now;
		Ui.now = () -> context.now;
		var png = try context.run(() -> {
			var ui = new Ui(text, width / scale, height / scale);
			ui.scale = scale;
			var c = new Controls(s.seed);
			var o = s.screenshot ?? {}, line = caption ? o.caption : null;
			var dispose = Stories.render(s, c, ui.root, line == null ? null : content -> {
				var bg = "#" + StringTools.hex(o.background ?? 0x111827, 6), fg = "#" + StringTools.hex(o.color ?? 0xffffff, 6);
				var band = Math.round(height / scale * 0.14), size = Math.round(width / scale * 0.075);
				<view grow={1} background={bg}>
					<view height={band} align-items="center" justify="center" padding="0 24">
						<text font-size={size} font-weight={700} color={fg}>{line}</text>
					</view>
					<view grow={1}>{content}</view>
				</view>;
			});
			r.scale = scale;
			// (a playing story's frames: laid out and painted, a <Scene>'s
			// controls and sizes stepped; their GPU passes left out, only the
			// moment's frame drawn)
			Stories.settle(ui, c, s.name, () -> {
				r.begin(width, height);
				ui.paint(r);
			});
			var pixels = Bytes.alloc(width * height * 4);
			var enc = device.beginFrame();
			if (enc == null) throw 'helder.story: no frame for ${s.name}';
			r.begin(width, height);
			ui.paint(r);
			// (the passes a texture drawn needs, a <Scene>'s, before the frame's)
			r.prepare(enc);
			enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]});
			r.end(enc);
			enc.endPass();
			device.readPixels(pixels);
			device.endFrame();
			// (what it runs stopped, its GPU targets freed: a <Scene>'s)
			dispose();
			helder.image.PngEncoder.encode(pixels, width, height, true);
		}) catch (e:Dynamic) {
			Ui.now = now;
			device.frameInto(null);
			throw e;
		}
		Ui.now = now;
		device.frameInto(null);
		device.destroyTexture(target);
		return png;
	}
}
