package helder.sprite;

import haxe.Json;

// A sprite sheet's frames by name, read from TexturePacker's JSON (its
// "JSON (Array)" and "JSON (Hash)" formats, which Phaser, PixiJS and most
// 2D libraries read too): each frame's rectangle in the image, whether it
// is stored turned a quarter clockwise (rotated), and its trim (the
// transparent margin cut from the source: spriteSourceSize within
// sourceSize). A frame is drawn about the centre of its source, as the
// sheet's sprites were made (SpriteBatch.sprite).
class Atlas {
	public final frames = new Map<String, AtlasFrame>();
	// the image the sheet was made for (its meta), in pixels
	public var width(default, null) = 0;
	public var height(default, null) = 0;
	// the image's file name, as the sheet names it (meta.image)
	public var image(default, null):Null<String> = null;

	public function new() {}

	// the sheet's JSON (TexturePacker's array or hash format)
	public static function parse(json:String):Atlas {
		var a = new Atlas();
		var d:Dynamic = Json.parse(json);
		if (d.meta != null) {
			a.image = d.meta.image;
			if (d.meta.size != null) {
				a.width = Std.int(d.meta.size.w);
				a.height = Std.int(d.meta.size.h);
			}
		}
		var fs:Dynamic = d.frames;
		if (fs == null) throw "helder.sprite: no frames in the atlas";
		if (fs is Array) {
			for (f in (fs : Array<Dynamic>))
				a.add(frame(Std.string(f.filename), f));
		} else for (name in Reflect.fields(fs))
			a.add(frame(name, Reflect.field(fs, name)));
		return a;
	}

	public function add(f:AtlasFrame)
		frames.set(f.name, f);

	public inline function get(name:String):Null<AtlasFrame>
		return frames.get(name);

	static function frame(name:String, f:Dynamic):AtlasFrame {
		var r:Dynamic = f.frame, rotated = f.rotated == true;
		var w = Std.int(r.w), h = Std.int(r.h);
		var sss:Dynamic = f.spriteSourceSize, ss:Dynamic = f.sourceSize;
		var tx = sss == null ? 0 : Std.int(sss.x), ty = sss == null ? 0 : Std.int(sss.y);
		var sw = ss == null ? w : Std.int(ss.w), sh = ss == null ? h : Std.int(ss.h);
		return new AtlasFrame(name, Std.int(r.x), Std.int(r.y), w, h, rotated, tx, ty, sw, sh);
	}
}

// A frame: its rectangle in the image (x, y and the sprite's own w, h: a
// rotated frame takes h x w pixels there), its trim (the sprite's top left
// within its source, trimX, trimY) and its source's size.
class AtlasFrame {
	public final name:String;
	public final x:Int;
	public final y:Int;
	public final w:Int;
	public final h:Int;
	public final rotated:Bool;
	public final trimX:Int;
	public final trimY:Int;
	public final sourceW:Int;
	public final sourceH:Int;

	public function new(name, x, y, w, h, rotated, trimX, trimY, sourceW, sourceH) {
		this.name = name;
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
		this.rotated = rotated;
		this.trimX = trimX;
		this.trimY = trimY;
		this.sourceW = sourceW;
		this.sourceH = sourceH;
	}
}
