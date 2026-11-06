package helder.story;

import haxe.macro.Expr;
#if macro
import haxe.macro.Context;
import helder.definition.HaxeAdapter;
#else
import haxe.PosInfos;
import helder.view.View;
import helder.view.graph.Graph;
import helder.view.graph.Signal;
#end

// Stories, as Storybook's: a `Foo.story.hx` file anywhere a test file may
// be (src/, tests/, the class paths) whose module-level values are made by
// story({...}), a definition (src/helder/compiler/DESIGN.md 4; its handler
// StoryDefinition, TypeScript's helder/story the same):
//
//   // src/game/Inventory.story.hx
//   package game;
//
//   import helder.story.Story;
//
//   final full = story({name: "Inventory/full", render: c -> new Inventory(c.number("slots", 24)).view()});
//   final shop = story({name: "Shop", store: true, caption: "Trade across the galaxy", seed: 7, render: c -> new Shop(c.random).view()});
//
// A story builds a view from its controls (Controls: each a signal with a
// name, a number, a flag, a choice, a colour, a text: an edit updates what
// is bound to it), in an owner of its own. Each is a test too: `helder
// test` mounts it headless in a phone's size with text laid out without
// fonts (StoryText) and snapshots its tree (Stories.tree: tags, boxes,
// texts) in Foo.story.snap. A story with store: true is a store
// screenshot: a deterministic scene (its seed for Controls.random,
// transitions finished, Controls.settled waited for) that `helder publish
// --screenshots` renders at each store's sizes (StoreShots), its caption
// over it. The fields are literals (render a function of the controls),
// checked where they are written. A release build (-D helder.release:
// helder build's) has no stories: story(...) is null there, and what only
// a story uses is not linked; helder test and publish link the story files
// alone (an app's own builds never see them).
@:definition macro function story(def:Expr):Expr {
	var a = new HaxeAdapter("story");
	var s = new StoryDefinition().generate(a.node(def), a);
	if (Context.defined("helder.release")) return macro(null : helder.story.Story);
	var render:Expr = s.render.source;
	if (s.render.params.length == 0) render = macro(_ : helder.story.Story.Controls) -> $render();
	var shot = s.store ? macro {caption: $v{s.caption}, background: $v{s.background}, color: $v{s.color}} : macro null;
	return macro @:pos(Context.currentPos()) new helder.story.Story($v{s.name}, $render, $v{s.seed}, $shot);
}

#if !macro
class Story {
	public final name:String;
	public final build:Controls->View;
	// Controls.random's seed
	public final seed:Int;
	// a store screenshot's settings (null: not one)
	public final screenshot:Null<StoreOptions>;
	public final pos:PosInfos;

	public function new(name:String, build:Controls->View, seed = 1, ?screenshot:StoreOptions, ?pos:PosInfos) {
		this.name = name;
		this.build = build;
		this.seed = seed;
		this.screenshot = screenshot;
		this.pos = pos;
	}

	// a file name of its name (Inventory/full: Inventory-full)
	public function slug():String
		return ~/[^A-Za-z0-9_-]+/g.replace(name, "-");
}

typedef StoreOptions = {
	// a line over the screenshot, in the template's band (null: the story alone, full bleed)
	?caption:String,
	// the caption band's colours (0xRRGGBB: #111827 and white)
	?background:Int,
	?color:Int,
}

// story({...})'s fields, as a TypeScript program gives them (helder/story:
// Stories.define, the definition checked them where they are written)
typedef StoryDef = {
	name:String,
	render:Controls->View,
	?seed:Int,
	?store:Bool,
	?caption:String,
	?background:Int,
	?color:Int,
}

// A story's controls: each a signal its view reads, recorded with its name
// and kind for an editor (the values a store screenshot uses are their
// defaults); random, a generator of the story's seed; settled, false while
// the scene is not ready (a store screenshot waits for it)
class Controls {
	public final seed:Int;
	public final list:Array<{name:String, kind:String, value:Dynamic, ?options:Array<String>}> = [];
	public final settled:Signal<Bool> = Graph.signal(true);

	var state:Int;

	public function new(seed = 1) {
		this.seed = seed;
		state = seed == 0 ? 0x9e3779b9 : seed;
		// (a few rounds first: small seeds' first numbers are small)
		for (_ in 0...4)
			random();
	}

	function add<T>(name:String, kind:String, value:T, ?options:Array<String>):Signal<T> {
		list.push({name: name, kind: kind, value: value, options: options});
		return Graph.signal(value);
	}

	public function number(name:String, value:Float):Signal<Float>
		return add(name, "number", value);

	public function bool(name:String, value:Bool):Signal<Bool>
		return add(name, "bool", value);

	public function text(name:String, value:String):Signal<String>
		return add(name, "text", value);

	public function choice(name:String, options:Array<String>, ?value:String):Signal<String>
		return add(name, "choice", value ?? options[0], options);

	// 0xAARRGGBB
	public function color(name:String, value:Int):Signal<Int>
		return add(name, "color", value);

	// the next of the seed's numbers in [0, 1) (xorshift32): the same story, the same scene
	public function random():Float {
		var x = state;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		state = x;
		return (x >>> 8) / 16777216.0;
	}
}
#end
