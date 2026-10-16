package hxmc.ui;

// A box shadow (Style.shadow): the node's rounded rectangle offset by x, y,
// grown by spread and faded over blur pixels on each side of its edge, drawn
// under the node's background. Parsed as CSS writes it: "0 2 8 #00000040"
// (x, y, blur, spread optional, the colour last; px units allowed).
@:structInit class Shadow {
	public var x:Float = 0;
	public var y:Float = 0;
	public var blur:Float = 0;
	public var spread:Float = 0;
	public var color:Color = 0x40000000;

	public static function parse(s:String):Shadow {
		var lengths:Array<Float> = [], color:Null<Color> = null;
		for (p in StringTools.trim(s).split(" ")) {
			if (p == "") continue;
			if (p.charAt(0) == "#") {
				color = Color.parse(p);
				continue;
			}
			var f = Std.parseFloat(StringTools.replace(p, "px", ""));
			if (Math.isNaN(f)) throw "Shadow.parse: " + s;
			lengths.push(f);
		}
		if (lengths.length < 2 || lengths.length > 4) throw "Shadow.parse: " + s;
		var sh:Shadow = {x: lengths[0], y: lengths[1]};
		if (lengths.length > 2) sh.blur = lengths[2];
		if (lengths.length > 3) sh.spread = lengths[3];
		if (color != null) sh.color = color;
		return sh;
	}
}
