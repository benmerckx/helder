package helder.story;

import helder.story.Story;
import helder.ui.*;
import helder.view.*;

// The stories registered (Story.story), mounted headless (mount: a Ui of
// a size, the story's view rendered into its root, the clock's
// transitions finished until Controls.settled), and as tests (test: each
// story's tree snapshotted, helder test's runner calls it for a
// .story.hx file: helder.cli.TestCommand)
class Stories {
	public static final all:Array<Story> = [];

	// (the size a story is tested at: a phone's, in points)
	public static inline var WIDTH = 390;
	public static inline var HEIGHT = 844;

	public static function add(s:Story):Story {
		if (Lambda.exists(all, o -> o.name == s.name)) throw 'helder.story: two stories named "${s.name}"';
		all.push(s);
		return s;
	}

	// the stories a file's stories() registers
	public static function of(register:Void->Void):Array<Story> {
		var before = all.length;
		register();
		return all.slice(before);
	}

	// a story mounted in a Ui of width x height (points) with a text engine
	public static function mount(s:Story, width:Float, height:Float, text:TextEngine, ?scale:Float):{ui:Ui, controls:Controls} {
		var ui = new Ui(text, width, height);
		if (scale != null) ui.scale = scale;
		var c = new Controls(s.screenshot?.seed ?? 1);
		Render.render(s.build(c), ui.root);
		settle(ui, c);
		return {ui: ui, controls: c};
	}

	// transitions finished and the tree laid out, until the story says it is settled (at most 100 rounds)
	public static function settle(ui:Ui, c:Controls) {
		var rounds = 0;
		do {
			Clock.finish();
			ui.update();
		} while (!c.settled() && ++rounds < 100);
		if (!c.settled()) throw "helder.story: the story never settled (Controls.settled stayed false)";
	}

	// the tree as text: each node's tag (or kind), box and text, indented
	public static function tree(s:Story, width = WIDTH, height = HEIGHT):String {
		var m = mount(s, width, height, new StoryText());
		var out = [];
		function walk(n:Node, depth:Int) {
			var kind = Type.getClassName(Type.getClass(n)).split(".").pop();
			var line = StringTools.lpad("", " ", 2 * depth) + kind + (n.tag != null ? '#${n.tag}' : "") + ' ${r(n.absX)},${r(n.absY)} ${r(n.width)}x${r(n.height)}';
			if (Std.isOfType(n, TextNode)) line += ' "${(cast n : TextNode).text}"';
			out.push(line);
			for (c in n.children)
				if (c.style.display != None) walk(c, depth + 1);
		}
		walk(m.ui.root, 0);
		return out.join("\n");
	}

	static function r(v:Float):String
		return Std.string(Math.round(v * 10) / 10);

	// a .story.hx file's stories as tests: each one's tree against its snapshot
	public static function test(register:Void->Void) {
		for (s in of(register))
			helder.test.Test.test("story " + s.name, () -> helder.test.Snapshots.check(s.name, tree(s), s.pos));
	}
}
