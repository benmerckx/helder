package helder.canvas;

// How a path is stroked: its width, the joins between segments, the caps
// on open ends, the miter limit, the dashes. Joins and caps are values of
// their own classes (Join.round, Cap.square...), so an app's executable
// keeps only those it uses.
final class Stroke {
	public var width = 1.0;
	public var join:Join = Join.miter;
	public var cap:Cap = Cap.butt;
	// a miter's length over the stroke's width beyond which it is beveled
	public var miterLimit = 10.0;
	// on and off lengths, in the path's units (null: solid)
	public var dash:Null<Dash> = null;
	// a subpath of no length drawn as a dot by round and square caps (as
	// Skia and SVG draw it; Canvas 2D's prunes it: false)
	public var dots = true;

	public function new(width = 1.0) {
		this.width = width;
	}

	public function copyFrom(s:Stroke):Stroke {
		width = s.width;
		join = s.join;
		cap = s.cap;
		miterLimit = s.miterLimit;
		dash = s.dash;
		dots = s.dots;
		return this;
	}
}

// The outer side of a turn (the inner side goes through the point)
interface JoinStyle {
	// 0 miter, 1 round, 2 bevel (a back end that strokes elsewhere: the browser's canvas)
	var kind(get, never):Int;

	// at (x, y), the side's offset points before (ax, ay) and after (bx, by)
	// the turn; (ix, iy) and (jx, jy) the directions in and out; s the side
	function outer(st:Stroker, x:Float, y:Float, ax:Float, ay:Float, bx:Float, by:Float, ix:Float, iy:Float, jx:Float, jy:Float, s:Float,
		cross:Float, dot:Float):Void;
}

@:forward(kind) abstract Join(JoinStyle) from JoinStyle to JoinStyle {
	public static var miter(get, never):Join;
	public static var round(get, never):Join;
	public static var bevel(get, never):Join;

	static inline function get_miter():Join
		return MiterJoin.instance;

	static inline function get_round():Join
		return RoundJoin.instance;

	static inline function get_bevel():Join
		return BevelJoin.instance;
}

final class MiterJoin implements JoinStyle {
	public static final instance = new MiterJoin();

	public var kind(get, never):Int;

	inline function get_kind()
		return 0;

	function new() {}

	public function outer(st:Stroker, x:Float, y:Float, ax:Float, ay:Float, bx:Float, by:Float, ix:Float, iy:Float, jx:Float, jy:Float, s:Float,
			cross:Float, dot:Float) {
		// (the miter's length over the width: 1 / cos(half the turn))
		var cosHalf = Math.sqrt(Math.max(0, (1 + dot) / 2));
		if (cosHalf > 1e-9 && 1 / cosHalf <= st.miterLimit) {
			var mx = -iy - jy, my = ix + jx, ml = Math.sqrt(mx * mx + my * my);
			if (ml > 1e-12) {
				var len = st.halfWidth / cosHalf;
				st.point(x + mx / ml * len * s, y + my / ml * len * s);
			}
		}
	}
}

final class RoundJoin implements JoinStyle {
	public static final instance = new RoundJoin();

	public var kind(get, never):Int;

	inline function get_kind()
		return 1;

	function new() {}

	public function outer(st:Stroker, x:Float, y:Float, ax:Float, ay:Float, bx:Float, by:Float, ix:Float, iy:Float, jx:Float, jy:Float, s:Float,
			cross:Float, dot:Float)
		st.arcPoints(x, y, Math.atan2(ay - y, ax - x), Math.atan2(cross, dot));
}

final class BevelJoin implements JoinStyle {
	public static final instance = new BevelJoin();

	public var kind(get, never):Int;

	inline function get_kind()
		return 2;

	function new() {}

	public function outer(st:Stroker, x:Float, y:Float, ax:Float, ay:Float, bx:Float, by:Float, ix:Float, iy:Float, jx:Float, jy:Float, s:Float,
		cross:Float, dot:Float) {}
}

// An open end: from the left side's end (lx, ly) to the right's (rx, ry),
// the path heading (dx, dy) there
interface CapStyle {
	// 0 butt, 1 round, 2 square
	var kind(get, never):Int;

	function end(st:Stroker, x:Float, y:Float, lx:Float, ly:Float, rx:Float, ry:Float, dx:Float, dy:Float):Void;
	// a zero length subpath's dot at (x, y)
	function dot(st:Stroker, x:Float, y:Float):Void;
}

@:forward(kind) abstract Cap(CapStyle) from CapStyle to CapStyle {
	public static var butt(get, never):Cap;
	public static var round(get, never):Cap;
	public static var square(get, never):Cap;

	static inline function get_butt():Cap
		return ButtCap.instance;

	static inline function get_round():Cap
		return RoundCap.instance;

	static inline function get_square():Cap
		return SquareCap.instance;
}

final class ButtCap implements CapStyle {
	public static final instance = new ButtCap();

	public var kind(get, never):Int;

	inline function get_kind()
		return 0;

	function new() {}

	public function end(st:Stroker, x:Float, y:Float, lx:Float, ly:Float, rx:Float, ry:Float, dx:Float, dy:Float) {}

	public function dot(st:Stroker, x:Float, y:Float) {}
}

final class RoundCap implements CapStyle {
	public static final instance = new RoundCap();

	public var kind(get, never):Int;

	inline function get_kind()
		return 1;

	function new() {}

	public function end(st:Stroker, x:Float, y:Float, lx:Float, ly:Float, rx:Float, ry:Float, dx:Float, dy:Float)
		st.arcPoints(x, y, Math.atan2(ly - y, lx - x), -Math.PI);

	public function dot(st:Stroker, x:Float, y:Float) {
		st.point(x + st.halfWidth, y);
		st.arcPoints(x, y, 0, 2 * Math.PI);
		st.emit();
	}
}

final class SquareCap implements CapStyle {
	public static final instance = new SquareCap();

	public var kind(get, never):Int;

	inline function get_kind()
		return 2;

	function new() {}

	public function end(st:Stroker, x:Float, y:Float, lx:Float, ly:Float, rx:Float, ry:Float, dx:Float, dy:Float) {
		var hw = st.halfWidth;
		st.point(lx + dx * hw, ly + dy * hw);
		st.point(rx + dx * hw, ry + dy * hw);
	}

	public function dot(st:Stroker, x:Float, y:Float) {
		var hw = st.halfWidth;
		st.point(x - hw, y - hw);
		st.point(x + hw, y - hw);
		st.point(x + hw, y + hw);
		st.point(x - hw, y + hw);
		st.emit();
	}
}

// A dash pattern: on and off lengths (an odd count repeated twice, as
// Canvas 2D's setLineDash), from offset into it
final class Dash {
	public final intervals:Array<Float>;
	public final total:Float;
	public var offset:Float;

	public function new(intervals:Array<Float>, offset = 0.0) {
		this.intervals = intervals.length % 2 == 1 ? intervals.concat(intervals) : intervals.copy();
		var t = 0.0;
		for (d in this.intervals)
			t += d;
		total = t;
		this.offset = offset;
	}

	// whether it draws anything other than a solid line (none: all zero)
	public inline function valid():Bool
		return intervals.length > 0 && total > 0 && Math.isFinite(total);
}
