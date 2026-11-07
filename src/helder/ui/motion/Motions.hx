package helder.ui.motion;

import helder.canvas.Matrix;
import helder.ui.Color;

// Motion as property tracks: what moves a node's presented state (its
// Present's tracks) when its layout, its style or its place in the tree
// changes, and steps them on the Clock (one step for every track that
// moves; a frame asked of each window drawing them). Nothing of it runs
// until a node declares motion (Node.motion, matched, ride; a transition's
// presence): `on`.
//
// - Layout (relaid, from Node.setLayout): under a declared motion, a node
//   laid out somewhere else after it has been drawn moves there edge by
//   edge in its parent's space, from where its edges are drawn: an edge
//   that stays put never moves, a child whose place in its parent stays put
//   rides its parent. lead and trail: the edge in the direction of travel on
//   lead, the other on trail.
// - Properties (from Style's setters): opacity, radius, background, border
//   and text colours (premultiplied OKLab; a text colour in half the time
//   when the spec's textLeads), transform (its translation, scale and
//   rotation as lanes): the property reads where it is, Style.target where
//   it goes; a text colour and a transform are drawn from their tracks.
// - Presence (from Node.insert and Node.remove): a node with a transition's
//   presence (transition="fade scale") inserted into a drawn parent enters;
//   removed, it is kept drawn where it was, out of the tree and its layout,
//   until its exit settles (its parent's exits), and revived from there if
//   it is inserted into that parent again. Nothing enters on the first frame.
// - Matched elements (Node.matched): one removed and another with its id
//   laid out within an update of it: the new one flies from where the old
//   one was seen (its rect and radius, its velocity), drawn over everything,
//   its content scaled to cover the frame as it goes.
// - Reduced motion (Clock.reducedMotion): travel, size, transforms and
//   radii jump; opacity, presence and colours fade over REDUCED_FADE;
//   matched elements cross-fade in place.
// - instant: an instant node's subtree (Node.instant), or what changes
//   inside instant(f), applies without motion (an instant node's own
//   entrance and exit still play).
class Motions {
	// (a node declared motion: the hooks run)
	public static var on(default, null) = false;
	// (the engine writing a style property: its setter takes it as it is)
	public static var writing = false;
	// (inside instant(f))
	static var instantDepth = 0;
	// (ghosts drawn: nodes leaving)
	public static var ghosts(default, null) = 0;
	// settled within this of an edge (pixels)
	public static inline var EDGE_EPS = 0.01;

	// what moves (each Present once)
	static final active:Array<Present> = [];
	static var ticking = false;
	// (the Ui updates so far: a matched source kept for the next one)
	static var updates = 0;
	static final sources:Array<Source> = [];
	static final scratch = new Bounds();

	public static function enable()
		on = true;

	// changes made in f apply without motion (a drag's moves, a settle)
	public static function instant(f:Void->Void) {
		instantDepth++;
		try f() catch (e:Dynamic) {
			instantDepth--;
			throw e;
		}
		instantDepth--;
	}

	// the motion over n: the nearest declared (null: none, or an instant node between)
	public static function specOf(n:Node):Null<MotionSpec> {
		if (instantDepth > 0) return null;
		var a = n;
		while (a != null) {
			if (a.instant) return null;
			if (a.motion != null) return a.motion;
			a = a.parent ?? a.leftFrom;
		}
		return null;
	}

	// (whether an ancestor of n, not n, is instant)
	static function underInstant(n:Node):Bool {
		if (instantDepth > 0) return true;
		var a = n.parent;
		while (a != null) {
			if (a.instant) return true;
			a = a.parent;
		}
		return false;
	}

	// (the curve for a property's change under spec, null: none; a token resolved for n)
	static inline function curveOf(c:Curve, n:Node):Curve
		return c.resolve(n);

	// (a change's start: in a frame's update the Clock's time, else (an event between frames) the next tick's)
	public static inline function now():Float
		return updating ? Clock.now : -1;

	// (inside Ui.update: the frame's time is the Clock's)
	public static var updating = false;

	static function present(n:Node):Present {
		if (n.present == null) @:privateAccess n.present = new Present(n);
		return n.present;
	}

	// (moving: stepped on the Clock)
	static function activate(p:Present) {
		if (!p.active) {
			p.active = true;
			active.push(p);
		}
		if (!ticking) {
			ticking = true;
			Clock.add(step);
		}
		var u = uiOf(p.node);
		if (u != null) u.requestFrame();
	}

	// the Ui a node is drawn in (a ghost's: its old parent's)
	public static function uiOf(n:Node):Null<Ui> {
		var a = n;
		while (a != null) {
			if (a.ui != null) return a.ui;
			a = a.parent ?? a.leftFrom;
		}
		return null;
	}

	// --- layout ---

	// (Node.setLayout: n laid out at x, y, w, h in its parent, before they are stored)
	public static function relaid(n:Node, x:Float, y:Float, w:Float, h:Float) {
		var p = n.present, par = n.parent;
		var parW = par == null ? 0.0 : par.width, parH = par == null ? 0.0 : par.height;
		// (not drawn yet: where it is laid out is where it is first seen; a matched one may fly there)
		if (@:privateAccess n.drawnAt < 0 || (p != null && p.exiting)) {
			if (n.matched != null && !Clock.reducedMotion && fly(n, x, y, w, h)) return;
			if (p != null && p.edges()) p.setEdges(x, y, w, h, parW, parH) else if (n.ride != 0 || n.matched != null) {
				p = present(n);
				p.rideX = n.ride & 1 != 0;
				p.rideY = n.ride & 2 != 0;
				p.setEdges(x, y, w, h, parW, parH);
			}
			return;
		}
		var spec = specOf(n);
		if (spec == null || Clock.reducedMotion) {
			if (p != null && p.edges()) {
				p.setEdges(x, y, w, h, parW, parH);
				p.flying = false;
			}
			return;
		}
		if (p == null) p = present(n);
		if (!p.edges()) {
			// (its edges from where it was laid out: what was drawn)
			p.rideX = n.ride & 1 != 0;
			p.rideY = n.ride & 2 != 0;
			var oldW = par == null ? 0.0 : par.present != null && par.present.edges() ? par.present.r.target - par.present.l.target : parW;
			var oldH = par == null ? 0.0 : par.present != null && par.present.edges() ? par.present.b.target - par.present.t.target : parH;
			p.setEdges(n.x, n.y, n.width, n.height, oldW, oldH);
		}
		var t = Clock.now;
		var x0 = p.rideX ? x - parW : x, y0 = p.rideY ? y - parH : y;
		var c = curveOf(spec.layoutCurve(), n);
		var lead = spec.lead == null ? null : curveOf(spec.lead, n), trail = spec.trail == null ? null : curveOf(spec.trail, n);
		moveAxis(p.l, p.r, x0, x0 + w, c, lead, trail, t);
		moveAxis(p.t, p.b, y0, y0 + h, c, lead, trail, t);
		if (p.l.moving() || p.t.moving() || p.r.moving() || p.b.moving()) activate(p);
	}

	// (an axis' edges to a and b: those that move, the one in the direction of travel on lead, the other on trail)
	static function moveAxis(e0:Track, e1:Track, a:Float, b:Float, c:Curve, lead:Null<Curve>, trail:Null<Curve>, t:Float) {
		var c0 = c, c1 = c;
		if (lead != null || trail != null) {
			var forward = a + b > e0.target + e1.target;
			// (travelling forward: its far edge leads)
			c0 = (forward ? trail : lead) ?? c;
			c1 = (forward ? lead : trail) ?? c;
		}
		if (a != e0.target) e0.animate(t, a, c0);
		if (b != e1.target) e1.animate(t, b, c1);
	}

	// (a matched n, new, laid out at x, y, w, h: from where its counterpart was seen, if one left; whether it flies)
	static function fly(n:Node, x:Float, y:Float, w:Float, h:Float):Bool {
		var src:Null<Source> = null;
		for (s in sources)
			if (!s.consumed && s.id == n.matched && s.node != n) src = s;
		if (src == null) return false;
		var par = n.parent;
		src.consumed = true;
		var p = present(n);
		p.rideX = p.rideY = false;
		// (its start in its parent's space: where the source was seen, less where the parent is drawn)
		var ox = 0.0, oy = 0.0;
		if (par != null) {
			par.windowBoundsInto(scratch);
			ox = scratch.x - (par.style.overflow == Scroll ? par.scrollX : 0);
			oy = scratch.y - (par.style.overflow == Scroll ? par.scrollY : 0);
		}
		p.setEdges(src.x0 - ox, src.y0 - oy, src.x1 - src.x0, src.y1 - src.y0, 0, 0);
		var spec = specOf(n) ?? MotionSpec.DEFAULT, c = curveOf(spec.layoutCurve(), n), t = Clock.now;
		p.l.animate(t, x, c, src.v0);
		p.t.animate(t, y, c, src.v1);
		p.r.animate(t, x + w, c, src.v2);
		p.b.animate(t, y + h, c, src.v3);
		p.flying = true;
		// (the one surface from now on: fully present)
		if (p.presence != null) p.presence.set(1);
		// (its radius and fill from the source's)
		var s = n.style;
		if (src.radius != s.radius) {
			var to = s.radius;
			if (p.radius == null) p.radius = new Track(src.radius, 1e-3) else p.radius.set(src.radius);
			p.radius.animate(t, to, curveOf(spec.radiusCurve(), n));
			write(() -> s.radius = src.radius);
		}
		if (src.background != s.background && !src.background.isToken && !s.background.isToken) {
			var to = s.background;
			if (p.background == null) p.background = new ColorTrack(src.background) else p.background.set(src.background);
			p.background.animate(t, to, curveOf(spec.colorCurve(), n));
			write(() -> s.background = src.background);
		}
		activate(p);
		return true;
	}

	static inline function write(f:Void->Void) {
		writing = true;
		f();
		writing = false;
	}

	// (Ui.update's end: a matched source left over one update forgotten, a consumed one's ghost gone)
	public static function updated() {
		updates++;
		if (sources.length == 0) return;
		var i = 0;
		while (i < sources.length) {
			var s = sources[i];
			if (s.consumed) {
				var p = s.node.present;
				if (p != null && p.exiting) finishExit(p);
				sources.splice(i, 1);
			} else if (s.update < updates - 1) sources.splice(i, 1) else i++;
		}
	}

	// --- presence ---

	// (Node.insert: child put into parent)
	public static function inserted(parent:Node, child:Node) {
		var p = child.present;
		// (revived: back from where it is, its exit undone)
		if (p != null && p.exiting) {
			endGhost(p);
			if (p.presence != null) {
				var spec = specOf(child) ?? MotionSpec.DEFAULT;
				p.presence.animate(now(), 1, Clock.reducedMotion ? Curve.REDUCED_FADE : curveOf(spec.presenceCurve(), child));
				activate(p);
			}
			return;
		}
		var tr = child.style.transition;
		if (tr == null || tr.presence == null || parent.ui == null || !@:privateAccess parent.style.drawn || underInstant(child)) return;
		p = present(child);
		p.effect = tr.presence;
		if (p.presence == null) p.presence = new Track(0, 1e-4) else p.presence.set(0);
		var spec = specOf(child) ?? MotionSpec.DEFAULT;
		p.presence.animate(now(), 1, Clock.reducedMotion ? Curve.REDUCED_FADE : curveOf(spec.presenceCurve(), child));
		activate(p);
	}

	// (Node.remove: child about to be taken out of parent; whether it is kept drawn, a ghost, until its exit settles)
	public static function removing(parent:Node, child:Node):Bool {
		if (parent.ui == null || @:privateAccess child.drawnAt < 0 || child.style.display == None) return false;
		if (matchedCount > 0 && !Clock.reducedMotion) sourcesIn(child);
		var tr = child.style.transition;
		if (tr == null || tr.presence == null || underInstant(child)) return false;
		var p = present(child);
		p.effect = tr.presence;
		p.gx = child.x + p.dx();
		p.gy = child.y + p.dy();
		p.exiting = true;
		if (p.presence == null) p.presence = new Track(1, 1e-4);
		var spec = specOf(child) ?? MotionSpec.DEFAULT;
		p.presence.animate(now(), 0, Clock.reducedMotion ? Curve.REDUCED_FADE : curveOf(spec.presenceCurve(), child).exit());
		if (parent.exits == null) @:privateAccess parent.exits = [];
		parent.exits.push(child);
		@:privateAccess child.leftFrom = parent;
		ghosts++;
		activate(p);
		return true;
	}

	// (the matched nodes declared)
	public static var matchedCount = 0;

	// (n's matched nodes and its subtree's, drawn, kept as sources: where each was seen)
	static function sourcesIn(n:Node) {
		if (n.style.display == None) return;
		if (n.matched != null && @:privateAccess n.drawnAt >= 0) {
			var child = n;
			child.windowBoundsInto(scratch);
			var p = child.present, e = p != null && p.edges();
			sources.push({
				id: child.matched,
				node: child,
				x0: scratch.x,
				y0: scratch.y,
				x1: scratch.x + scratch.width,
				y1: scratch.y + scratch.height,
				v0: e ? p.l.velocity : 0,
				v1: e ? p.t.velocity : 0,
				v2: e ? p.r.velocity : 0,
				v3: e ? p.b.velocity : 0,
				radius: child.style.radius,
				background: child.style.background,
				update: updates,
				consumed: false
			});
		}
		for (c in n.children)
			sourcesIn(c);
	}

	// (out of its old parent's exits)
	static function endGhost(p:Present) {
		var n = p.node, from = n.leftFrom;
		if (from != null && from.exits != null) from.exits.remove(n);
		@:privateAccess n.leftFrom = null;
		p.exiting = false;
		ghosts--;
		var u = from == null ? null : uiOf(from);
		if (u != null) u.requestFrame();
	}

	// (its exit settled, or its counterpart flew: no longer drawn)
	static function finishExit(p:Present) {
		endGhost(p);
		var told = p.onExited;
		p.onExited = null;
		if (told != null)
			for (f in told)
				f();
	}

	// whether n is inside a ghost (a node leaving: its subtree kept as it was drawn)
	public static function inGhost(n:Node):Bool {
		if (ghosts == 0) return false;
		var a = n;
		while (a.parent != null)
			a = a.parent;
		return a.leftFrom != null;
	}

	// whether n is leaving (drawn until its exit settles); done is told when it has left (helder.view's For)
	public static function leaving(n:Node, ?done:Void->Void):Bool {
		var p = n.present;
		if (p == null || !p.exiting) return false;
		if (done != null) {
			if (p.onExited == null) p.onExited = [];
			p.onExited.push(done);
		}
		return true;
	}

	// --- properties ---

	// (a property's change, under motion: moving, whether the setter leaves it where it is)
	static function gate(n:Node):Null<MotionSpec>
		return writing || n.ui == null || !@:privateAccess n.style.drawn ? null : specOf(n);

	public static inline var OPACITY = 0;
	public static inline var RADIUS = 1;

	// (Style's setters of opacity and radius)
	public static function moveFloat(n:Node, prop:Int, from:Float, to:Float):Bool {
		if (writing) return false;
		var p = n.present, tr = p == null ? null : prop == OPACITY ? p.opacity : p.radius;
		var spec = gate(n);
		var fades = prop == OPACITY;
		if (spec == null || (Clock.reducedMotion && !fades)) {
			if (tr != null && tr.moving()) tr.set(to);
			return false;
		}
		if (from == to && (tr == null || !tr.moving())) return false;
		if (p == null) p = present(n);
		if (tr == null) {
			tr = new Track(from, prop == OPACITY ? 1e-4 : 1e-3);
			if (prop == OPACITY) p.opacity = tr else p.radius = tr;
		}
		var c = Clock.reducedMotion ? Curve.REDUCED_FADE : curveOf(prop == OPACITY ? spec.opacityCurve() : spec.radiusCurve(), n);
		tr.animate(now(), to, c);
		activate(p);
		return true;
	}

	public static inline var BACKGROUND = 0;
	public static inline var BORDER = 1;

	// (Style's setters of background and borderColor)
	public static function moveColor(n:Node, prop:Int, from:Color, to:Color):Bool {
		if (writing) return false;
		var p = n.present, tr = p == null ? null : prop == BACKGROUND ? p.background : p.border;
		var spec = gate(n);
		if (spec == null || from.isToken || to.isToken) {
			if (tr != null && tr.moving()) tr.set(to);
			return false;
		}
		if (from == to && (tr == null || !tr.moving())) return false;
		if (p == null) p = present(n);
		if (tr == null) {
			tr = new ColorTrack(from);
			if (prop == BACKGROUND) p.background = tr else p.border = tr;
		}
		tr.animate(now(), to, Clock.reducedMotion ? Curve.REDUCED_FADE : curveOf(spec.colorCurve(), n));
		activate(p);
		return true;
	}

	// (Style's setter of color: the text colour drawn from its track, Node.textColor, the style set when it settles)
	public static function moveTextColor(n:Node, from:Null<Color>, to:Null<Color>):Bool {
		if (writing) return false;
		var p = n.present, tr = p == null ? null : p.color;
		var spec = gate(n);
		if (spec == null) {
			if (tr != null && tr.moving()) tr.set(0);
			return false;
		}
		var a = from ?? n.textColor(), b = to ?? (n.parent == null ? Style.DEFAULT_COLOR : n.parent.textColor());
		if (tr != null && tr.moving()) a = tr.value();
		if (a.isToken || b.isToken || a == b && (tr == null || !tr.moving())) return false;
		if (p == null) p = present(n);
		if (tr == null) p.color = tr = new ColorTrack(a) else if (!tr.moving()) tr.set(a);
		p.colorTo = to;
		var c = curveOf(spec.colorCurve(), n);
		tr.animate(now(), b, Clock.reducedMotion ? Curve.REDUCED_FADE : spec.textLeads ? c.scaled(0.5) : c);
		activate(p);
		return true;
	}

	// (Style's setter of transform: its lanes from the transform drawn now to the new one's, the style set at once)
	public static function moveTransform(n:Node, from:Null<Transform>, to:Null<Transform>) {
		if (writing) return;
		var p = n.present;
		var spec = gate(n);
		if (spec == null || Clock.reducedMotion) {
			if (p != null) p.tx = p.ty = p.sx = p.sy = p.rot = null;
			return;
		}
		if (p == null) p = present(n);
		if (p.tx == null) p.setLanes(from == null || from.isIdentity() ? null : from.toMatrix(n.width, n.height));
		p.animateLanes(now(), to == null || to.isIdentity() ? null : to.toMatrix(n.width, n.height), curveOf(spec.transformCurve(), n));
		activate(p);
	}

	// --- the clock ---

	// (each moving track sampled at now; their values written, frames asked; the settled let go)
	static function step(now:Float):Bool {
		var i = 0;
		while (i < active.length) {
			var p = active[i];
			sampleAll(p, now);
			var u = uiOf(p.node);
			if (u != null) u.requestFrame();
			if (!p.moving()) {
				p.active = false;
				active[i] = active[active.length - 1];
				active.pop();
				continue;
			}
			i++;
		}
		if (active.length == 0) {
			ticking = false;
			return false;
		}
		return true;
	}

	static function sampleAll(p:Present, now:Float) {
		var n = p.node, s = n.style;
		if (p.l != null) {
			p.l.sample(now);
			p.t.sample(now);
			p.r.sample(now);
			p.b.sample(now);
			if (p.flying && !p.l.moving() && !p.t.moving() && !p.r.moving() && !p.b.moving()) p.flying = false;
		}
		writing = true;
		if (p.opacity != null && p.opacity.moving()) {
			p.opacity.sample(now);
			s.opacity = p.opacity.value;
		}
		if (p.radius != null && p.radius.moving()) {
			p.radius.sample(now);
			s.radius = p.radius.value;
		}
		if (p.background != null && p.background.moving()) {
			p.background.sample(now);
			s.background = p.background.value();
		}
		if (p.border != null && p.border.moving()) {
			p.border.sample(now);
			s.borderColor = p.border.value();
		}
		if (p.color != null && p.color.moving()) {
			p.color.sample(now);
			// (settled: the style's own)
			if (!p.color.moving()) s.color = p.colorTo;
			@:privateAccess n.paintChanged();
		}
		writing = false;
		if (p.tx != null) {
			p.tx.sample(now);
			p.ty.sample(now);
			p.sx.sample(now);
			p.sy.sample(now);
			p.rot.sample(now);
			if (!p.tx.moving() && !p.ty.moving() && !p.sx.moving() && !p.sy.moving() && !p.rot.moving()) p.tx = p.ty = p.sx = p.sy = p.rot = null;
			@:privateAccess n.inkChanged();
		}
		if (p.presence != null && p.presence.moving()) {
			p.presence.sample(now);
			if (!p.presence.moving() && p.exiting && p.presence.target <= 0) finishExit(p);
		}
	}

	// the tracks of n settled at once (a test, a screenshot: Clock.finish ends them too)
	public static function settle(n:Node) {
		var p = n.present;
		if (p == null) return;
		sampleAll(p, 1e300);
	}

	// how many nodes move now
	public static function moving():Int
		return active.length;
}

// (a matched element that left: where it was seen, its edges' velocities, its radius and fill)
private typedef Source = {
	id:String,
	node:Node,
	x0:Float,
	y0:Float,
	x1:Float,
	y1:Float,
	v0:Float,
	v1:Float,
	v2:Float,
	v3:Float,
	radius:Float,
	background:Color,
	update:Int,
	consumed:Bool
}
