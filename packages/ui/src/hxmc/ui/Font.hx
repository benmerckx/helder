package hxmc.ui;

// A node's resolved text properties (Node.font()): what a TextEngine lays out with
class Font {
	public final family:String;
	public final size:Float;
	public final weight:Int;
	public final italic:Bool;
	// a multiple of size
	public final lineHeight:Float;
	// pixels after each character, and on each space
	public final letterSpacing:Float;
	public final wordSpacing:Float;

	public function new(family:String, size:Float, weight:Int, italic:Bool, lineHeight:Float, letterSpacing = 0.0, wordSpacing = 0.0) {
		this.family = family;
		this.size = size;
		this.weight = weight;
		this.italic = italic;
		this.lineHeight = lineHeight;
		this.letterSpacing = letterSpacing;
		this.wordSpacing = wordSpacing;
	}

	public function equals(f:Font):Bool
		return f != null && family == f.family && size == f.size && weight == f.weight && italic == f.italic && lineHeight == f.lineHeight
			&& letterSpacing == f.letterSpacing && wordSpacing == f.wordSpacing;

	public function toString():String
		return '$family ${size}px $weight' + (italic ? " italic" : "");
}
