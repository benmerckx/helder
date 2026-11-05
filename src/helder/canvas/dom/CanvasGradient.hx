package helder.canvas.dom;

// The browser's CanvasGradient: linear, radial or conic (a context's
// createLinearGradient...), its stops added with CSS colours
class CanvasGradient {
	@:noCompletion public final gradient:helder.canvas.Gradient;

	@:noCompletion public function new(gradient:helder.canvas.Gradient) {
		this.gradient = gradient;
	}

	public function addColorStop(offset:Float, color:String) {
		if (!(offset >= 0 && offset <= 1)) throw new Path2D.DOMException("IndexSizeError", "The provided value (" + offset + ") is outside the range (0.0, 1.0).");
		var c = Colors.parse(color);
		if (c == null) throw new Path2D.DOMException("SyntaxError", "The value provided ('" + color + "') could not be parsed as a color.");
		gradient.addStop(offset, c);
	}
}
