package helder.ui;

// A box shadow (Style.shadow): the node's rounded rectangle offset by x, y,
// grown by spread and blurred as CSS blurs it (a Gaussian whose standard
// deviation is half of blur), drawn outside the node under its background;
// inset: cast inward inside its padding box, over the background, by the
// edge of the rectangle offset and shrunk by spread. Parsed as CSS writes
// it: "0 2 8 #00000040", "inset 0 1px 3px rgba(0, 0, 0, 0.3)" (x, y, blur,
// spread optional, the colour first or last, any CSS colour), several
// separated by commas (next: the one after; the first drawn on top);
// "none": NONE, no shadow. As a text shadow (Style.textShadow) the
// glyphs' shapes instead, blurred the same; spread and inset left out,
// and without a colour the text's (currentColor: CSS's default, for a box
// shadow too, which keeps its translucent black instead).
@:structInit class Shadow {
	public var x:Float = 0;
	public var y:Float = 0;
	public var blur:Float = 0;
	public var spread:Float = 0;
	public var color:Color = 0x40000000;
	public var inset:Bool = false;
	public var next:Null<Shadow> = null;
	// (no colour given: a text shadow takes the text's)
	public var currentColor:Bool = false;

	// no shadow (CSS's none): drawn as none, and a text shadow it sets stops its ancestors'
	public static final NONE:Shadow = {};

	// shadows a fraction k of the way from a to b (null or none: no
	// shadow), as CSS interpolates them: shadow by shadow, the shorter list
	// (or none) taken as transparent shadows of no size; inset against not:
	// no easing (b's at the end)
	public static function between(a:Null<Shadow>, b:Null<Shadow>, k:Float):Null<Shadow> {
		if (a == NONE) a = null;
		if (b == NONE) b = null;
		if (a == null && b == null) return b;
		var first:Null<Shadow> = null, last:Null<Shadow> = null, x = a, y = b;
		while (x != null || y != null) {
			var p:Shadow = x ?? {color: Color.TRANSPARENT, inset: y.inset}, q:Shadow = y ?? {color: Color.TRANSPARENT, inset: x.inset};
			if (p.inset != q.inset) return k < 1 ? a : b;
			var c:Shadow = {
				x: p.x + (q.x - p.x) * k,
				y: p.y + (q.y - p.y) * k,
				blur: Math.max(0, p.blur + (q.blur - p.blur) * k),
				spread: p.spread + (q.spread - p.spread) * k,
				color: Color.between(x == null ? q.color.fade(0) : p.color, y == null ? p.color.fade(0) : q.color, k),
				inset: p.inset,
				currentColor: p.currentColor
			};
			if (first == null) first = c else last.next = c;
			last = c;
			x = x?.next;
			y = y?.next;
		}
		return first;
	}

	public static function parse(s:String):Shadow {
		if (StringTools.trim(s) == "none") return NONE;
		return list(s);
	}

	static function list(s:String):Shadow {
		var first:Null<Shadow> = null, last:Null<Shadow> = null;
		for (part in split(s, ",".code)) {
			var sh = one(part, s);
			if (first == null) first = sh else last.next = sh;
			last = sh;
		}
		if (first == null) throw "Shadow.parse: " + s;
		return first;
	}

	static function one(part:String, whole:String):Shadow {
		var lengths:Array<Float> = [], color:Null<Color> = null, inset = false;
		for (p in split(part, " ".code)) {
			if (p == "inset") {
				inset = true;
				continue;
			}
			var f = isLength(p) ? Std.parseFloat(StringTools.replace(p, "px", "")) : Math.NaN;
			if (!Math.isNaN(f)) {
				lengths.push(f);
				continue;
			}
			var c = Color.tryParse(p);
			if (c == null || color != null) throw "Shadow.parse: " + whole;
			color = c;
		}
		if (lengths.length < 2 || lengths.length > 4) throw "Shadow.parse: " + whole;
		var sh:Shadow = {x: lengths[0], y: lengths[1], inset: inset};
		if (lengths.length > 2) sh.blur = lengths[2];
		if (lengths.length > 3) sh.spread = lengths[3];
		if (color != null) sh.color = color else sh.currentColor = true;
		return sh;
	}

	// (a number, px allowed: -1.5, 3px)
	static function isLength(p:String):Bool {
		var n = StringTools.endsWith(p, "px") ? p.length - 2 : p.length;
		if (n == 0) return false;
		for (i in 0...n) {
			var c = StringTools.fastCodeAt(p, i);
			if (!(c >= "0".code && c <= "9".code || c == ".".code || i == 0 && c == "-".code)) return false;
		}
		return true;
	}

	// the parts of s between separators outside parentheses, trimmed, empty ones left out
	static function split(s:String, sep:Int):Array<String> {
		var out = [], depth = 0, start = 0;
		for (i in 0...s.length + 1) {
			var c = i < s.length ? StringTools.fastCodeAt(s, i) : sep;
			if (c == "(".code) depth++ else if (c == ")".code) depth-- else if (depth == 0 && (c == sep || sep == " ".code && c == "\t".code)) {
				var p = StringTools.trim(s.substring(start, i));
				if (p != "") out.push(p);
				start = i + 1;
			}
		}
		return out;
	}

	// the shadows in the order CSS paints them (the last first, under the others)
	public function painted():Array<Shadow> {
		var all = [], sh:Null<Shadow> = this == NONE ? null : this;
		while (sh != null) {
			all.unshift(sh);
			sh = sh.next;
		}
		return all;
	}
}
