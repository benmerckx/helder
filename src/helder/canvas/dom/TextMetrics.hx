package helder.canvas.dom;

// The browser's TextMetrics (measureText): the advance, the ink's box
// from the alignment point, the font's and the em box's ascent and
// descent, the baselines from textBaseline's
class TextMetrics {
	public var width(default, null) = 0.0;
	public var actualBoundingBoxLeft(default, null) = 0.0;
	public var actualBoundingBoxRight(default, null) = 0.0;
	public var actualBoundingBoxAscent(default, null) = 0.0;
	public var actualBoundingBoxDescent(default, null) = 0.0;
	public var fontBoundingBoxAscent(default, null) = 0.0;
	public var fontBoundingBoxDescent(default, null) = 0.0;
	public var emHeightAscent(default, null) = 0.0;
	public var emHeightDescent(default, null) = 0.0;
	public var hangingBaseline(default, null) = 0.0;
	public var alphabeticBaseline(default, null) = 0.0;
	public var ideographicBaseline(default, null) = 0.0;

	@:noCompletion public function new() {}

	@:noCompletion public function set(width, left, right, ascent, descent, fontAscent, fontDescent, emAscent, emDescent, hanging, alphabetic,
			ideographic) {
		this.width = width;
		actualBoundingBoxLeft = left;
		actualBoundingBoxRight = right;
		actualBoundingBoxAscent = ascent;
		actualBoundingBoxDescent = descent;
		fontBoundingBoxAscent = fontAscent;
		fontBoundingBoxDescent = fontDescent;
		emHeightAscent = emAscent;
		emHeightDescent = emDescent;
		hangingBaseline = hanging;
		alphabeticBaseline = alphabetic;
		ideographicBaseline = ideographic;
	}
}
