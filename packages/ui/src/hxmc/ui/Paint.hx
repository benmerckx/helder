package hxmc.ui;

// what a path is filled or stroked with (Canvas.path): a colour, or a CSS
// gradient over the path's bounds
abstract Paint(PaintValue) from PaintValue to PaintValue {
	@:from static inline function ofColor(c:Color):Paint
		return Solid(c);

	@:from static inline function ofInt(c:Int):Paint
		return Solid(c);

	@:from static inline function ofGradient(g:Gradient):Paint
		return Gradient(g);
}

enum PaintValue {
	Solid(c:Color);
	Gradient(g:Gradient);
}
