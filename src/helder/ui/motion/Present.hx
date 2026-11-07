package helder.ui.motion;

import helder.canvas.Matrix;

// A node's presented state (Node.present, made when something of it first
// moves): a track per animated property. Its edges are in its parent's
// space (left, top, right, bottom of its border box from the parent's
// presented top left; riding the parent's trailing edge, from its right and
// bottom), so that a child whose layout in its parent stays put rides it
// without moving on its own; its presence (0 absent, 1 present) and the
// effect that plays it; its opacity, corner radius, background, border and
// text colours; its transform as translation, scale and rotation. Where it
// is drawn is where its tracks are (Ui's paint: dx, dy, width, height,
// matrix); Motions steps them on the Clock.
class Present {
	public final node:Node;
	// its edges (null until its layout first moves)
	public var l:Null<Track> = null;
	public var t:Null<Track> = null;
	public var r:Null<Track> = null;
	public var b:Null<Track> = null;
	// (its edges are kept from its parent's right, bottom edge: Node.ride)
	public var rideX = false;
	public var rideY = false;
	// a matched element flying from where its counterpart was seen to its own place (drawn over everything)
	public var flying = false;
	// a matched element whose counterpart flew from it: no longer drawn (inside a node leaving)
	public var away = false;
	public var presence:Null<Track> = null;
	public var effect:Presence = Presence.FADE;
	// leaving: drawn where it was (gx, gy: its left and top in its old
	// parent's presented space, Node.leftFrom) until its presence settles at 0
	public var exiting = false;
	public var gx = 0.0;
	public var gy = 0.0;
	public var opacity:Null<Track> = null;
	public var radius:Null<Track> = null;
	public var background:Null<ColorTrack> = null;
	public var border:Null<ColorTrack> = null;
	public var color:Null<ColorTrack> = null;
	// (the text colour it goes to as the style gives it: null, inherited)
	public var colorTo:Null<Color> = null;
	// its transform as lanes while it moves (translate, scale, rotate in radians)
	public var tx:Null<Track> = null;
	public var ty:Null<Track> = null;
	public var sx:Null<Track> = null;
	public var sy:Null<Track> = null;
	public var rot:Null<Track> = null;
	// (in Motions' list of what moves)
	public var active = false;
	// what is told when its exit has settled (helder.view's For: a row's owner disposed)
	public var onExited:Null<Array<Void->Void>> = null;

	public function new(node:Node)
		this.node = node;

	// whether its edges are kept
	public inline function edges():Bool
		return l != null;

	// (its edges set to a layout rect, x, y, w, h in its parent, still)
	public function setEdges(x:Float, y:Float, w:Float, h:Float, parentW:Float, parentH:Float) {
		var x0 = rideX ? x - parentW : x, y0 = rideY ? y - parentH : y;
		if (l == null) {
			l = new Track(x0, Motions.EDGE_EPS);
			t = new Track(y0, Motions.EDGE_EPS);
			r = new Track(x0 + w, Motions.EDGE_EPS);
			b = new Track(y0 + h, Motions.EDGE_EPS);
		} else {
			l.set(x0);
			t.set(y0);
			r.set(x0 + w);
			b.set(y0 + h);
		}
	}

	// (the parent's presented width and height: what a child riding its trailing edges is placed from)
	static inline function pw(p:Null<Node>):Float
		return p == null ? 0 : p.present != null && p.present.l != null ? p.present.r.value - p.present.l.value : p.width;

	static inline function ph(p:Null<Node>):Float
		return p == null ? 0 : p.present != null && p.present.l != null ? p.present.b.value - p.present.t.value : p.height;

	// how far from its layout it is drawn (in its parent's presented space), across and down
	public function dx():Float {
		if (l == null || exiting) return 0;
		return l.value + (rideX ? pw(node.parent) : 0) - node.x;
	}

	public function dy():Float {
		if (t == null || exiting) return 0;
		return t.value + (rideY ? ph(node.parent) : 0) - node.y;
	}

	// its presented size
	public inline function width():Float
		return l == null ? node.width : Math.max(0, r.value - l.value);

	public inline function height():Float
		return t == null ? node.height : Math.max(0, b.value - t.value);

	// its presence's share of its opacity (presence fades it)
	public inline function presenceOpacity():Float
		return presence == null ? 1 : Math.max(0, Math.min(1, presence.value));

	// whether its presence or its transform's lanes move how it is drawn
	public function transforms():Bool
		return tx != null || presence != null && presence.value < 1 && (effect.scale != 1 || effect.dx != 0 || effect.dy != 0) && !Clock.reducedMotion;

	// the transform it is drawn with, about its origin (ox, oy: window pixels): its presence's scale and
	// slide over its transform's lanes, or over m (the style's transform's matrix about its top left; null: none)
	public function matrix(m:Null<Matrix>, ox:Float, oy:Float, stickyX:Float, stickyY:Float):Matrix {
		var out = new Matrix();
		if (tx != null) {
			out.translate(tx.value, ty.value);
			out.rotate(rot.value);
			out.scale(sx.value, sy.value);
		} else if (m != null) out.copyFrom(m);
		if (presence != null && presence.value < 1 && !Clock.reducedMotion) {
			var k = 1 - Math.max(0, Math.min(1, presence.value)), s = 1 + (effect.scale - 1) * k;
			// (the slide and scale applied after the transform: p' = slide + s * M p)
			out.premultiply(new Matrix(s, 0, 0, s, effect.dx * k, effect.dy * k));
		}
		out.e += ox - (out.a * ox + out.c * oy) + stickyX;
		out.f += oy - (out.b * ox + out.d * oy) + stickyY;
		return out;
	}

	// whether any of its tracks still moves
	public function moving():Bool {
		return l != null && (l.moving() || t.moving() || r.moving() || b.moving()) || presence != null && presence.moving() || opacity != null
			&& opacity.moving() || radius != null && radius.moving() || background != null && background.moving() || border != null
			&& border.moving() || color != null && color.moving() || tx != null;
	}

	// the transform's lanes set from a matrix's translation, rotation and scale
	public function setLanes(m:Null<Matrix>) {
		var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0;
		if (m != null) {
			a = m.a;
			b = m.b;
			c = m.c;
			d = m.d;
			e = m.e;
			f = m.f;
		}
		var s = Math.sqrt(a * a + b * b), turn = Math.atan2(b, a), t = s == 0 ? 1.0 : (a * d - b * c) / s;
		if (tx == null) {
			tx = new Track(e, Motions.EDGE_EPS);
			ty = new Track(f, Motions.EDGE_EPS);
			sx = new Track(s, 1e-4);
			sy = new Track(t, 1e-4);
			rot = new Track(turn, 1e-4);
		} else {
			tx.set(e);
			ty.set(f);
			sx.set(s);
			sy.set(t);
			rot.set(turn);
		}
	}

	// the lanes moved to a matrix's (a turn the short way round from where they are)
	public function animateLanes(now:Float, m:Null<Matrix>, curve:Curve) {
		var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0;
		if (m != null) {
			a = m.a;
			b = m.b;
			c = m.c;
			d = m.d;
			e = m.e;
			f = m.f;
		}
		var s = Math.sqrt(a * a + b * b), turn = Math.atan2(b, a), t = s == 0 ? 1.0 : (a * d - b * c) / s;
		rot.sample(now);
		while (turn - rot.value > Math.PI)
			turn -= 2 * Math.PI;
		while (turn - rot.value < -Math.PI)
			turn += 2 * Math.PI;
		tx.animate(now, e, curve);
		ty.animate(now, f, curve);
		sx.animate(now, s, curve);
		sy.animate(now, t, curve);
		rot.animate(now, turn, curve);
	}
}
