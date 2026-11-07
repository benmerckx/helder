import helder.markup.Syntax;
import helder.syntax.Cst;
import helder.syntax.Document;
import helder.syntax.Edits;
import helder.syntax.Lexer;
import helder.syntax.Scanner;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The syntax lane's checks of helder.syntax on the repository's own files
// (bun run test syntax; on Eval and natively):
// - every .ts and .tsx file, and every .hx file with markup, read and
//   printed back: the same bytes (the tree's leaves cover the file, no gap);
//   random edits of its elements read again and undone, byte for byte;
//   each read structurally (its brackets and markup) but the ones listed
//   in FLAT, which do not balance (Haxe's #if branches);
// - each Haxe markup literal read as helder.markup.Syntax's parser (the
//   macro's) reads it: the same elements, names and attributes, in order;
// - the time a read takes, a file of 2000 lines and more (a few ms natively).
//   Check [--quiet]
class Check {
	static var failed = 0;
	static var checks = 0;

	// (files that read flat: brackets that do not balance across #if branches)
	static final FLAT:Array<String> = [];

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('syntax: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var files = [];
		for (d in ["src", "examples", "apps", "tests", "site"])
			if (FileSystem.exists(d)) walk(d, files);
		files.sort(Reflect.compare);
		var read = 0, tags = 0, markup = 0, elements = 0, literals = 0, flat = [], bytes = 0, fuzzed = 0;
		var largest = {path: "", lines: 0, ms: 0.0};
		for (path in files) {
			var lang = Lang.of(path);
			var text = File.getContent(path);
			var t0 = haxe.Timer.stamp();
			var doc = Document.parse(text, lang);
			var ms = (haxe.Timer.stamp() - t0) * 1000;
			var els = doc.elements();
			if (lang == Haxe && els.length == 0 && doc.structured) continue;
			if (lang == Haxe && !doc.structured && text.indexOf("implements Markup") < 0 && text.indexOf("View.view(") < 0
				&& text.indexOf("implements helder.view.Markup") < 0) continue;
			read++;
			bytes += text.length;
			if (els.length > 0) markup++;
			elements += els.length;
			var printed = try doc.print() catch (e:Dynamic) "<" + Std.string(e) + ">";
			check('$path: printed back byte for byte', printed == text, firstDifference(printed, text));
			if (!doc.structured) flat.push('$path (${doc.error})');
			var lines = text.split("\n").length;
			if (lines > largest.lines) largest = {path: path, lines: lines, ms: ms};
			if (lang == Haxe) literals += againstParser(path, doc);
			if (els.length > 0) fuzzed += fuzz(path, doc);
			if (doc.structured && doc.backtracks.length == 0) tags += lexed(path, doc);
			for (b in doc.backtracks)
				Sys.println('syntax: $path:${doc.lineCol(b).line}: "<" read as code (' + haxe.Json.stringify(text.substr(b, 30)) + ")");
		}
		for (f in flat)
			check('read structurally: $f', Lambda.exists(FLAT, x -> f.startsWith(x)));
		Sys.println('syntax: $read files read and printed back ($markup with markup, $elements elements, ${Math.round(bytes / 1024)} KB), $literals Haxe literals as the macro\'s parser reads them, $fuzzed random edits, $tags tag names lexed line by line as tags'
			+ (flat.length > 0 ? ', ${flat.length} flat' : ""));
		// (the read of a file of 2000 lines and more: the largest, else one made of the todo example)
		var big = largest.lines >= 2000 ? File.getContent(largest.path) : repeated("examples/todo/Todo.hx", 2000);
		var lang = largest.lines >= 2000 ? Lang.of(largest.path) : Haxe;
		var runs = 5, best = 1e9;
		for (_ in 0...runs) {
			var t0 = haxe.Timer.stamp();
			Document.parse(big, lang);
			best = Math.min(best, (haxe.Timer.stamp() - t0) * 1000);
		}
		Sys.println('syntax: a read of ${big.split("\n").length} lines (${largest.lines >= 2000 ? largest.path : "the todo example, repeated"}): ${Math.round(best * 10) / 10} ms');
		// (the same file lexed line by line, as an editor highlights it)
		var bigLines = big.split("\n"), lbest = 1e9, out = [];
		for (_ in 0...runs) {
			var lx = new Lexer(lang), st = lx.start(), t0 = haxe.Timer.stamp();
			for (l in bigLines) {
				out.resize(0);
				st = lx.line(l, st, out);
			}
			lbest = Math.min(lbest, (haxe.Timer.stamp() - t0) * 1000);
		}
		Sys.println('syntax: its lines lexed for highlighting (helder.syntax.Lexer): ${Math.round(lbest * 10) / 10} ms');
		Sys.println('syntax: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	// the file lexed line by line (helder.syntax.Lexer, an editor's
	// highlighting): its tokens in order inside each line, and every tag
	// name of its tree a Tag token there; the tag names checked
	static function lexed(path:String, doc:Document):Int {
		var lx = new Lexer(doc.lang), st = lx.start(), out = [];
		var lines = doc.text.split("\n"), at = 0, ordered = true;
		var tagAt = new Map<Int, Int>();
		for (l in lines) {
			out.resize(0);
			st = lx.line(l, st, out);
			var k = 0, last = 0;
			while (k < out.length) {
				if (out[k] < last || out[k + 1] <= out[k] || out[k + 1] > l.length) ordered = false;
				last = out[k + 1];
				if (out[k + 2] == (TokenClass.Tag : Int)) tagAt.set(at + out[k], at + out[k + 1]);
				k += 3;
			}
			at += l.length + 1;
		}
		check('$path: lexed tokens in order inside their lines', ordered);
		var count = 0, missed = [];
		doc.root.walk(n -> if (n.kind == TagName) {
			count++;
			if (tagAt.get(n.start) != n.end) missed.push(doc.lineCol(n.start).line + ":" + n.text(doc.text));
		});
		check('$path: every tag name lexed as a tag', missed.length == 0, missed.slice(0, 5).join(", "));
		return count;
	}

	// (a seeded generator: the same edits each run)
	static var seed = Std.parseInt(Sys.getEnv("SYNTAX_SEED") ?? "") ?? 7;

	static function random(n:Int):Int {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return (seed >> 8) % n;
	}

	// random edits of a file's elements (an attribute set or removed, an
	// element wrapped, unwrapped, deleted, renamed, moved, a child inserted): each
	// edited text read again structurally and printed back, as many elements
	// as the edit makes, its inverse the text before; the edits made
	static function fuzz(path:String, doc:Document):Int {
		var made = 0;
		for (round in 0...6) {
			var els = doc.elements();
			if (els.length == 0) break;
			var el = els[random(els.length)];
			var before = els.length, count = 1;
			el.node.walk(n -> if (n != el.node && n.kind == Element) count++);
			var op = random(8);
			var expect = before;
			var tx = try switch op {
				case 0: Edits.setAttribute(doc, el, "fuzz-" + round, random(2) == 0 ? AString("v" + round) : ACode(Std.string(round)));
				case 1 if (el.attrs().length > 0):
					// (an attribute's markup goes with it)
					var a = el.attrs()[random(el.attrs().length)];
					a.node.walk(n -> if (n.kind == Element) expect--);
					Edits.removeAttribute(doc, el, a.name);
				case 2:
					expect = before + 1;
					Edits.wrap(doc, el, "view");
				case 3 if (el.close != null && el.name != ""):
					// (a literal's root of other than one element: a fragment)
					var kids = el.children();
					expect = el.parent() == null && (kids.length != 1 || kids[0].kind != Element) ? before : before - 1;
					// (its attributes' markup goes with them: fallback={<text/>})
					el.open.walk(n -> if (n.kind == Element) expect--);
					Edits.unwrap(doc, el);
				case 4 if (el.parent() != null):
					expect = before - count;
					Edits.delete(doc, el);
				case 5 if (el.name != ""): Edits.rename(doc, el, "fuzzed");
				case 6:
					expect = before + 1;
					Edits.insertChild(doc, el, random(el.children().length + 1), "<text>fuzz</text>");
				case 7 if (el.parent() != null):
					// (into another element of the same literal, not one inside it)
					var to = els[random(els.length)];
					if (to.node.start >= el.node.start && to.node.end <= el.node.end) continue;
					Edits.move(doc, el, to, random(to.children().length + 1));
				case _: continue;
			} catch (e:helder.syntax.Transaction.SourceError) continue;
			var after = tx.apply(doc.text);
			var next = Document.parse(after, doc.lang);
			var where = '$path:${doc.lineCol(el.start).line}: edit $op of <${el.name}>';
			check('$where: read again structurally', next.structured, next.error);
			check('$where: printed back', next.print() == after);
			check('$where: undone by its inverse', tx.inverse.apply(after) == doc.text);
			check('$where: $expect elements', next.elements().length == expect,
				'${next.elements().length}: ' + haxe.Json.stringify(doc.text.substring(doc.lineStart(el.start), el.end)) + " to " + haxe.Json.stringify(after.substring(doc.lineStart(el.start), Std.int(Math.min(after.length, el.end + after.length - doc.text.length)))));
			doc = next;
			made++;
		}
		return made;
	}

	// (path's text repeated to lines lines)
	static function repeated(path:String, lines:Int):String {
		var t = File.getContent(path), b = new StringBuf(), n = 0;
		while (n < lines) {
			b.add(t);
			n += t.split("\n").length;
		}
		return b.toString();
	}

	static function walk(dir:String, out:Array<String>) {
		for (f in FileSystem.readDirectory(dir)) {
			var p = '$dir/$f';
			if (f == "node_modules" || f == "bin" || f.startsWith(".")) continue;
			if (FileSystem.isDirectory(p)) walk(p, out);
			else if (f.endsWith(".ts") || f.endsWith(".tsx") || f.endsWith(".hx")) out.push(p);
		}
	}

	static function firstDifference(a:String, b:String):String {
		var k = 0;
		while (k < a.length && k < b.length && a.charAt(k) == b.charAt(k))
			k++;
		return 'at $k: ' + haxe.Json.stringify(a.substr(k, 40)) + " against " + haxe.Json.stringify(b.substr(k, 40));
	}

	// each top literal of a Haxe file against helder.markup.Syntax's parser: the literals compared
	static function againstParser(path:String, doc:Document):Int {
		var n = 0;
		for (e in doc.elements()) {
			if (e.node.parent != null && e.node.parent.kind == Element) continue;
			var src = e.source();
			var parsed = try new Parser(src, (m, at, len) -> throw '$m at $at').document() catch (x:Dynamic) {
				check('$path:${doc.lineCol(e.start).line}: the macro\'s parser reads the literal', false, Std.string(x));
				continue;
			}
			var mine = shape(doc, e), theirs = pshape(parsed);
			check('$path:${doc.lineCol(e.start).line}: the same elements as the macro\'s parser', mine == theirs, mine + "\n  against " + theirs);
			n++;
		}
		return n;
	}

	// (an element's names: its name, its attributes', its child elements' (not those in holes))
	static function shape(doc:Document, e:Element):String
		return "<" + e.name + [for (a in e.attrs()) " " + a.name].join("") + ">" + [for (c in e.elements()) shape(doc, c)].join("") + "</>";

	static function pshape(n:PNode):String
		return switch n.kind {
			case PElement(name, attrs, children, _): "<" + name + [for (a in attrs) " " + a.name].join("") + ">" + [for (c in children) pshape(c)].join("") + "</>";
			case PFragment(children): "<>" + [for (c in children) pshape(c)].join("") + "</>";
			case _: "";
		}
}
