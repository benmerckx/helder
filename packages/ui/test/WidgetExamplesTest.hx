#if !macro
import hxmc.theme.Shadcn;
import hxmc.ui.*;
import hxmc.view.*;
#end

// The widgets' reference checked (make ui-check, on Eval): each example of
// examples/widgets rendered under Shadcn.sheet and with no sheet, laid out,
// a slot of its widget in the tree (or the overlay's); then WidgetDocs read
// from Widgets.hx: every widget documented, each of its props, and every
// widget not a part of another with an example.
//   WidgetExamplesTest
class WidgetExamplesTest {
	#if !macro
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('WidgetExamplesTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	#end

	// (each <Name>Example class beside WidgetExample.hx: its widget's name and view)
	static macro function examples():haxe.macro.Expr {
		var dir = haxe.io.Path.directory(haxe.macro.Context.resolvePath("WidgetExample.hx"));
		var names = [
			for (f in sys.FileSystem.readDirectory(dir))
				if (StringTools.endsWith(f, "Example.hx") && f != "WidgetExample.hx") f.substr(0, f.length - 3)
		];
		names.sort(Reflect.compare);
		var list = [for (n in names) macro {name: $v{n.substr(0, n.length - 7)}, view: () -> $i{n}.view()}];
		return macro $a{list};
	}

	static macro function paths():haxe.macro.Expr {
		var widgets = haxe.macro.Context.resolvePath("hxmc/ui/widgets/Widgets.hx");
		var dir = haxe.io.Path.directory(haxe.macro.Context.resolvePath("WidgetExample.hx"));
		return macro {widgets: $v{widgets}, examples: $v{dir}};
	}

	#if !macro
	static function slots(n:Node, out:Map<String, Bool>) {
		if (n.slot != null) out[n.slot] = true;
		for (c in n.children)
			slots(c, out);
	}

	static function main() {
		var p = paths();
		var docs = WidgetDocs.read(sys.io.File.getContent(p.widgets), p.examples);
		var byName = [for (w in docs) (w.name : String) => w];
		for (e in examples()) {
			var w = byName[e.name];
			check(e.name + "Example: a widget of that name", w != null);
			for (sheet in [Shadcn.sheet, null]) {
				var ui = new Ui(new MonoText(), 480, 320);
				if (sheet != null) ui.theme = sheet;
				var seen = new Map<String, Bool>();
				try {
					Render.render(e.view(), ui.root);
					ui.update();
					slots(ui.root, seen);
					slots(ui.overlay, seen);
				} catch (x:Dynamic) {
					check(e.name + "Example" + (sheet == null ? " (no sheet)" : "") + " renders", false, Std.string(x));
					continue;
				}
				if (w == null) continue;
				var mine = [for (s in (w.slots : Array<String>)) if (seen.exists(s)) s];
				check(e.name + "Example" + (sheet == null ? " (no sheet)" : "") + ": its widget's slots in the tree", (w.slots : Array<String>).length == 0 || mine.length > 0,
					(w.slots : Array<String>).join(" "));
			}
		}
		for (m in WidgetDocs.missing(docs))
			check("the reference", false, m);
		Sys.println('WidgetExamplesTest: ${docs.length} widgets, ${examples().length} examples, $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
	#end
}
