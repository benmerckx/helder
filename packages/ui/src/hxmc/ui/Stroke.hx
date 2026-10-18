package hxmc.ui;

// a path's outline (Canvas.path): its width and paint, the ends of open
// subpaths (cap), the corners (join; a miter longer than miterLimit times
// the width bevelled), dashes (lengths of dashes and gaps, from dashOffset)
typedef Stroke = {
	width:Float,
	paint:Paint,
	?cap:LineCap,
	?join:LineJoin,
	?miterLimit:Float,
	?dashes:Array<Float>,
	?dashOffset:Float
}

enum abstract LineCap(Int) to Int {
	var Butt;
	var Round;
	var Square;
}

enum abstract LineJoin(Int) to Int {
	var Miter;
	var Round;
	var Bevel;
}
