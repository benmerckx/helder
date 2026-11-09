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
	// the places of the frames drawn by the program: <Frame story="file#name"
	// canvas:at="x y"/> (a story's: its file from this one's folder, its
	// export's or its own name), <Frame app canvas:at="x y"/> (the app's)
	public final places:Array<Place> = [];

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
				case PElement("Frame", attrs, children, at) if (value(attrs, "story") != null || Lambda.exists(attrs, a -> a.name == "app")):
					places.push({ref: value(attrs, "story") ?? "app", at: point(attrs), start: lead + at - 1, cover: flag(attrs, "cover")});
				case PElement("Frame", attrs, children, at):
					frames.push({
						name: value(attrs, "name") ?? 'Frame ${frames.length + 1}',
						width: Std.int(number(attrs, "width") ?? 390),
						height: Std.int(number(attrs, "height") ?? 844),
						at: point(attrs),
						start: lead + at - 1,
						cover: flag(attrs, "cover"),
						root: {kind: PElement("view", [for (a in attrs) if (shown(a.name)) a].concat(sized(attrs, at)), strip(children), at)},
						base: lead
					});
				case _:
			}
	}

	// (canvas:at's point; null: none)
	static function point(attrs:Array<PAttr>):Null<{x:Float, y:Float}> {
		var xy = (value(attrs, "canvas:at") ?? "").trim().split(" ").map(Std.parseFloat);
		return xy.length == 2 && !Math.isNaN(xy[0]) && !Math.isNaN(xy[1]) ? {x: xy[0], y: xy[1]} : null;
	}

	// (the frame's own attributes, not a view's)
	static function shown(name:String):Bool
		return !name.startsWith("canvas:") && name != "name" && name != "story" && name != "app" && name != "route" && name != "cover";

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

	// (a flag: <Frame cover/>, or cover={true})
	static function flag(attrs:Array<PAttr>, name:String):Bool {
		for (a in attrs)
			if (a.name == name) return value(attrs, name) != "false";
		return false;
	}

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

// (a live frame's place: its reference, story's or "app", where, its element's offset)
typedef Place = {
	ref:String,
	at:Null<{x:Float, y:Float}>,
	start:Int,
	cover:Bool,
}

typedef Frame = {
	name:String,
	width:Int,
	height:Int,
	// where it is on the canvas (canvas:at; null: after the one before)
	at:Null<{x:Float, y:Float}>,
	// its element's offset in the file
	start:Int,
	// the project's cover (Project.cover)
	cover:Bool,
	// what is drawn: a view of its size, its content; the offset of its text in the file
	root:PNode,
	base:Int,
}
