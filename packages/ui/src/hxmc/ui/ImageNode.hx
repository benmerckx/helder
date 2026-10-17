package hxmc.ui;

// A node showing an Image in its content box, as fit says (Fill by
// default), its corners rounded with the node's (radius less the border
// and padding). Its size is the image's when the style gives none, and
// keeps the image's aspect ratio when the style gives one side. An SVG
// drawing (svg) is drawn into its image at the size it is shown in the
// window's pixels (Ui.scale), its currentColor the node's color, again
// when either changes; its size is the drawing's.
class ImageNode extends Node {
	public var image(default, set):Null<Image>;
	public var fit(default, set):ImageFit = Fill;
	public var svg(default, set):Null<Svg>;
	// what the svg was last drawn as: its pixel size and colour
	var drawn = "";

	public function new(?image:Image, ?tag:String) {
		super(tag == null ? "image" : tag);
		this.image = image;
	}

	function set_image(v:Null<Image>):Null<Image> {
		if (v == image) return v;
		var resized = v == null || image == null || v.width != image.width || v.height != image.height;
		image = v;
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
		switch fit {
			case Fill:
				return [x, y, w, h, 0, 0, 1, 1];
			case Contain:
				var s = Math.min(w / iw, h / ih), dw = iw * s, dh = ih * s;
				return [x + (w - dw) / 2, y + (h - dh) / 2, dw, dh, 0, 0, 1, 1];
			case Cover | None:
				var s = fit == Cover ? Math.max(w / iw, h / ih) : 1.0;
				var dw = iw * s, dh = ih * s;
				// (the image's size scaled; the box shows its middle, the rest cut)
				var cw = Math.min(w, dw), ch = Math.min(h, dh);
				var u = (dw - cw) / 2 / dw, v = (dh - ch) / 2 / dh;
				return [x + (w - cw) / 2, y + (h - ch) / 2, cw, ch, u, v, 1 - u, 1 - v];
		}
	}

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if ((image == null && svg == null) || width <= 0 || height <= 0) return;
		var p = placement(x, y, width, height);
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
		var s = style, inset = s.borderWidth + Math.max(Math.max(s.padding.left, s.padding.right), Math.max(s.padding.top, s.padding.bottom));
		canvas.image(image, p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], Math.max(0, s.radius - inset));
	}
}
