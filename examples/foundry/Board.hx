import Model;
import helder.text.FontEncoder.FontPoint;
import helder.ui.*;
import helder.ui.widgets.Theme;

// The glyph being drawn, at a size to draw it: the guides, its
// neighbours (n either side of a small letter, H of a capital) to judge
// its spacing, a tracing letter behind it, its ink, and its pen lines.
// Draw: a press and drag is a line (Shift: straight), made into knots and
// snapped (Freehand). Adjust: drag a knot or a line, double-click a knot
// for a corner, Delete removes what is selected, the arrows nudge it.
// Erase: what the pointer passes over goes. The spacing handles under the
// baseline move either side. The view stays where it was while the glyph
// is drawn (its ink never jumps), set again when another one is opened.
class Board extends Node {
	final ws:Workshop;
	// font units to the node's pixels: x of the glyph's own space
	var scale = 1.0;
	var ox = 0.0;
	var base = 0.0;
	var viewFor = "";
	var viewWidth = 0.0;

	var stroke:Null<Array<{x:Float, y:Float}>> = null;
	var straight = false;
	var drag:Null<Drag> = null;
	var hoverLine = -1;
	var hoverKnot:Null<{line:Int, knot:Int}> = null;
	var lastPress = 0.0;
	var pointer = {x: 0.0, y: 0.0};

	public function new(ws:Workshop) {
		super("board");
		this.ws = ws;
		focusable = true;
		onPointerDown = down;
		onPointerMove = move;
		onPointerUp = up;
		onLostPointerCapture = _ -> {
			stroke = null;
			drag = null;
		};
		onPointerLeave = _ -> {
			hoverLine = -1;
			hoverKnot = null;
			repaint();
		};
		onKeyDown = key;
	}

	public function repaint()
		if (ui != null) ui.requestFrame();

	override public function hasContent():Bool
		return true;

	// ---- the view

	// where baseline and scale put the guides, for the labels beside them
	public static function vertical(face:Face, height:Float, width:Float):{scale:Float, base:Float} {
		var m = face.metrics, top = Math.max(m.ascender, m.capHeight) + 160, bottom = m.descender - 150;
		var scale = Math.min(height / (top - bottom), width / 1700);
		return {scale: scale, base: (height - (top - bottom) * scale) / 2 + top * scale};
	}

	function frame(w:Float, h:Float) {
		var f = ws.value(), char = ws.current.peek(), v = vertical(f, h, w);
		var rescale = Math.abs(v.scale - scale) > 1e-6;
		scale = v.scale;
		base = v.base;
		if (viewFor != char || Math.abs(w - viewWidth) > 0.5 || rescale) {
			var b = Ink.bounds(f, char);
			var cx = b.x1 <= b.x0 ? 260 : (b.x0 + b.x1) / 2;
			ox = w / 2 - cx * scale;
			viewFor = char;
			viewWidth = w;
		}
	}

	inline function px(x:Float):Float
		return ox + x * scale;

	inline function py(y:Float):Float
		return base - y * scale;

	inline function gx(x:Float):Float
		return (x - ox) / scale;

	inline function gy(y:Float):Float
		return (base - y) / scale;

	// the glyph's advance in its own space: where its spacing starts and ends
	function span(f:Face, char:String):{start:Float, end:Float} {
		var s = Ink.shape(f, char);
		if (s.contours.length == 0) return {start: -f.metrics.spacing, end: 520 + f.metrics.spacing};
		return {start: -s.dx, end: s.advance - s.dx};
	}

	// ---- painting

	override public function paintContent(c:Canvas, x:Float, y:Float, w:Float, h:Float) {
		frame(w, h);
		var f = ws.value(), char = ws.current.peek(), m = f.metrics;
		var fg = Theme.c("fg"), line = Theme.c("line"), edge = Theme.c("edge"), accent = Theme.c("accent");
		var sp = span(f, char);
		// the x-height's band, the guides
		c.rect(x, y + py(m.xHeight), w, (m.xHeight) * scale, 0, alpha(Theme.c("well"), 0.55), 0, 0);
		for (g in [m.descender, m.xHeight, m.capHeight, m.ascender])
			c.rect(x, y + Math.round(py(g)), w, 1, 0, line, 0, 0);
		c.rect(x, y + Math.round(py(0)), w, 1, 0, edge, 0, 0);
		// the neighbours either side
		var ns = Ink.shape(f, Charset.neighbour(char)), ghost = alpha(fg, ws.dark.peek() ? 0.16 : 0.22);
		if (ns.contours.length > 0)
			for (i in 1...3) {
				c.path(path(ns.contours, x + px(sp.start - ns.advance * i), y + base, "left" + i), ghost);
				c.path(path(ns.contours, x + px(sp.end + ns.advance * (i - 1)), y + base, "right" + i), ghost);
			}
		// the tracing letter, where the view put the glyph (still while it is drawn over)
		if (ws.guide.peek()) {
			var cx = gx(w / 2), k = kept.get("tracing");
			var key = '$char ${f.metrics.xHeight} ${f.metrics.capHeight} $cx';
			var t = if (k != null && k.of == key && k.x == x + ox && k.y == y + base && k.scale == scale) k.path else {
				var made = Tracing.path(char, f, cx, scale, x + ox, y + base);
				if (made != null) kept.set("tracing", {of: key, x: x + ox, y: y + base, scale: scale, path: made});
				made;
			}
			if (t != null) c.path(t, alpha(fg, ws.dark.peek() ? 0.07 : 0.05));
		}
		// the spacing: either side, its handles under the descender
		for (side in [sp.start, sp.end]) {
			var sx = x + Math.round(px(side));
			c.rect(sx, y, 1, h, 0, alpha(accent, 0.35), 0, 0);
			var hot = drag != null && drag.kind == (side == sp.start ? "left" : "right");
			c.rect(sx - 5, y + handleY(), 11, 22, 3, hot ? accent : Theme.c("active"), 1, hot ? accent : edge);
		}
		// the ink, or an agent's lines being written out
		var s = Ink.shape(f, char), own = Model.drawn(f, char), g = ws.glyph(char);
		var a = ws.agentStroke.peek();
		if (a != null && a.char == char && Clock.now - a.at < AFTER + duration(g)) {
			writeOut(c, x, y, g, f, s, Clock.now - a.at);
			repaint();
		} else if (s.contours.length > 0) c.path(path(s.contours, x + px(-s.dx), y + base, "ink"), own ? fg : Theme.c("fg2"));
		// erasing: the line under the pointer
		if (ws.tool.peek() == "erase" && hoverLine >= 0 && hoverLine < g.lines.length) {
			var one = Ink.contours([g.lines[hoverLine]], f.pen);
			c.path(Glyphs.path(one, scale, x + ox, y + base), alpha(Theme.c("red"), 0.85));
		}
		// the outline's points (the outline layer), the lines and knots (adjusting), the line being drawn
		if (ws.layer.peek() == "outline") paintOutline(c, x, y, g) else if (ws.tool.peek() == "adjust") paintLines(c, x, y, g, f);
		var st = stroke;
		if (st != null && st.length > 0) {
			var p = new Path();
			var pts = straight ? [st[0], st[st.length - 1]] : st;
			p.moveTo(x + px(pts[0].x), y + py(pts[0].y));
			for (i in 1...pts.length)
				p.lineTo(x + px(pts[i].x), y + py(pts[i].y));
			if (pts.length == 1) p.lineTo(x + px(pts[0].x) + 0.01, y + py(pts[0].y));
			c.path(p, null, {width: f.pen.width * scale, paint: alpha(fg, 0.5), cap: Round, join: Round});
		}
	}

	// ---- an agent's lines written out: along the pen's path, in violet,
	// sparks trailing the pen's tip; the letter then turning to ink

	static inline var AFTER = 0.45;

	function duration(g:Glyph):Float
		return 0.7 + length(g) / 2600;

	static function length(g:Glyph):Float {
		var total = 0.0;
		for (l in g.lines)
			for (p in Ink.centre(l))
				for (i in 1...p.length)
					total += Math.sqrt(Math.pow(p[i].x - p[i - 1].x, 2) + Math.pow(p[i].y - p[i - 1].y, 2));
		return total;
	}

	function writeOut(c:Canvas, x:Float, y:Float, g:Glyph, f:Face, s:Ink.Shape, age:Float) {
		var violet = Theme.c("violet"), fg = Theme.c("fg"), d = duration(g), total = length(g);
		var t = Math.min(1, age / d), eased = t * t * (3 - 2 * t);
		// (where the pen is after so far along its path, in pixels)
		function at(along:Float):Null<{x:Float, y:Float}> {
			var walked = 0.0, last:Null<{x:Float, y:Float}> = null;
			for (l in g.lines)
				for (p in Ink.centre(l)) {
					last = {x: p[p.length - 1].x, y: p[p.length - 1].y};
					for (i in 1...p.length) {
						var step = Math.sqrt(Math.pow(p[i].x - p[i - 1].x, 2) + Math.pow(p[i].y - p[i - 1].y, 2));
						if (walked + step >= along) {
							var k = step == 0 ? 0 : (along - walked) / step;
							return {x: x + px(p[i - 1].x + (p[i].x - p[i - 1].x) * k), y: y + py(p[i - 1].y + (p[i].y - p[i - 1].y) * k)};
						}
						walked += step;
					}
				}
			return last == null ? null : {x: x + px(last.x), y: y + py(last.y)};
		}
		if (t >= 1 || total == 0) {
			var k = Math.min(1, (age - d) / AFTER);
			if (s.contours.length > 0) c.path(path(s.contours, x + px(-s.dx), y + base, "ink"), Color.mix(violet, fg, k * k));
		} else {
			var reveal = eased * total, walked = 0.0;
			for (l in g.lines)
				for (p in Ink.centre(l)) {
					if (walked >= reveal) break;
					var part = new Path();
					part.moveTo(x + px(p[0].x), y + py(p[0].y));
					if (p.length == 1) part.lineTo(x + px(p[0].x) + 0.01, y + py(p[0].y));
					for (i in 1...p.length) {
						var step = Math.sqrt(Math.pow(p[i].x - p[i - 1].x, 2) + Math.pow(p[i].y - p[i - 1].y, 2));
						if (walked + step > reveal) {
							var k = (reveal - walked) / step;
							part.lineTo(x + px(p[i - 1].x + (p[i].x - p[i - 1].x) * k), y + py(p[i - 1].y + (p[i].y - p[i - 1].y) * k));
							walked = reveal;
							break;
						}
						walked += step;
						part.lineTo(x + px(p[i].x), y + py(p[i].y));
					}
					c.path(part, null, {width: f.pen.width * scale, paint: alpha(violet, 0.92), cap: Round, join: Round});
				}
			var tip = at(reveal);
			if (tip != null) c.rect(tip.x - 16, tip.y - 16, 32, 32, 16, alpha(violet, 0.28), 0, 0);
		}
		// sparks: each left where the pen was a moment ago, drifting up and fading
		for (k in 0...16) {
			var born = age - k * 0.05, life = (age - born) / 0.8;
			if (born < 0 || born > d || life > 1) continue;
			var from = at(Math.min(1, born / d) * Math.min(1, born / d) * (3 - 2 * Math.min(1, born / d)) * total);
			if (from == null) continue;
			var seed = Std.int(born * 20) * 7919 + k, rx = rand(seed) - 0.5, ry = rand(seed + 1);
			var size = (1 - life) * (4 + rand(seed + 2) * 6);
			star(c, from.x + rx * 44 * life, from.y - (12 + ry * 30) * life, size, alpha(Color.mix(violet, 0xFFFFFFFF, 0.35), 1 - life));
		}
	}

	// a four-pointed spark
	static function star(c:Canvas, cx:Float, cy:Float, r:Float, color:Color) {
		if (r <= 0.2) return;
		var p = new Path(), i = r * 0.28;
		p.moveTo(cx, cy - r);
		p.quadTo(cx + i * 0.3, cy - i * 0.3, cx + r, cy);
		p.quadTo(cx + i * 0.3, cy + i * 0.3, cx, cy + r);
		p.quadTo(cx - i * 0.3, cy + i * 0.3, cx - r, cy);
		p.quadTo(cx - i * 0.3, cy - i * 0.3, cx, cy - r);
		p.close();
		c.path(p, color);
	}

	static function rand(n:Int):Float {
		var h = n * 0x45d9f3b;
		h = (h ^ (h >>> 16)) * 0x45d9f3b;
		return ((h ^ (h >>> 16)) & 0xFFFFFF) / 0xFFFFFF;
	}

	// the outline: its path, each point on it (a square a corner, a circle
	// smooth), each handle on a line from its point; the selected filled
	function paintOutline(c:Canvas, x:Float, y:Float, g:Glyph) {
		var outline = g.outline;
		if (outline == null) return;
		var accent = Theme.c("accent"), bg = Theme.c("bg"), chosen = ws.points.peek();
		var p = new Path();
		for (pts in outline) {
			var n = pts.length, start = 0;
			while (start < n && pts[start].off == true)
				start++;
			if (start == n) continue;
			p.moveTo(x + px(pts[start].x), y + py(pts[start].y));
			var i = 1;
			while (i <= n) {
				var q = pts[(start + i) % n];
				if (q.off == true) {
					var h2 = pts[(start + i + 1) % n], e = pts[(start + i + 2) % n];
					p.cubicTo(x + px(q.x), y + py(q.y), x + px(h2.x), y + py(h2.y), x + px(e.x), y + py(e.y));
					i += 3;
				} else {
					p.lineTo(x + px(q.x), y + py(q.y));
					i++;
				}
			}
			p.close();
		}
		c.path(p, null, {width: 1.5, paint: accent, cap: Round, join: Round});
		for (ci in 0...outline.length) {
			var pts = outline[ci], n = pts.length;
			for (pi in 0...n) {
				var q = pts[pi];
				if (q.off != true) continue;
				// (a handle's line from the point it belongs to)
				var anchor = pts[(pi - 1 + n) % n].off == true ? pts[(pi + 1) % n] : pts[(pi - 1 + n) % n];
				var l = new Path();
				l.moveTo(x + px(anchor.x), y + py(anchor.y));
				l.lineTo(x + px(q.x), y + py(q.y));
				c.path(l, null, {width: 1, paint: alpha(accent, 0.55)});
			}
			for (pi in 0...n) {
				var q = pts[pi], on = Lambda.exists(chosen, s -> s.c == ci && s.p == pi);
				var qx = x + px(q.x), qy = y + py(q.y);
				if (q.off == true) c.rect(qx - 3.5, qy - 3.5, 7, 7, 3.5, on ? accent : bg, 1.5, accent) else {
					var r = 4.5;
					c.rect(qx - r, qy - r, r * 2, r * 2, q.smooth == true ? r : 1, on ? accent : bg, 1.5, accent);
				}
			}
		}
	}

	function paintLines(c:Canvas, x:Float, y:Float, g:Glyph, f:Face) {
		var accent = Theme.c("accent"), sel = ws.selected.peek();
		for (i in 0...g.lines.length) {
			var chosen = sel != null && sel.line == i;
			for (piece in Ink.centre(g.lines[i])) {
				if (piece.length < 2) continue;
				var p = new Path();
				p.moveTo(x + px(piece[0].x), y + py(piece[0].y));
				for (k in 1...piece.length)
					p.lineTo(x + px(piece[k].x), y + py(piece[k].y));
				c.path(p, null, {width: chosen && sel.knot < 0 ? 2.5 : 1.5, paint: accent, cap: Round, join: Round});
			}
		}
		var bg = Theme.c("bg");
		for (i in 0...g.lines.length) {
			var l = g.lines[i];
			for (k in 0...l.knots.length) {
				var kn = l.knots[k], kx = x + px(kn.x), ky = y + py(kn.y);
				var on = sel != null && sel.line == i && (sel.knot == k || sel.knot < 0);
				var hot = hoverKnot != null && hoverKnot.line == i && hoverKnot.knot == k;
				var r = hot ? 6 : 5;
				c.rect(kx - r, ky - r, r * 2, r * 2, kn.corner == true ? 1.5 : r, on ? accent : bg, 1.5, accent);
			}
		}
	}

	inline function handleY():Float
		return py(ws.value().metrics.descender) + 40;

	// contours in font units as a path in pixels, the font's origin at (ox, base);
	// the same path as the last frame's for the same contours and place (the
	// renderer keeps a path's pixels while it is given the same one)
	function path(contours:Array<Array<FontPoint>>, ox:Float, base:Float, slot:String):Path {
		var k = kept.get(slot);
		if (k != null && k.of == contours && k.x == ox && k.y == base && k.scale == scale) return k.path;
		var p = Glyphs.path(contours, scale, ox, base);
		kept.set(slot, {of: contours, x: ox, y: base, scale: scale, path: p});
		return p;
	}

	final kept = new Map<String, {of:Dynamic, x:Float, y:Float, scale:Float, path:Path}>();

	// ---- input

	function local(e:Event):{x:Float, y:Float}
		return {x: e.x - absX, y: e.y - absY};

	function down(e:Event) {
		focus();
		capture();
		var p = local(e), f = ws.value(), char = ws.current.peek();
		frame(width, height);
		var sp = span(f, char), g = ws.glyph(char);
		for (side in ["left", "right"]) {
			var sx = px(side == "left" ? sp.start : sp.end);
			if (Math.abs(p.x - sx) < 10 && p.y > handleY() - 6 && p.y < handleY() + 28) {
				drag = {kind: side, x: gx(p.x), y: 0, left: g.left ?? 0, right: g.right ?? 0};
				return repaint();
			}
		}
		if (ws.layer.peek() == "outline") return downOutline(e, p, g);
		switch ws.tool.peek() {
			case "draw":
				straight = e.mods & Key.MOD_SHIFT != 0;
				stroke = [{x: gx(p.x), y: gy(p.y)}];
			case "adjust":
				var k = knotAt(p, g);
				if (k != null) {
					var now = haxe.Timer.stamp(), sel = ws.selected.peek();
					if (now - lastPress < 0.35 && sel != null && sel.line == k.line && sel.knot == k.knot) {
						ws.toggleCorner(char, k.line, k.knot);
						lastPress = 0;
						return;
					}
					lastPress = now;
					ws.selected(k);
					drag = {kind: "knot", x: gx(p.x), y: gy(p.y), left: 0, right: 0};
				} else {
					var l = lineAt(p, g, f);
					ws.selected(l < 0 ? null : {line: l, knot: -1});
					if (l >= 0) drag = {kind: "line", x: gx(p.x), y: gy(p.y), left: 0, right: 0};
				}
			case "erase":
				erasing = true;
				erase(p, g, f);
		}
		repaint();
	}

	function move(e:Event) {
		var p = local(e), f = ws.value(), char = ws.current.peek(), g = ws.glyph(char);
		pointer = p;
		var st = stroke, d = drag;
		if (st != null) {
			var q = {x: gx(p.x), y: gy(p.y)}, last = st[st.length - 1];
			if (Math.abs(px(q.x) - px(last.x)) + Math.abs(py(q.y) - py(last.y)) > 1.5) st.push(q);
			straight = e.mods & Key.MOD_SHIFT != 0;
			return repaint();
		}
		if (d != null) {
			var dx = gx(p.x) - d.x, dy = gy(p.y) - d.y, sel = ws.selected.peek();
			switch d.kind {
				case "points" if (dragFrom != null):
					var chosen = ws.points.peek(), sx = dx, sy = dy;
					// (one point on the curve near a guide: on it)
					if (chosen.length == 1) {
						var q = dragFrom[chosen[0].c][chosen[0].p], m = f.metrics;
						if (q.off != true)
							for (guide in [m.descender, 0, m.xHeight, m.capHeight, m.ascender])
								if (Math.abs(py(q.y + dy) - py(guide)) < 6) sy = guide - q.y;
					}
					ws.setOutline(char, OutlineEdit.moved(dragFrom, chosen, Math.round(sx), Math.round(sy)), "drag");
				case "left": ws.setSpacing(char, Math.round(d.left - dx), d.right, "space");
				case "right": ws.setSpacing(char, d.left, Math.round(d.right + dx), "space");
				case "knot" if (sel != null):
					var l = g.lines[sel.line];
					if (l == null) return;
					var k = l.knots[sel.knot];
					var ty = guide(k.y + dy, f);
					ws.moveKnot(char, sel.line, sel.knot, Math.round(k.x + dx), Math.round(ty), "drag");
					d.x += dx;
					d.y += ty - k.y;
				case "line" if (sel != null):
					var l = g.lines[sel.line];
					if (l == null) return;
					ws.setLine(char, sel.line, {knots: [for (k in l.knots) {x: Math.round(k.x + dx), y: Math.round(k.y + dy), corner: k.corner}], closed: l.closed}, "drag");
					d.x += Math.round(dx);
					d.y += Math.round(dy);
				case _:
			}
			return repaint();
		}
		switch ws.tool.peek() {
			case "erase":
				if (erasing) erase(p, g, f);
				var l = lineAt(p, g, f);
				if (l != hoverLine) {
					hoverLine = l;
					repaint();
				}
			case "adjust":
				var k = knotAt(p, g);
				if ((k == null) != (hoverKnot == null) || k != null && hoverKnot != null && (k.line != hoverKnot.line || k.knot != hoverKnot.knot)) {
					hoverKnot = k;
					repaint();
				}
			case _:
		}
	}

	// (the erase tool pressed: erasing what the pointer passes over)
	var erasing = false;

	function up(e:Event) {
		var st = stroke;
		erasing = false;
		if (st != null) {
			stroke = null;
			var char = ws.current.peek(), f = ws.value();
			var l = Freehand.line(st, f, Ink.lines(f, char), straight || e.mods & Key.MOD_SHIFT != 0);
			if (l != null) ws.addLine(char, l);
		}
		drag = null;
		dragFrom = null;
		releaseCapture();
		repaint();
	}

	function erase(p:{x:Float, y:Float}, g:Glyph, f:Face) {
		var l = lineAt(p, g, f);
		if (l < 0) return;
		ws.removeLine(ws.current.peek(), l);
		hoverLine = -1;
	}

	function key(e:Event) {
		if (ws.layer.peek() == "outline") return keyOutline(e);
		var sel = ws.selected.peek(), char = ws.current.peek();
		if (e.key == Key.ESCAPE) {
			ws.selected(null);
			return e.preventDefault();
		}
		if (sel == null) return;
		if (e.key == Key.DELETE || e.key == Key.BACKSPACE) {
			ws.deleteSelected();
			return e.preventDefault();
		}
		var step = e.mods & Key.MOD_SHIFT != 0 ? 25 : 5, dx = 0, dy = 0;
		if (e.key == Key.LEFT) dx = -step else if (e.key == Key.RIGHT) dx = step else if (e.key == Key.UP) dy = step else if (e.key == Key.DOWN) dy = -step else
			return;
		var l = ws.glyph(char).lines[sel.line];
		if (l == null) return;
		ws.setLine(char, sel.line, {
			knots: [for (i in 0...l.knots.length) sel.knot < 0 || sel.knot == i ? {x: l.knots[i].x + dx, y: l.knots[i].y + dy, corner: l.knots[i].corner} : l.knots[i]],
			closed: l.closed
		}, "nudge");
		e.preventDefault();
	}

	// ---- the outline layer: points chosen (Shift adds), dragged, a
	// double-click on a point for smooth or corner, on a curve for a new point

	var dragFrom:Null<Array<Array<OPoint>>> = null;

	function downOutline(e:Event, p:{x:Float, y:Float}, g:Glyph) {
		var outline = g.outline ?? [], char = ws.current.peek(), r = 9 / scale;
		var hit = OutlineEdit.pointAt(outline, gx(p.x), gy(p.y), r), now = haxe.Timer.stamp(), chosen = ws.points.peek();
		var twice = now - lastPress < 0.35;
		lastPress = now;
		if (hit != null) {
			var picked = Lambda.exists(chosen, s -> s.c == hit.c && s.p == hit.p);
			if (twice && picked && chosen.length == 1) {
				ws.setOutline(char, OutlineEdit.toggled(outline, hit.c, hit.p));
				lastPress = 0;
				return;
			}
			if (e.mods & Key.MOD_SHIFT != 0) ws.points(picked ? chosen.filter(s -> !(s.c == hit.c && s.p == hit.p)) : chosen.concat([hit])) else if (!picked)
				ws.points([hit]);
			dragFrom = outline;
			drag = {kind: "points", x: gx(p.x), y: gy(p.y), left: 0, right: 0};
			return repaint();
		}
		var seg = OutlineEdit.segmentAt(outline, gx(p.x), gy(p.y), 7 / scale);
		if (seg != null && twice) {
			ws.setOutline(char, OutlineEdit.inserted(outline, seg.c, seg.at, seg.t));
			ws.points([]);
			lastPress = 0;
			return;
		}
		if (e.mods & Key.MOD_SHIFT == 0) ws.points([]);
		repaint();
	}

	function keyOutline(e:Event) {
		var chosen = ws.points.peek(), char = ws.current.peek(), outline = ws.glyph(char).outline;
		if (e.key == Key.ESCAPE) {
			ws.points([]);
			return e.preventDefault();
		}
		if (chosen.length == 0 || outline == null) return;
		if (e.key == Key.DELETE || e.key == Key.BACKSPACE) {
			ws.setOutline(char, OutlineEdit.removed(outline, chosen));
			ws.points([]);
			return e.preventDefault();
		}
		var step = e.mods & Key.MOD_SHIFT != 0 ? 10 : 1, dx = 0, dy = 0;
		if (e.key == Key.LEFT) dx = -step else if (e.key == Key.RIGHT) dx = step else if (e.key == Key.UP) dy = step else if (e.key == Key.DOWN) dy = -step else
			return;
		ws.setOutline(char, OutlineEdit.moved(outline, chosen, dx, dy), "nudge");
		e.preventDefault();
	}

	// the guide a dragged knot comes to rest on, near one
	function guide(y:Float, f:Face):Float {
		var m = f.metrics, hv = Ink.vertical(f.pen);
		for (t in [hv, m.xHeight - hv, m.capHeight - hv, m.ascender - hv, m.descender + hv])
			if (Math.abs(py(y) - py(t)) < 7) return t;
		return y;
	}

	function knotAt(p:{x:Float, y:Float}, g:Glyph):Null<{line:Int, knot:Int}> {
		var best:Null<{line:Int, knot:Int}> = null, most = 9.0;
		for (i in 0...g.lines.length)
			for (k in 0...g.lines[i].knots.length) {
				var kn = g.lines[i].knots[k], d = Math.sqrt(Math.pow(px(kn.x) - p.x, 2) + Math.pow(py(kn.y) - p.y, 2));
				if (d < most) {
					most = d;
					best = {line: i, knot: k};
				}
			}
		return best;
	}

	function lineAt(p:{x:Float, y:Float}, g:Glyph, f:Face):Int {
		var best = -1, most = f.pen.width / 2 * scale + 5;
		for (i in 0...g.lines.length)
			for (piece in Ink.centre(g.lines[i]))
				for (q in piece) {
					var d = Math.sqrt(Math.pow(px(q.x) - p.x, 2) + Math.pow(py(q.y) - p.y, 2));
					if (d < most) {
						most = d;
						best = i;
					}
				}
		return best;
	}

	static inline function alpha(c:Color, a:Float):Color
		return Color.rgba((c : Int) & 0xFFFFFF, ((c : Int) >>> 24) / 255 * a);
}

private typedef Drag = {kind:String, x:Float, y:Float, left:Float, right:Float};
