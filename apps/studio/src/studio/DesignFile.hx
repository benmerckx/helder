package studio;

import helder.markup.Syntax;

using StringTools;

// A design file (*.helder, DESIGN.md): markup alone, a root (<Design>, a
// fragment) of frames, <Frame name="Home" width={390} height={844}
// canvas:at="0 0">...</Frame>, each a place on the canvas with a size (a
// phone's, 390 by 844, without), its content markup the studio interprets
// (helder.ui.view.Interpreter). What only the editor needs is dropped
// before it is drawn: canvas:* attributes, <note> elements. A frame is drawn
// as a view of its size, its own attributes but its name and the editor's
// its style, so that the frame itself is selected and edited as any node.
class DesignFile {
	// the file's text read; a thrown message: not one root of markup
	public final frames:Array<Frame> = [];

	public function new(text:String) {
		// (the root at the first "<": the offsets the parser gives are of its text from there)
		var lead = text.length - text.ltrim().length;
		var root = new Parser(text.substr(lead), (m, at, _) -> throw '$m (at ${lead + at})').document();
		var kids = switch root.kind {
			case PElement("Frame", _, _, _): [root];
			case PElement(_, _, children, _) | PFragment(children): children;
			case _: [];
		}
		for (k in kids)
			switch k.kind {
				case PElement("Frame", attrs, children, at):
					var xy = (value(attrs, "canvas:at") ?? "").trim().split(" ").map(Std.parseFloat);
					frames.push({
						name: value(attrs, "name") ?? 'Frame ${frames.length + 1}',
						width: Std.int(number(attrs, "width") ?? 390),
						height: Std.int(number(attrs, "height") ?? 844),
						at: xy.length == 2 && !Math.isNaN(xy[0]) && !Math.isNaN(xy[1]) ? {x: xy[0], y: xy[1]} : null,
						root: {kind: PElement("view", [for (a in attrs) if (shown(a.name)) a].concat(sized(attrs, at)), strip(children), at)},
						base: lead
					});
				case _:
			}
	}

	// (the frame's own attributes, not a view's)
	static function shown(name:String):Bool
		return !name.startsWith("canvas:") && name != "name" && name != "story" && name != "app" && name != "route";

	// (a size not written: a phone's)
	static function sized(attrs:Array<PAttr>, at:Int):Array<PAttr>
		return [
			for (d in [{name: "width", v: "390"}, {name: "height", v: "844"}])
				if (!Lambda.exists(attrs, a -> a.name == d.name)) {name: d.name, value: AExpr(d.v, at), at: at}
		];

	// (the editor's own: dropped, as a build drops stories)
	static function strip(nodes:Array<PNode>):Array<PNode>
		return [
			for (n in nodes)
				switch n.kind {
					case PElement("note", _, _, _): continue;
					case PElement(name, attrs, children, at): {kind: PElement(name, [for (a in attrs) if (!a.name.startsWith("canvas:")) a], strip(children), at), at: n.at, end: n.end};
					case PFragment(children): {kind: PFragment(strip(children)), at: n.at, end: n.end};
					case _: n;
				}
		];

	static function value(attrs:Array<PAttr>, name:String):Null<String> {
		for (a in attrs)
			if (a.name == name) return switch a.value {
				case AStatic(s): s;
				case AExpr(code, _): code.trim();
				case _: null;
			}
		return null;
	}

	static function number(attrs:Array<PAttr>, name:String):Null<Float> {
		var t = value(attrs, name);
		var f = t == null ? Math.NaN : Std.parseFloat(t);
		return Math.isNaN(f) ? null : f;
	}
}

typedef Frame = {
	name:String,
	width:Int,
	height:Int,
	// where it is on the canvas (canvas:at; null: after the one before)
	at:Null<{x:Float, y:Float}>,
	// what is drawn: a view of its size, its content; the offset of its text in the file
	root:PNode,
	base:Int,
}
