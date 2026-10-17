package hxmc.ui;

// A box shadow (Style.shadow): the node's rounded rectangle offset by x, y,
// grown by spread and blurred as CSS blurs it (a Gaussian whose standard
// deviation is half of blur), drawn outside the node under its background;
// inset: cast inward inside its padding box, over the background, by the
// edge of the rectangle offset and shrunk by spread. Parsed as CSS writes
// it: "0 2 8 #00000040", "inset 0 1px 3px rgba(0, 0, 0, 0.3)" (x, y, blur,
// spread optional, the colour first or last, any CSS colour), several
// separated by commas (next: the one after; the first drawn on top).
@:structInit class Shadow {
	public var x:Float = 0;
	public var y:Float = 0;
	public var blur:Float = 0;
	public var spread:Float = 0;
	public var color:Color = 0x40000000;
	public var inset:Bool = false;
	public var next:Null<Shadow> = null;

	public static function parse(s:String):Shadow {
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
			var f = Std.parseFloat(StringTools.replace(p, "px", ""));
			if (!Math.isNaN(f) && ~/^-?[0-9.]+(px)?$/.match(p)) {
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
		if (color != null) sh.color = color;
		return sh;
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
		var all = [], sh:Null<Shadow> = this;
		while (sh != null) {
			all.unshift(sh);
			sh = sh.next;
		}
		return all;
	}
}
