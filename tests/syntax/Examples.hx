import helder.syntax.Cst;
import helder.syntax.Document;
import helder.syntax.Edits;
import helder.syntax.Scanner;
import helder.syntax.Transaction;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The syntax-run lane's scripted edits (bun run test syntax-run): the
// examples' sources (todo, ts-todo, mail, the guide's screen, the viewer's
// shell and shader) copied into <out>, each edited through helder.syntax
// (an attribute set, added, removed; a literal; a child inserted; an
// element moved, deleted, wrapped, unwrapped, renamed; a component
// renamed; a definition's field), each edit's text changed only in the
// span expected (the first and last bytes that differ inside it), undone
// by its inverse byte for byte, the whole read again structurally; then
// (tests/Run.hx) each built and run headless, and here their --tree
// checked for each change: a colour, a node added, moved, wrapped, gone,
// a component's new name in the source map.
//   Examples prepare <out>
//   Examples check <out>
class Examples {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('syntax-run: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var args = Sys.args();
		var out = args[1];
		switch args[0] {
			case "prepare": prepare(out);
			case "check": checkTrees(out);
			case _: throw "Examples prepare|check <out>";
		}
		Sys.println('syntax-run: ${args[0]}: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	// ---- the edits

	static function prepare(out:String) {
		rmrf(out);
		copy("examples/todo/Todo.hx", '$out/todo/Todo.hx');
		copyDir("examples/ts-todo", '$out/ts-todo');
		copyDir("examples/ts-todo", '$out/ts-todo-story');
		copy("examples/mail/Mail.hx", '$out/mail/Mail.hx');
		for (f in FileSystem.readDirectory("tests/ui"))
			if (f.endsWith(".hx")) copy('tests/ui/$f', '$out/guide/$f');
		File.saveContent('$out/guide/GuideScreen.hx', GUIDE_SCREEN);
		copyDir("apps/viewer", '$out/viewer');

		todo('$out/todo/Todo.hx', "todo");
		todo('$out/ts-todo/app.tsx', "ts-todo");
		edits('$out/ts-todo-story/app.test.tsx', [
			{
				what: "the story's name, a definition's field",
				edit: d -> {
					var o = d.definition("story", "Todo");
					var f = o.field("name");
					{tx: Edits.setField(d, o, "name", '"todo, edited"'), from: f.first.start, to: f.last.end};
				}
			}
		]);
		mail('$out/mail/Mail.hx');
		guide('$out/guide/GuideTest.hx');
		viewer('$out/viewer/src/viewer/Shell.hx', '$out/viewer/src/viewer/PhotoShader.hx');
	}

	// the todos, Haxe's and TypeScript's: the same edits
	static function todo(path:String, app:String) {
		inline function title(d:Document)
			return Lambda.find(d.elementsNamed("text"), e -> e.attr("color")?.valueText() == "#3b82f6");
		inline function root(d:Document)
			return Lambda.find(d.elementsNamed("view"), e -> e.attr("font-family")?.valueText() == "DejaVu Sans");
		edits(path, [
			{
				what: '$app: the title\'s colour set',
				edit: d -> {
					var t = title(d);
					{tx: Edits.setAttribute(d, t, "color", AString("#ef4444")), from: t.attr("color").node.start, to: t.attr("color").node.end};
				}
			},
			{
				what: '$app: the root\'s padding, a literal',
				edit: d -> {
					var l = root(d).attr("padding").literal();
					{tx: Edits.setLiteral(d, l.start, 16), from: l.start, to: l.end};
				}
			},
			{
				what: '$app: the root\'s background removed',
				edit: d -> {
					var r = root(d);
					{tx: Edits.removeAttribute(d, r, "background"), from: r.open.start, to: r.open.end};
				}
			},
			{
				what: '$app: a hint inserted after the title',
				edit: d -> {
					var r = root(d), kids = r.children();
					{tx: Edits.insertChild(d, r, 1, '<text tag="hint" color="#71717a">Press Enter to add</text>'), from: kids[0].end, to: kids[1].start};
				}
			},
			{
				what: '$app: the count moved after the filters',
				edit: d -> {
					var left = d.elementWith("tag", "left"), footer = left.parent();
					{tx: Edits.move(d, left, footer, 2), from: footer.open.end, to: footer.close.start};
				}
			},
			{
				what: '$app: Add wrapped in a view',
				edit: d -> {
					var add = d.elementWith("tag", "add");
					var p = add.parent();
					{tx: Edits.wrap(d, add, "view", [{name: "tag", value: AString("add-box")}, {name: "padding", value: ACode("2")}]), from: p.open.end, to: p.close.start};
				}
			},
			{
				what: '$app: Checkbox renamed Toggle, its function and its element',
				edit: d -> {
					var el = d.elementsNamed("Checkbox")[0];
					{tx: Edits.renameComponent(d, "Checkbox", "Toggle"), from: d.text.indexOf("function Checkbox"), to: el.open.end};
				}
			}
		]);
	}

	static function mail(path:String) {
		edits(path, [
			{
				what: "mail: Delete moved first in the bar",
				edit: d -> {
					var del = d.elementWith("tag", "delete"), bar = del.parent();
					{tx: Edits.move(d, del, bar, 0), from: bar.open.end, to: del.end + 1};
				}
			},
			{
				what: "mail: the search field's width, a literal",
				edit: d -> {
					var l = d.elementWith("tag", "search").attr("width").literal();
					{tx: Edits.setLiteral(d, l.start, 260), from: l.start, to: l.end};
				}
			},
			{
				what: "mail: Mark unread deleted",
				edit: d -> {
					var u = d.elementWith("tag", "unread");
					{tx: Edits.delete(d, u), from: d.lineStart(u.start) - 1, to: u.end};
				}
			},
			{
				what: "mail: the bar's spacer renamed a scroll",
				edit: d -> {
					var spacer = Lambda.find(d.elementsNamed("view"), e -> e.selfClosing && e.attr("grow")?.valueText() == "1" && e.attrs().length == 1);
					{tx: Edits.rename(d, spacer, "scroll"), from: spacer.start, to: spacer.end};
				}
			},
			{
				what: "mail: the reader's Show unwrapped",
				edit: d -> {
					var show = Lambda.find(d.elementsNamed("Show"), e -> e.attr("when")?.valueText() == "selected() != null");
					{tx: Edits.unwrap(d, show), from: show.start, to: show.end};
				}
			},
			{
				what: "mail: the folders wrapped in a sidebar",
				edit: d -> {
					var f = d.elementWith("tag", "folders");
					{tx: Edits.wrap(d, f, "view", [{name: "tag", value: AString("sidebar")}, {name: "padding", value: ACode("4")}]), from: f.start, to: f.end};
				}
			}
		]);
	}

	static function guide(path:String) {
		edits(path, [
			{
				what: "guide: the total's colour added",
				edit: d -> {
					var t = d.elementWith("tag", "total");
					{tx: Edits.setAttribute(d, t, "color", AString("#16a34a")), from: t.open.start, to: t.open.end};
				}
			},
			{
				what: "guide: a note inserted in the order's card",
				edit: d -> {
					var card = Lambda.find(d.elementsNamed("Card"), e -> e.attr("title")?.valueText() == "Tickets"), kids = card.children();
					{tx: Edits.insertChild(d, card, 2, '<text tag="note">Children under 3 go free</text>'), from: kids[1].end, to: kids[2].start};
				}
			},
			{
				what: "guide: the search button's colour set",
				edit: d -> {
					var s = d.elementWith("tag", "search");
					{tx: Edits.setAttribute(d, s, "color", AString("#dc2626")), from: s.attr("color").node.start, to: s.attr("color").node.end};
				}
			},
			{
				what: "guide: Stepper renamed Counter",
				edit: d -> {
					var last = d.elementsNamed("Stepper").pop();
					{tx: Edits.renameComponent(d, "Stepper", "Counter"), from: d.text.indexOf("function Stepper"), to: last.open.end};
				}
			}
		]);
	}

	static function viewer(shell:String, shader:String) {
		inline function status(d:Document)
			return d.elementWith("tag", "status");
		edits(shell, [
			{
				what: "viewer: the status bar's background set",
				edit: d -> {
					var a = status(d).attr("background").node;
					{tx: Edits.setAttribute(d, status(d), "background", AString("#1e3a8a")), from: a.start, to: a.end};
				}
			},
			{
				what: "viewer: the status bar's padding set",
				edit: d -> {
					var a = status(d).attr("padding").node;
					{tx: Edits.setAttribute(d, status(d), "padding", AString("6 20")), from: a.start, to: a.end};
				}
			},
			{
				what: "viewer: a note inserted first in the status bar",
				edit: d -> {
					var s = status(d);
					{tx: Edits.insertChild(d, s, 0, '<text tag="status-note" color="#fbbf24">edited</text>'), from: s.open.end, to: s.children()[0].start};
				}
			}
		]);
		edits(shader, [
			{
				what: "viewer: the photo shader's fragment, a literal in a definition's field",
				edit: d -> {
					var f = d.definition("shader", "PhotoShader").field("fragment");
					var at = d.text.indexOf("12.92", f.first.start);
					if (at < 0 || at > f.end) throw "no 12.92 in the fragment";
					{tx: Edits.setLiteral(d, at, 12.9232), from: at, to: at + 5};
				}
			}
		]);
	}

	// a file edited step by step: each step's change inside its span, its inverse the text before; the file saved
	static function edits(path:String, steps:Array<{what:String, edit:Document->{tx:Transaction, from:Int, to:Int}}>) {
		var original = File.getContent(path);
		var doc = Document.parse(original, Lang.of(path));
		check('$path: read structurally', doc.structured, doc.error);
		var done:Array<Transaction> = [];
		for (s in steps) {
			var r = try s.edit(doc) catch (e:Dynamic) {
				check(s.what, false, Std.string(e));
				continue;
			}
			var before = doc.text, after = r.tx.apply(before);
			// (the text before the span and after it kept: what is outside it the same, byte for byte)
			var kept = r.from <= r.to && r.from + (before.length - r.to) <= after.length && StringTools.startsWith(after, before.substr(0, r.from))
				&& StringTools.endsWith(after, before.substr(r.to));
			var a = 0;
			while (a < before.length && a < after.length && before.charCodeAt(a) == after.charCodeAt(a))
				a++;
			var e1 = before.length, e2 = after.length;
			while (e1 > a && e2 > a && before.charCodeAt(e1 - 1) == after.charCodeAt(e2 - 1)) {
				e1--;
				e2--;
			}
			var line = doc.lineCol(a).line;
			check('${s.what}: changed', after != before);
			check('${s.what}: only in its span', kept,
				'bytes $a-$e1 changed, the span ${r.from}-${r.to}: ' + haxe.Json.stringify(before.substring(a, e1)) + " to " + haxe.Json.stringify(after.substring(a, e2)));
			check('${s.what}: undone by its inverse', r.tx.inverse.apply(after) == before);
			var next = Document.parse(after, doc.lang);
			check('${s.what}: read again structurally', next.structured, next.error);
			Sys.println('syntax-run: $path:$line: ${s.what} (${e1 - a} bytes to ${e2 - a})');
			done.push(r.tx);
			doc = next;
		}
		// (every step undone, the last first: the file as it was)
		var text = doc.text;
		var k = done.length;
		while (k-- > 0)
			text = done[k].inverse.apply(text);
		check('$path: every edit undone, the file as it was', text == original);
		File.saveContent(path, doc.text);
	}

	// ---- the trees

	static function checkTrees(out:String) {
		for (app in ["todo", "ts-todo"]) {
			var n = tree('$out/$app-end.json');
			var title = byText(n, "todos");
			check('$app: the title red', title?.color == "#ef4444", title?.color);
			check('$app: the padding 16', title != null && title.rect[0] == 16, haxe.Json.stringify(title?.rect));
			var root = n[0];
			check('$app: the root without a background', root != null && root.fill == null, root?.fill);
			var hint = byTag(n, "hint");
			check('$app: the hint after the title', hint != null && hint.text == "Press Enter to add" && n.indexOf(hint) == n.indexOf(title) + 1);
			var left = byTag(n, "left"), all = byTag(n, "filter-all");
			check('$app: the count after the filters', left != null && all != null && left.rect[0] > all.rect[0], '${left?.rect} ${all?.rect}');
			var add = byTag(n, "add");
			check('$app: Add in its box', add != null && (add.path : String).endsWith("add-box/add"), add?.path);
			var boxes = [for (x in n) if (x.role == "checkbox") x];
			check('$app: the checkboxes mounted by Toggle', boxes.length > 0 && Lambda.foreach(boxes, b -> b.component?.name == "Toggle"),
				haxe.Json.stringify(boxes[0]?.component?.name));
		}
		var m = tree('$out/mail.json');
		var del = byTag(m, "delete"), arch = byTag(m, "archive");
		check("mail: Delete first in the bar", del != null && arch != null && del.rect[0] < arch.rect[0], '${del?.rect} ${arch?.rect}');
		check("mail: the search field 260 wide", byTag(m, "search")?.rect[2] == 260, haxe.Json.stringify(byTag(m, "search")?.rect));
		check("mail: Mark unread gone", byTag(m, "unread") == null);
		check("mail: the spacer a scroll", Lambda.exists(m, x -> x.tag == "scroll" && (x.path : String).split("/").length == 3), [for (x in m) if (x.tag == "scroll") x.path].join(" "));
		check("mail: the reader's subject shown, unwrapped", byTag(m, "reader-subject") != null);
		check("mail: the folders in the sidebar", (byTag(m, "folders")?.path : String)?.endsWith("sidebar/folders"), byTag(m, "folders")?.path);
		var g = tree('$out/guide.json');
		check("guide: the total green", byTag(g, "total")?.color == "#16a34a", byTag(g, "total")?.color);
		var note = byTag(g, "note"), total = byTag(g, "total");
		check("guide: the note before the total", note != null && total != null && note.rect[1] < total.rect[1]);
		var search:Dynamic = Lambda.find(g, x -> x.text == "Search");
		check("guide: Search red", search?.color == "#dc2626", search?.color);
		var steppers = [for (x in g) if (x.component?.name == "Counter") x];
		check("guide: the steppers mounted by Counter", steppers.length > 0 && !Lambda.exists(g, x -> x.component?.name == "Stepper"));
		var v = tree('$out/viewer-end.json');
		var st = byTag(v, "status"), sn = byTag(v, "status-note");
		check("viewer: the status bar blue", st?.fill == "#1e3a8a", st?.fill);
		check("viewer: the note first in it, 20 in", sn != null && st != null && sn.rect[0] == st.rect[0] + 20 && sn.text == "edited", '${sn?.rect} ${st?.rect}');
	}

	static function tree(path:String):Array<Dynamic> {
		if (!FileSystem.exists(path)) {
			check('$path written', false);
			return [];
		}
		var t:Dynamic = haxe.Json.parse(File.getContent(path));
		return t.nodes;
	}

	static function byTag(nodes:Array<Dynamic>, tag:String):Null<Dynamic>
		return Lambda.find(nodes, n -> n.tag == tag);

	static function byText(nodes:Array<Dynamic>, text:String):Null<Dynamic>
		return Lambda.find(nodes, n -> n.text == text);

	// ---- files

	static function copy(from:String, to:String) {
		FileSystem.createDirectory(haxe.io.Path.directory(to));
		File.copy(from, to);
	}

	static function copyDir(from:String, to:String) {
		FileSystem.createDirectory(to);
		for (f in FileSystem.readDirectory(from)) {
			if (f == "bin" || f == "node_modules") continue;
			if (FileSystem.isDirectory('$from/$f')) copyDir('$from/$f', '$to/$f') else File.copy('$from/$f', '$to/$f');
		}
	}

	static function rmrf(p:String) {
		if (!FileSystem.exists(p)) return;
		if (FileSystem.isDirectory(p)) {
			for (f in FileSystem.readDirectory(p))
				rmrf('$p/$f');
			FileSystem.deleteDirectory(p);
		} else FileSystem.deleteFile(p);
	}

	// the guide's screen (tests/ui/AccessApp.hx's guide): its widgets in a window
	static final GUIDE_SCREEN = "import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;

// (made by tests/syntax/Examples.hx: GuideTest's widgets, as AccessApp's guide screen)
class GuideScreen implements Markup {
	static function main() {
		var text = signal(\"A draft\"), subject = signal(\"Hi\"), body = signal(\"\"), name = signal(\"Ann\");
		var v:View = @:privateAccess <view padding={12} row-gap={12}>
			{GuideTest.Order({})}
			{GuideTest.Confirm({onYes: () -> {}})}
			{GuideTest.Greeting({name: name, onLink: () -> {}})}
			{GuideTest.SearchButton({onClick: () -> {}})}
			{GuideTest.Editor({text: text, onSave: () -> {}})}
			{GuideTest.Compose({subject: subject, body: body})}
		</view>;
		UiWindow.run(<Surface title=\"guide\" width={480} height={640}>{v}</Surface>);
	}
}
";
}
