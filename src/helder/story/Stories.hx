package helder.story;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#else
import helder.story.Story;
import helder.ui.*;
import helder.view.*;
#end

// The stories of the story files (Story.story), registered (add), mounted
// headless (mount: a Ui of a size in a ScreenContext of its own, the
// story's view rendered into its root and brought to its moment: settle),
// and as tests (test: each story's tree snapshotted, helder test's runner
// calls it for a .story.hx file with its stories: of, helder.cli.TestCommand)
class Stories {
	// a module's stories: its module-level values made by story({...}), in
	// the order they are written (null in a release build: none)
	public static macro function of(module:String):Expr {
		var out = [];
		for (t in Context.getModule(module))
			switch t {
				case TInst(_.get() => c, _) if (c.kind.match(KModuleFields(_))):
					var fields = c.statics.get().filter(f -> switch haxe.macro.TypeTools.followWithAbstracts(f.type) {
						case TInst(_.get() => {pack: ["helder", "story"], name: "Story"}, _): true;
						case _: false;
					});
					fields.sort((a, b) -> Context.getPosInfos(a.pos).min - Context.getPosInfos(b.pos).min);
					for (f in fields) {
						var path = module.split(".").concat([f.name]);
						out.push(macro $p{path});
					}
				case _:
			}
		return macro [for (s in ([$a{out}] : Array<helder.story.Story>)) if (s != null) s];
	}

	#if !macro
	public static final all:Array<Story> = [];

	// (the size a story is tested at: a phone's, in points)
	public static inline var WIDTH = 390;
	public static inline var HEIGHT = 844;
	// (a playing story's frames a second of its clock, and how long it may play before it is an error: settle)
	public static inline var FPS = 60;
	public static inline var TIMEOUT = 120;

	public static function add(s:Story):Story {
		if (Lambda.exists(all, o -> o.name == s.name)) throw 'helder.story: two stories named "${s.name}"';
		all.push(s);
		return s;
	}

	// story({...}) in a TypeScript program (helder/story; the definition
	// checked its fields where they are written)
	public static function define(def:StoryDef):Story
		return new Story(def.name, def.render, def.seed ?? 1, def.store == true ? {caption: def.caption, background: def.background, color: def.color, feature: def.feature == true} : null, def.width,
			def.height);

	// a story mounted in a Ui of width x height (points) with a text engine
	// (helder.text's own shaping and rasters: a story looks the same on every
	// OS), in a ScreenContext of its own (its clock, timers and settings: what
	// one story leaves running is not the next one's), brought to its moment
	// (settle); the context, to run in it after (dispose: the view's owner)
	public static function mount(s:Story, width:Float, height:Float, text:TextEngine, ?scale:Float):{ui:Ui, controls:Controls, context:ScreenContext, dispose:Void->Void} {
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		var context = new ScreenContext(s.name);
		return context.run(() -> {
			var ui = new Ui(text, width, height);
			if (scale != null) ui.scale = scale;
			var c = new Controls(s.seed);
			var dispose = render(s, c, ui.root);
			settle(ui, c, s.name);
			{ui: ui, controls: c, context: context, dispose: dispose};
		});
	}

	// a story's view made from its controls and rendered into parent (wrap:
	// something round it, a store screenshot's caption band); the disposer
	// removes it and lets the story go (Controls.dispose: what it asked,
	// Controls.onDispose, a game's scene world freed)
	public static function render(s:Story, c:Controls, parent:Node, ?wrap:View->View):Void->Void {
		var v = s.build(c);
		var d = Render.render(wrap != null ? wrap(v) : v, parent);
		return () -> {
			d();
			c.dispose();
		};
	}

	// a story brought to its moment, in its context (current): settled as it
	// is built, its transitions finished and the tree laid out (until it says
	// it is settled, at most 100 rounds); not (Controls.play, a scene still
	// loading), its frames run on its clock, 1/FPS s apart, each the clock
	// ticked (its timers, its steps: a game's frame), the tree laid out and
	// frame called (a renderer's paint), until it is settled: the moment, its
	// last frame not painted (the caller's). TIMEOUT s of its clock at most,
	// then an error naming it
	public static function settle(ui:Ui, c:Controls, ?name:String, ?frame:Void->Void) {
		var what = name == null ? "the story" : 'the story "$name"';
		// (what the story wrote as it rendered committed: its settled read as it is)
		helder.view.graph.Graph.flush();
		if (c.settled()) {
			var rounds = 0;
			do {
				Clock.finish();
				ui.update();
			} while (!c.settled() && ++rounds < 100);
			if (!c.settled()) throw 'helder.story: $what never settled (Controls.settled stayed false)';
			return;
		}
		var start = Clock.now, frames = 0;
		while (true) {
			if (frames >= TIMEOUT * FPS)
				throw 'helder.story: $what never settled: Controls.settled still false after $TIMEOUT s of its clock ($frames frames: its Controls.play, or what it waits for)';
			frames++;
			Clock.tick(start + frames / FPS);
			ui.update();
			if (c.settled()) return;
			if (frame != null) frame();
		}
	}

	// the tree as text: each node's tag (or kind), box and text, indented
	// (in a phone's size, WIDTH x HEIGHT, unless given)
	public static function tree(s:Story, ?width:Int, ?height:Int):String {
		var m = mount(s, width ?? WIDTH, height ?? HEIGHT, new StoryText());
		var out = [];
		function walk(n:Node, depth:Int) {
			var c = Type.getClass(n), kind = c == null ? "Node" : Type.getClassName(c).split(".").pop();
			var line = StringTools.lpad("", " ", 2 * depth) + kind + (n.tag != null ? '#${n.tag}' : "") + ' ${r(n.absX)},${r(n.absY)} ${r(n.width)}x${r(n.height)}';
			if (Std.isOfType(n, TextNode)) line += ' "${(cast n : TextNode).text}"';
			out.push(line);
			for (c in n.children)
				if (c.style.display != None) walk(c, depth + 1);
		}
		walk(m.ui.root, 0);
		// (what it left running stopped: its owner disposed in its context)
		m.context.run(m.dispose);
		return out.join("\n");
	}

	static function r(v:Float):String
		return Std.string(Math.round(v * 10) / 10);

	// a .story.hx file's stories as tests (Stories.of): each one's tree against its snapshot
	public static function test(stories:Array<Story>) {
		for (s in stories)
			helder.test.Test.test("story " + add(s).name, () -> helder.test.Snapshots.check(s.name, tree(s), s.pos));
	}
	#end
}
