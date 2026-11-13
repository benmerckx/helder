package helder.story;

import helder.definition.Kernel;

// story({name, render, seed, width, height, store, caption, background, color, feature})'s handler
// (src/helder/compiler/DESIGN.md 4), the same for both languages (Haxe's
// helder.story.Story.story, TypeScript's helder/story): the fields checked
// at their positions, each a literal but render, a function of the story's
// controls making its view; width and height its size in points (the
// studio's screen, helder.story.Screens; a phone's, 390x844, without). A story with store: true is a store
// screenshot (helder publish --screenshots), its caption over it and the
// caption band's colours; seed is Controls.random's (1). What each adapter
// makes of it is the Story; in a release build (-D helder.release) nothing:
// a story, and what only it uses, is not in an app's release.
class StoryDefinition implements Definition<Adapter, StoryFields> {
	public final name = "story";

	static final FIELDS = ["name", "render", "seed", "width", "height", "store", "caption", "background", "color", "feature"];

	public function new() {}

	public function generate(arg:KNode, a:Adapter):StoryFields {
		var r = new KObjectReader(arg, a, "the argument", FIELDS);
		var n = r.require("name");
		var name = switch n.value {
			case KString(s) if (s != ""): s;
			case KString(_): a.error("the name is empty", n.pos);
			case _: a.error('the name is a string literal, not ${n.describe()}', n.pos);
		}
		var rn = r.require("render");
		var render = switch rn.value {
			case KFunction(f) if (f.params.length <= 1): f;
			case KFunction(f): a.error('render is a function of the story\'s controls ((c) => view), not of ${f.params.length} arguments', rn.pos);
			case _: a.error('render is a function of the story\'s controls ((c) => view), not ${rn.describe()}', rn.pos);
		}
		var store = switch r.get("store") {
			case null: false;
			case {value: KBool(b)}: b;
			case x: a.error('store is true or false, not ${x.describe()}', x.pos);
		}
		var caption = switch r.get("caption") {
			case null: null;
			case {value: KString(s)}: s;
			case x: a.error('caption is a string literal, not ${x.describe()}', x.pos);
		}
		for (f in ["width", "height"]) {
			var x = r.get(f);
			if (x != null) switch x.value {
				case KInt(i) if (i > 0): {}
				case KFloat(v) if (v > 0 && v == Math.ffloor(v)): {}
				case _: a.error('$f is a size in points, a whole number above 0, not ${x.describe()}', x.pos);
			}
		}
		var feature = switch r.get("feature") {
			case null: false;
			case {value: KBool(b)}: b;
			case x: a.error('feature is true or false, not ${x.describe()}', x.pos);
		}
		for (f in ["caption", "background", "color", "feature"]) {
			var x = r.get(f);
			if (x != null && !store) a.error('$f is a store screenshot\'s (store: true)', x.pos);
		}
		return {
			name: name,
			render: render,
			seed: int(r, "seed", a) ?? 1,
			width: int(r, "width", a),
			height: int(r, "height", a),
			store: store,
			caption: caption,
			background: int(r, "background", a),
			color: int(r, "color", a),
			feature: feature
		};
	}

	// (an integer literal's field, or null)
	static function int(r:KObjectReader, field:String, a:Adapter):Null<Int> {
		var x = r.get(field);
		return x == null ? null : switch x.value {
			case KInt(i): i;
			case KFloat(f) if (f == Math.ffloor(f) && Math.abs(f) < 2147483648.0): Std.int(f);
			case _: a.error('$field is an integer literal, not ${x.describe()}', x.pos);
		}
	}
}

typedef StoryFields = {
	name:String,
	render:KFunction,
	seed:Int,
	width:Null<Int>,
	height:Null<Int>,
	store:Bool,
	caption:Null<String>,
	background:Null<Int>,
	color:Null<Int>,
	feature:Bool
}
