package studio;

// Snapping a box being moved or resized on the canvas: its moving edges
// (and its centre, when the whole box moves) to the lines of the boxes
// around it (their edges and centres: a frame's and its siblings', or the
// other frames'), on each axis the nearest within near, each line it meets
// a guide drawn across both boxes.
class Snap {
	// box b's edges moving (which: left, right, top, bottom; all four: a
	// move) snapped to targets' lines within near: the box, the guides
	public static function box(b:Box, edges:Edges, targets:Array<Box>, near:Float):{box:Box, guides:Array<Guide>} {
		var move = edges.left && edges.right;
		var xs = (edges.left ? [b.x] : []).concat(move ? [b.x + b.width / 2] : []).concat(edges.right ? [b.x + b.width] : []);
		var vmove = edges.top && edges.bottom;
		var ys = (edges.top ? [b.y] : []).concat(vmove ? [b.y + b.height / 2] : []).concat(edges.bottom ? [b.y + b.height] : []);
		var sx = axis(xs, [for (t in targets) for (v in [t.x, t.x + t.width / 2, t.x + t.width]) v], near);
		var sy = axis(ys, [for (t in targets) for (v in [t.y, t.y + t.height / 2, t.y + t.height]) v], near);
		var x = b.x, y = b.y, w = b.width, h = b.height;
		// (a move shifts the box; an edge dragged alone resizes it)
		if (sx != null) {
			if (edges.left) x += sx.by;
			if (!move) w += edges.left ? -sx.by : sx.by;
		}
		if (sy != null) {
			if (edges.top) y += sy.by;
			if (!vmove) h += edges.top ? -sy.by : sy.by;
		}
		var out:Box = {x: x, y: y, width: w, height: h};
		var guides:Array<Guide> = [];
		if (sx != null) guides.push(guide(true, sx.at, out, targets));
		if (sy != null) guides.push(guide(false, sy.at, out, targets));
		return {box: out, guides: guides};
	}

	// the nearest of lines to any of moving within near: how far to move, to which line (null: none)
	public static function axis(moving:Array<Float>, lines:Array<Float>, near:Float):Null<{by:Float, at:Float}> {
		var best:Null<{by:Float, at:Float}> = null;
		for (m in moving)
			for (l in lines)
				if (Math.abs(l - m) <= near && (best == null || Math.abs(l - m) < Math.abs(best.by))) best = {by: l - m, at: l};
		return best;
	}

	// (a line at at, across the box and every target on it)
	static function guide(vertical:Bool, at:Float, b:Box, targets:Array<Box>):Guide {
		var from = vertical ? b.y : b.x, to = vertical ? b.y + b.height : b.x + b.width;
		for (t in targets) {
			var lines = vertical ? [t.x, t.x + t.width / 2, t.x + t.width] : [t.y, t.y + t.height / 2, t.y + t.height];
			if (!Lambda.exists(lines, l -> Math.abs(l - at) < 0.001)) continue;
			from = Math.min(from, vertical ? t.y : t.x);
			to = Math.max(to, vertical ? t.y + t.height : t.x + t.width);
		}
		return {vertical: vertical, at: at, from: from, to: to};
	}
}

typedef Box = {x:Float, y:Float, width:Float, height:Float};
typedef Edges = {left:Bool, right:Bool, top:Bool, bottom:Bool};
// a line drawn while snapped: vertical at x = at from y = from to to, or horizontal
typedef Guide = {vertical:Bool, at:Float, from:Float, to:Float};
