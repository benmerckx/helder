package helder.canvas.dom;

// The browser's CanvasPattern: an image repeated (createPattern), placed by setTransform
class CanvasPattern {
	@:noCompletion public final pattern:helder.canvas.Pattern;

	@:noCompletion public function new(pattern:helder.canvas.Pattern) {
		this.pattern = pattern;
	}

	public function setTransform(?transform:DOMMatrix) {
		if (transform == null) pattern.matrix.identity() else transform.into(pattern.matrix);
	}
}
