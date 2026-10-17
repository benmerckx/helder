package hxmc.text;

// A face and the faces tried after it for characters it lacks (SystemFonts'
// fallbacks, then a lookup of more: SystemFonts' fallbackFor, which loads
// a face when a character first needs it), at a size in pixels: what
// TextLayout shapes with.
class FontSet {
	public final primary:FontFile;
	public final fallbacks:Array<FontFile>;
	public final size:Float;
	public final more:Null<Int->Null<FontFile>>;
	// colour emoji faces (SystemFonts' emojiFor)
	public final emoji:Null<Int->Null<FontFile>>;

	public function new(primary:FontFile, ?fallbacks:Array<FontFile>, size:Float, ?more:Int->Null<FontFile>, ?emoji:Int->Null<FontFile>) {
		this.primary = primary;
		this.more = more;
		this.emoji = emoji;
		this.fallbacks = fallbacks == null ? [] : [for (f in fallbacks) if (f != primary) f];
		this.size = size;
	}

	// pixels per font unit of a face
	public inline function scale(f:FontFile):Float
		return size / f.unitsPerEm;

	// the face that has the character (the primary's .notdef when none does)
	public function faceFor(cp:Int):FontFile {
		if (primary.glyph(cp) != 0) return primary;
		for (f in fallbacks)
			if (f.glyph(cp) != 0) return f;
		if (more != null) {
			var f = more(cp);
			if (f != null) return f;
		}
		if (emoji != null) {
			var f = emoji(cp);
			if (f != null) return f;
		}
		return primary;
	}

	// the face for a character of an emoji's sequence (with VS16, a modifier,
	// a joiner, a flag): a colour face that has it first
	public function emojiFaceFor(cp:Int):FontFile {
		if (primary.hasColor && primary.glyph(cp) != 0) return primary;
		for (f in fallbacks)
			if (f.hasColor && f.glyph(cp) != 0) return f;
		if (emoji != null) {
			var f = emoji(cp);
			if (f != null) return f;
		}
		return faceFor(cp);
	}

	public var ascent(get, never):Float;
	public var descent(get, never):Float;

	inline function get_ascent()
		return primary.ascender * scale(primary);

	// (positive, below the baseline)
	inline function get_descent()
		return -primary.descender * scale(primary);
}
