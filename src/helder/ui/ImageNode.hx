package helder.ui;

import helder.image.Image;

// A node showing an Image in its content box, as fit says (Fill by
// default), placed as position says (centred by default; the part outside
// the content box cut), its corners rounded with the node's (radius less
// the border and padding). Its size is the image's when the style gives none, and
// keeps the image's aspect ratio when the style gives one side. An SVG
// drawing (svg) is drawn into its image at the size it is shown in the
// window's pixels (Ui.scale), its currentColor the node's color, again
// when either changes; its size is the drawing's.
class ImageNode extends Node {
	public var image(default, set):Null<Image>;
	public var fit(default, set):ImageFit = Fill;
	// where the image sits in the box (CSS's object-position): each axis a
	// share of the room left over (0: the start, 0.5: centred, 1: the end)
	// and pixels more; position("right 10px top") sets them as CSS writes them
	public var positionX(default, set) = 0.5;
	public var positionY(default, set) = 0.5;
	public var offsetX(default, set) = 0.0;
	public var offsetY(default, set) = 0.0;
	public var svg(default, set):Null<Svg>;
	// drawn flipped where it is right to left (an icon pointing the way the line reads)
	public var mirrored(default, set) = false;
	// what the svg was last drawn as: its pixel size and colour
	var drawn = "";

	public function new(?image:Image, ?tag:String) {
		super(tag == null ? "image" : tag);
		this.image = image;
	}

	// (the size laid out with: the same image may change size, Image.replace)
	var laidWidth = 0;
	var laidHeight = 0;
	var setVersion = 0;

	function set_image(v:Null<Image>):Null<Image> {
		if (v == image && (v == null || v.width == laidWidth && v.height == laidHeight)) {
			// (set again after a change: drawn again)
			if (v != null && v.version != setVersion && ui != null) ui.requestFrame();
			if (v != null) setVersion = v.version;
			return v;
		}
		setVersion = v == null ? 0 : v.version;
		var resized = v == null || image == null || v.width != laidWidth || v.height != laidHeight;
		image = v;
		laidWidth = v == null ? 0 : v.width;
		laidHeight = v == null ? 0 : v.height;
		if (resized) markDirty() else if (ui != null) ui.requestFrame();
		return v;
	}

	function set_svg(v:Null<Svg>):Null<Svg> {
		if (v == svg) return v;
		svg = v;
		drawn = "";
		markDirty();
		return v;
	}

	// the size it has by itself: the drawing's, else the image's
	inline function intrinsicWidth():Float
		return svg != null ? svg.width : image.width;

	inline function intrinsicHeight():Float
		return svg != null ? svg.height : image.height;

	function set_mirrored(v:Bool):Bool {
		if (v != mirrored && ui != null) ui.requestFrame();
		return mirrored = v;
	}

	function set_positionX(v:Float):Float {
		if (v != positionX && ui != null) ui.requestFrame();
		return positionX = v;
	}

	function set_positionY(v:Float):Float {
		if (v != positionY && ui != null) ui.requestFrame();
		return positionY = v;
	}

	function set_offsetX(v:Float):Float {
		if (v != offsetX && ui != null) ui.requestFrame();
		return offsetX = v;
	}

	function set_offsetY(v:Float):Float {
		if (v != offsetY && ui != null) ui.requestFrame();
		return offsetY = v;
	}

	// CSS's object-position: one or two of left, center, right, top,
	// bottom, a percentage or a length ("left top", "25% 75%", "10px 20px",
	// "right 10px bottom 5px"); one value centres the other axis
	public function position(s:String) {
		var px = 0.5, py = 0.5, ox = 0.0, oy = 0.0;
		var words = [for (w in StringTools.trim(s).split(" ")) if (w != "") w];
		inline function bad():Dynamic
			throw 'helder.ui: position "$s" is not CSS\'s object-position';
		function length(w:String):Null<{share:Float, px:Float}> {
			if (StringTools.endsWith(w, "%")) {
				var f = Std.parseFloat(w.substr(0, w.length - 1));
				return Math.isNaN(f) ? null : {share: f / 100, px: 0.0};
			}
			var f = Std.parseFloat(StringTools.endsWith(w, "px") ? w.substr(0, w.length - 2) : w);
			return Math.isNaN(f) || !Dim.isPixels(w) ? null : {share: 0.0, px: f};
		}
		// (keyword with an offset from its side: right 10px, bottom 5px)
		var i = 0, axis = 0, xSet = false, ySet = false;
		while (i < words.length) {
			var w = words[i], next = i + 1 < words.length ? length(words[i + 1]) : null;
			switch w {
				case "left" | "right":
					px = w == "left" ? 0 : 1;
					if (next != null && words.length >= 3) {
						ox = w == "left" ? next.px : -next.px;
						i++;
					}
					xSet = true;
				case "top" | "bottom":
					py = w == "top" ? 0 : 1;
					if (next != null && words.length >= 3) {
						oy = w == "top" ? next.px : -next.px;
						i++;
					}
					ySet = true;
				case "center":
					if (axis == 0 && !xSet) xSet = true else ySet = true;
				case _:
					var l = length(w);
					if (l == null) bad();
					if (axis == 0 && !xSet) {
						px = l.share;
						ox = l.px;
						xSet = true;
					} else {
						py = l.share;
						oy = l.px;
						ySet = true;
					}
			}
			axis++;
			i++;
		}
		if (words.length == 0 || words.length > 4) bad();
		positionX = px;
		positionY = py;
		offsetX = ox;
		offsetY = oy;
	}

	function set_fit(v:ImageFit):ImageFit {
		if (v == fit) return v;
		fit = v;
		if (ui != null) ui.requestFrame();
		return v;
	}

	override public function hasContent():Bool
		return true;

	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		if (image == null && svg == null) return new Size(Math.isNaN(knownWidth) ? 0 : knownWidth, Math.isNaN(knownHeight) ? 0 : knownHeight);
		var iw = intrinsicWidth(), ih = intrinsicHeight();
		var kw = !Math.isNaN(knownWidth), kh = !Math.isNaN(knownHeight);
		return if (kw && kh) new Size(knownWidth, knownHeight) else if (kw) new Size(knownWidth, knownWidth * ih / iw) else if (kh)
			new Size(knownHeight * iw / ih, knownHeight) else new Size(iw, ih);
	}

	// the image's rectangle in a box of w x h at (x, y) and the part of the
	// image drawn (u0, v0, u1, v1 in 0...1): x, y, w, h, u0, v0, u1, v1
	public function placement(x:Float, y:Float, w:Float, h:Float):Array<Float> {
		var iw = intrinsicWidth(), ih = intrinsicHeight();
		// (the image's size scaled as fit says)
		var s = switch fit {
			case Contain: Math.min(w / iw, h / ih);
			case Cover: Math.max(w / iw, h / ih);
			case _: 1.0;
		}
		var dw = fit == Fill ? w : iw * s, dh = fit == Fill ? h : ih * s;
		// (placed by position in the room left over, which is negative when it is larger; the part outside the box cut)
		var ix = x + positionX * (w - dw) + offsetX, iy = y + positionY * (h - dh) + offsetY;
		var x0 = Math.max(x, ix), y0 = Math.max(y, iy), x1 = Math.min(x + w, ix + dw), y1 = Math.min(y + h, iy + dh);
		if (x1 <= x0 || y1 <= y0) return [x, y, 0, 0, 0, 0, 0, 0];
		return [x0, y0, x1 - x0, y1 - y0, (x0 - ix) / dw, (y0 - iy) / dh, (x1 - ix) / dw, (y1 - iy) / dh];
	}

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if ((image == null && svg == null) || width <= 0 || height <= 0) return;
		var p = placement(x, y, width, height);
		if (p[2] <= 0 || p[3] <= 0) return;
		if (svg != null) {
			// (drawn at the pixels it covers: the whole drawing scaled, its part shown cut by u, v)
			var k = ui != null ? ui.scale : 1.0;
			var fw = p[2] / (p[6] - p[4]), fh = p[3] / (p[7] - p[5]);
			var pw = Std.int(Math.max(1, Math.round(fw * k))), ph = Std.int(Math.max(1, Math.round(fh * k))), c = textColor();
			var key = pw + "x" + ph + " " + c;
			if (key != drawn) {
				drawn = key;
				@:bypassAccessor image = svg.render(pw, ph, c);
			}
		}
		var s = style, be = s.borderEdges;
		var inset = Math.max(Math.max(be.left, be.right), Math.max(be.top, be.bottom))
			+ Math.max(Math.max(s.padding.left, s.padding.right), Math.max(s.padding.top, s.padding.bottom));
		var flip = mirrored && rtl();
		if (flip) canvas.pushTransform(-1, 0, 0, 1, 2 * x + width, 0);
		canvas.image(image, p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], Math.max(0, s.radius - inset), s.corners == null ? null : s.cornerRadii().grow(-inset));
		if (flip) canvas.popTransform();
	}
}
