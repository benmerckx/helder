package helder.story;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.story.Story;
import helder.ui.*;
import helder.ui.draw.*;
import helder.view.*;

// The store screenshots of the stories with store: true: each rendered
// offscreen on the GPU (helder.gfx's headless surface: Mesa's llvmpipe on
// Linux) at each store's size as a real layout (the size in points, the
// screen's scale), text in the system's fonts (DrawText), its caption
// (StoreOptions) in a band over it, then written as an opaque RGB PNG (no
// alpha channel: Apple's rule): <dir>/<size>/<story>.png, and
// <dir>/shots.json (each file's size, story, SHA-256 and MD5, which
// helder publish compares with the stores'). helder publish --screenshots
// builds a program of the project's story files around main.
class StoreShots implements Markup {
	// the stores' sizes (portrait; landscape apps' swapped): App Store
	// Connect's display types, Google Play's image types
	public static final SIZES:Array<{name:String, width:Int, height:Int, scale:Float, store:String, type:String}> = [
		{name: "iphone-6.9", width: 1320, height: 2868, scale: 3, store: "ios", type: "APP_IPHONE_67"},
		{name: "iphone-6.5", width: 1284, height: 2778, scale: 3, store: "ios", type: "APP_IPHONE_65"},
		{name: "ipad-13", width: 2064, height: 2752, scale: 2, store: "ios", type: "APP_IPAD_PRO_3GEN_129"},
		{name: "android-phone", width: 1080, height: 1920, scale: 2.5, store: "android", type: "phoneScreenshots"},
	];

	// helder publish's program: StoreShots.main(<dir>, portrait|landscape) after the story files' stories are added (Stories.add)
	public static function main() {
		var args = Sys.args();
		var dir = args[0] ?? "bin/store", landscape = args[1] == "landscape";
		var stories = [for (s in Stories.all) if (s.screenshot != null) s];
		if (stories.length == 0) throw "helder.story: no story with store: true (a store screenshot)";
		var list = [];
		for (size in SIZES) {
			var w = landscape ? size.height : size.width, h = landscape ? size.width : size.height;
			for (s in stories) {
				var png = shot(s, w, h, size.scale);
				var path = '${size.name}/${s.slug()}.png';
				mkdirs('$dir/${size.name}');
				sys.io.File.saveBytes('$dir/$path', png);
				list.push({
					file: path,
					size: size.name,
					store: size.store,
					type: size.type,
					story: s.name,
					caption: s.screenshot.caption,
					width: w,
					height: h,
					sha256: haxe.crypto.Sha256.make(png).toHex(),
					md5: haxe.crypto.Md5.make(png).toHex()
				});
				Sys.println('store: $path ${w}x$h');
			}
		}
		sys.io.File.saveContent('$dir/shots.json', haxe.Json.stringify(list, null, "  "));
	}

	static function mkdirs(d:String)
		if (!sys.FileSystem.exists(d)) sys.FileSystem.createDirectory(d);

	// a story at width x height pixels (scale: pixels a point), opaque, as a PNG
	public static function shot(s:Story, width:Int, height:Int, scale:Float):Bytes {
		var device = Device.create(helder.os.Surface.headless(width, height));
		var ui = new Ui(new DrawText(), width / scale, height / scale);
		ui.scale = scale;
		var c = new Controls(s.seed);
		var o = s.screenshot;
		var content = s.build(c);
		if (o.caption != null) {
			var bg = "#" + StringTools.hex(o.background ?? 0x111827, 6), fg = "#" + StringTools.hex(o.color ?? 0xffffff, 6);
			var band = Math.round(height / scale * 0.14), size = Math.round(width / scale * 0.075);
			Render.render(<view grow={1} background={bg}>
				<view height={band} align-items="center" justify="center" padding="0 24">
					<text font-size={size} font-weight={700} color={fg}>{o.caption}</text>
				</view>
				<view grow={1}>{content}</view>
			</view>, ui.root);
		} else
			Render.render(content, ui.root);
		Stories.settle(ui, c);
		var r = new Renderer(device);
		r.scale = scale;
		var pixels = Bytes.alloc(width * height * 4);
		var enc = device.beginFrame();
		enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]});
		r.begin(width, height);
		ui.paint(r);
		r.end(enc);
		enc.endPass();
		device.readPixels(pixels);
		device.endFrame();
		device.dispose();
		return helder.image.PngEncoder.encode(pixels, width, height, true);
	}
}
