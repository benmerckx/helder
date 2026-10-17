import hxmc.ui.*;

// A sample UI built with hxmc.ui's nodes: a toolbar, a sidebar of items, a
// card with wrapped text and buttons (UiDrawTest draws it headless, Demo
// in a window)
class Sample {
	public static function build(root:Node) {
		root.style.background = Color.rgb(0xF4F4F5);
		root.style.fontFamily = "DejaVu Sans";
		root.style.fontSize = 13;
		root.style.color = Color.rgb(0x18181B);
		var bar = box(root, {direction: Row, alignItems: Center, padding: [8, 12], columnGap: 8, background: Color.rgb(0x18181B)});
		var title = text(bar, "hxmc.ui");
		title.style.color = Color.WHITE;
		title.style.fontWeight = 700;
		title.style.fontSize = 15;
		box(bar, {grow: 1});
		for (t in ["File", "Edit", "View"]) {
			var b = text(bar, t);
			b.style.color = Color.rgb(0xD4D4D8);
		}
		// (minHeight 0: the body takes the window's height left, its main part scrolls)
		var body = box(root, {direction: Row, grow: 1, minHeight: 0});
		var side = box(body, {width: 140, shrink: 0, padding: 8, rowGap: 4, background: Color.rgb(0xE4E4E7)});
		for (i in 0...5) {
			var item = box(side, {padding: [6, 8], radius: 6, background: i == 1 ? Color.rgb(0x3B82F6) : Color.TRANSPARENT});
			var t = text(item, ["Inbox", "Projects", "Calendar", "Notes", "Settings"][i]);
			if (i == 1) t.style.color = Color.WHITE;
		}
		// (an image, covering a box with rounded corners)
		var pic = new ImageNode(landscape(96, 64));
		pic.fit = Cover;
		pic.style.set({height: 64, radius: 8, margin: [12, 0, 0, 0]});
		side.append(pic);
		var main = box(body, {grow: 1, padding: 16, rowGap: 12, overflow: Scroll});
		var card = box(main, {padding: 14, rowGap: 10, radius: 10, background: Color.WHITE, borderWidth: 1, borderColor: Color.rgb(0xD4D4D8),
			shadow: {x: 0, y: 3, blur: 8, color: Color.rgba(0x000000, 0.18)}});
		var h = text(card, "Flexbox, text and the GPU");
		h.style.fontSize = 18;
		h.style.fontWeight = 700;
		text(card, "This card is laid out by hxmc.ui's flexbox, its text shaped and wrapped by hxmc.text, and everything drawn by one shader on hxmc.gfx: rounded rectangles with borders, shadows, rounded clips and glyphs from an atlas.");
		// (a rounded clip: the bar's square fill is cut to its track's corners)
		var track = box(card, {height: 12, radius: 6, overflow: Hidden, background: Color.rgb(0xE4E4E7), direction: Row});
		box(track, {width: "62%", background: Color.rgb(0x3B82F6)});
		box(track, {width: 24, background: Color.rgb(0x93C5FD)});
		var row = box(card, {direction: Row, columnGap: 8, justify: End});
		var cancel = box(row, {padding: [6, 14], radius: 6, borderWidth: 1, borderColor: Color.rgb(0xA1A1AA)});
		text(cancel, "Cancel");
		var ok = box(row, {padding: [6, 14], radius: 6, background: Color.rgb(0x16A34A)});
		var okText = text(ok, "Save");
		okText.style.color = Color.WHITE;
		var chips = box(main, {direction: Row, wrap: true, columnGap: 6, rowGap: 6});
		for (c in ["red", "orange", "amber", "green", "teal", "blue", "violet", "pink"]) {
			var chip = box(chips, {padding: [4, 10], radius: 12, background: Color.rgba(0x3B82F6, 0.15)});
			text(chip, c);
		}
		var faded = box(main, {padding: 10, radius: 8, background: Color.rgb(0xFDE68A), opacity: 0.5});
		text(faded, "Half opaque: opacity applies to a subtree.");
	}

	// a landscape drawn pixel by pixel: sky, a sun, hills (an image without a file)
	public static function landscape(w:Int, h:Int):Image {
		var img = new Image(w, h);
		for (y in 0...h)
			for (x in 0...w) {
				var fx = x / w, fy = y / h;
				var r = 96 + 80 * fy, g = 165 + 60 * fy, b = 250 - 20 * fy;
				var dx = fx - 0.75, dy = fy - 0.3, sun = Math.sqrt(dx * dx * w * w + dy * dy * h * h) / (h * 0.16);
				if (sun < 1) {
					r = 253;
					g = 224 - 40 * sun;
					b = 71;
				}
				var hill = 0.62 + 0.1 * Math.sin(fx * 7.0), far = 0.55 + 0.08 * Math.sin(fx * 4.0 + 1.3);
				if (fy > far) {
					r = 74;
					g = 158 - 30 * (fy - far);
					b = 110;
				}
				if (fy > hill) {
					r = 34 + 20 * fy;
					g = 120 + 30 * fy;
					b = 60;
				}
				var o = 4 * (y * w + x);
				img.pixels.set(o, Std.int(r));
				img.pixels.set(o + 1, Std.int(g));
				img.pixels.set(o + 2, Std.int(b));
				img.pixels.set(o + 3, 255);
			}
		return img;
	}

	public static function box(parent:Node, style:StyleProps):Node {
		var n = new Node();
		n.style.set(style);
		parent.append(n);
		return n;
	}

	public static function text(parent:Node, s:String):TextNode {
		var t = new TextNode(s);
		parent.append(t);
		return t;
	}
}
