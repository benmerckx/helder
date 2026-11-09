package studio;

import helder.syntax.Transaction;
import helder.ui.Node;
import helder.view.graph.Graph.*;
import studio.Project.ScreenInfo;
import studio.Snap;

// A drag on the canvas that edits a design file (helder.build's PLAN step
// 6): a frame moved by its caption, or by itself when it is selected; a
// handle of the selection dragged (resized); the selected nodes placed
// absolutely moved (a node in auto layout is resized only: its place is
// its parent's). Each value is snapped (Snap: to the frame's and the
// siblings' edges and centres, a frame to the other frames'), rounded to a
// point and written as its element's attributes (a frame's canvas:at,
// width and height; a node's width, height, left and top), one
// helder.syntax transaction a move, all of a gesture one entry of the
// history (Docs' group), the frame drawn again from the text at once.
class Drag {
	// (a handle's reach, a snap's: stage points)
	static inline var HANDLE = 6.0;
	static inline var NEAR = 6.0;

	final studio:Studio;
	var on:Null<Gesture> = null;
	// the guides of the snaps now (the world's points)
	public final guides:helder.view.graph.Signal<Array<Guide>> = signal([]);
	public var active(get, never):Bool;

	inline function get_active()
		return on != null;

	public function new(studio)
		this.studio = studio;

	// a press at (px, py) of the stage, dragged: whether it is an edit's (else the canvas pans)
	public function begin(px:Float, py:Float):Bool {
		var p = studio.project;
		if (p == null || studio.mode.peek() == "stories") return false;
		var cam = studio.camera, wx = cam.wx(px), wy = cam.wy(py);
		var f = studio.focused.peek(), info = f == null ? null : p.screen(f);
		var sel = studio.selection.peek();
		if (info != null && info.source.match(Design(_)) && sel != null && sel.screen == f) {
			var r = studio.layout.rect(f);
			var all = [sel].concat(studio.others.peek());
			// (a handle of the selection: resized)
			var h = handleAt(px, py, r.x + sel.x, r.y + sel.y, sel.width, sel.height);
			if (h != null) return start(info, [sel], h);
			for (s in all)
				if (wx >= r.x + s.x && wy >= r.y + s.y && wx < r.x + s.x + s.width && wy < r.y + s.y + s.height) {
					// (the frame itself selected: it moves; else the nodes placed absolutely)
					if (Lambda.exists(all, x -> x.start == info.start)) return frame(info);
					var moved = [for (x in all) if (absolute(info, x.start)) x];
					return moved.length > 0 && start(info, moved, null);
				}
		}
		// (a frame's caption, or the frame itself unless its contents are entered: the frame moved, selected)
		for (r in studio.layout.screens()) {
			var i = p.screen(r.name);
			if (i == null) continue;
			var x0 = cam.sx(r.x), y0 = cam.sy(r.y);
			var caption = px >= x0 && px < x0 + Math.max(60, r.w * cam.k) && py >= y0 - 24 && py < y0 - 2;
			var body = wx >= r.x && wy >= r.y && wx < r.x + r.w && wy < r.y + r.h && !(studio.entered.peek() && f == i.name);
			if (!caption && !body) continue;
			if (f != i.name) studio.focus(i.name, false);
			return frame(i);
		}
		return false;
	}

	// (a frame moved: its box in the world; a design's its own element's
	// canvas:at, a story's or the app's its place's, made when it has none)
	function frame(info:ScreenInfo):Bool {
		var r = studio.layout.rect(info.name);
		if (r == null) return false;
		var file = info.file, start = info.start;
		if (!info.source.match(Design(_))) {
			var place = studio.place(info, r.x, r.y);
			if (place == null) return false;
			file = place.file;
			start = place.start;
		}
		if (start == null) return false;
		var targets = [for (o in studio.layout.screens()) if (o.name != info.name) ({x: o.x, y: o.y, width: o.w, height: o.h} : Box)];
		on = {
			info: info,
			file: file,
			kind: Frame,
			items: [{start: start, box: {x: r.x, y: r.y, width: r.w, height: r.h}, left: 0, top: 0, absolute: false}],
			targets: targets,
			origin: {x: 0, y: 0},
			written: ""
		};
		return true;
	}

	// (nodes moved or one resized: their boxes in the frame)
	function start(info:ScreenInfo, sels:Array<Studio.Selection>, handle:Null<Edges>):Bool {
		var r = studio.layout.rect(info.name);
		var d = studio.designs;
		var items = [], targets:Array<Box> = [];
		for (s in sels) {
			var n = d.nodeAt(info.name, s.start);
			if (n == null) continue;
			var b = d.box(info.name, n), parent = n.parent;
			var pb = parent == null ? null : d.box(info.name, parent);
			items.push({
				start: s.start,
				box: ({x: b.x, y: b.y, width: b.width, height: b.height} : Box),
				left: pb == null ? b.x : b.x - pb.x,
				top: pb == null ? b.y : b.y - pb.y,
				absolute: n.style.position == Absolute
			});
			// (the frame's: the other frames; a node's: its parent's box and its siblings')
			if (s.start == info.start) {
				for (o in studio.layout.screens())
					if (o.name != info.name) targets.push({x: o.x - r.x, y: o.y - r.y, width: o.w, height: o.h});
			} else if (parent != null) {
				targets.push(pb);
				for (c in parent.children)
					if (c != n && !Lambda.exists(sels, x -> d.nodeAt(info.name, x.start) == c)) targets.push(d.box(info.name, c));
			}
		}
		if (items.length == 0) return false;
		on = {
			info: info,
			file: info.file,
			kind: handle == null ? Move : Resize(handle),
			items: items,
			targets: targets,
			origin: {x: r.x, y: r.y},
			written: ""
		};
		return true;
	}

	// the drag at (tx, ty) stage points from its press: the boxes there, snapped, written
	public function move(tx:Float, ty:Float) {
		var g = on;
		if (g == null) return;
		var k = studio.camera.k, dx = tx / k, dy = ty / k;
		var edges:Edges = switch g.kind {
			case Resize(e): e;
			case _: {left: true, right: true, top: true, bottom: true};
		}
		// (the boxes' union moved, or the one box resized, then snapped)
		var u = union([for (i in g.items) i.box]);
		var moved:Box = switch g.kind {
			case Resize(e): {
				x: u.x + (e.left ? dx : 0),
				y: u.y + (e.top ? dy : 0),
				width: Math.max(1, u.width + (e.left ? -dx : e.right ? dx : 0)),
				height: Math.max(1, u.height + (e.top ? -dy : e.bottom ? dy : 0))
			};
			case _: {x: u.x + dx, y: u.y + dy, width: u.width, height: u.height};
		}
		var s = Snap.box(moved, edges, g.targets, NEAR / k);
		var b = s.box;
		// (a node's guides from its frame's points to the world's; a frame's are)
		var gx = g.kind == Frame ? 0 : g.origin.x, gy = g.kind == Frame ? 0 : g.origin.y;
		guides([for (x in s.guides) {vertical: x.vertical, at: x.at + (x.vertical ? gx : gy), from: x.from + (x.vertical ? gy : gx), to: x.to + (x.vertical ? gy : gx)}]);
		var ox = Math.round(b.x - u.x), oy = Math.round(b.y - u.y);
		var w = Math.round(b.width), h = Math.round(b.height);
		write(g, switch g.kind {
			case Frame: [[{name: "canvas:at", value: '${Math.round(b.x - g.origin.x)} ${Math.round(b.y - g.origin.y)}'}]];
			case Move: [for (i in g.items) if (i.absolute) [{name: "left", value: Std.string(Math.round(i.left) + ox)}, {name: "top", value: Std.string(Math.round(i.top) + oy)}]];
			case Resize(e):
				var i = g.items[0];
				var frame = i.start == g.info.start;
				var out = [];
				if (e.left || e.right) out.push({name: "width", value: Std.string(w)});
				if (e.top || e.bottom) out.push({name: "height", value: Std.string(h)});
				if (frame && (e.left || e.top)) {
					var at = g.info.at ?? {x: g.origin.x, y: g.origin.y};
					out.push({name: "canvas:at", value: '${Math.round(at.x) + ox} ${Math.round(at.y) + oy}'});
				} else if (i.absolute) {
					if (e.left) out.push({name: "left", value: Std.string(Math.round(i.left) + ox)});
					if (e.top) out.push({name: "top", value: Std.string(Math.round(i.top) + oy)});
				}
				[out];
		});
	}

	// each item's attributes set, one transaction (nothing when they are as last written)
	function write(g:Gesture, sets:Array<Array<{name:String, value:String}>>) {
		var key = haxe.Json.stringify(sets);
		if (key == g.written) return;
		g.written = key;
		var file = g.file, doc = studio.docs.get(file).doc;
		var changes = [];
		var targets = g.kind == Move ? [for (i in g.items) if (i.absolute) i] : g.items;
		for (k in 0...targets.length) {
			var el = doc.elementAt(targets[k].start);
			if (el == null) continue;
			for (a in sets[k])
				for (c in Studio.attribute(doc, el, a.name, a.value).changes)
					changes.push(c);
		}
		var tx = try new Transaction(changes, null, doc.text) catch (_:Dynamic) return;
		if (tx.changes.length == 0) return;
		for (i in g.items)
			i.start = tx.map(i.start, 1);
		studio.edit(file, tx, label(g), "canvas", 'drag:${studio.gesture}');
	}

	static function label(g:Gesture):String
		return switch g.kind {
			case Frame: "frame moved";
			case Move: "moved";
			case Resize(_): "resized";
		};

	// the drag let go: its edits one entry, the guides gone
	public function end() {
		var g = on;
		if (g == null) return;
		on = null;
		var snapped = guides.peek().length;
		guides([]);
		studio.endGesture();
		var doc = studio.docs.get(g.file).doc;
		studio.log("dragged", {
			screen: g.info.name,
			kind: label(g),
			snapped: snapped,
			elements: [for (i in g.items) {var el = doc.elementAt(i.start); el == null ? null : el.open.text(doc.text);}]
		});
	}

	// (a node of a design screen placed absolutely)
	function absolute(info:ScreenInfo, start:Int):Bool {
		var n = studio.designs.nodeAt(info.name, start);
		return n != null && n.style.position == Absolute;
	}

	// (the handle of a box (world) at the stage's (px, py): the edges it drags; null: none)
	function handleAt(px:Float, py:Float, x:Float, y:Float, w:Float, h:Float):Null<Edges> {
		var cam = studio.camera;
		var x0 = cam.sx(x), y0 = cam.sy(y), x1 = cam.sx(x + w), y1 = cam.sy(y + h);
		var xm = (x0 + x1) / 2, ym = (y0 + y1) / 2;
		for (hx in [x0, xm, x1])
			for (hy in [y0, ym, y1]) {
				if (hx == xm && hy == ym) continue;
				if (Math.abs(px - hx) <= HANDLE && Math.abs(py - hy) <= HANDLE)
					return {left: hx == x0, right: hx == x1, top: hy == y0, bottom: hy == y1};
			}
		return null;
	}

	// the handles of a box (world): their centres in the stage
	public static function handles(cam:Camera, x:Float, y:Float, w:Float, h:Float):Array<{x:Float, y:Float}> {
		var x0 = cam.sx(x), y0 = cam.sy(y), x1 = cam.sx(x + w), y1 = cam.sy(y + h);
		var xm = (x0 + x1) / 2, ym = (y0 + y1) / 2;
		return [for (hx in [x0, xm, x1]) for (hy in [y0, ym, y1]) if (hx != xm || hy != ym) {x: hx, y: hy}];
	}

	static function union(boxes:Array<Box>):Box {
		var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
		for (b in boxes) {
			x0 = Math.min(x0, b.x);
			y0 = Math.min(y0, b.y);
			x1 = Math.max(x1, b.x + b.width);
			y1 = Math.max(y1, b.y + b.height);
		}
		return {x: x0, y: y0, width: x1 - x0, height: y1 - y0};
	}
}

private enum Kind {
	Frame;
	Move;
	Resize(edges:Edges);
}

// (a drag under way: the frame's screen, what it moves (each element's
// offset now, its box when pressed: the frame's in the world, a node's in
// its frame; a node's left and top in its parent), what it snaps to, the
// origin of a node's points in the world (a frame's: the world's),
// what it last wrote)
private typedef Gesture = {
	info:ScreenInfo,
	// (the file it writes: the frame's, or its place's)
	file:String,
	kind:Kind,
	items:Array<{start:Int, box:Box, left:Float, top:Float, absolute:Bool}>,
	targets:Array<Box>,
	origin:{x:Float, y:Float},
	written:String
}
