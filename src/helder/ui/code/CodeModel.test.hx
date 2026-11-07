package helder.ui.code;

import helder.syntax.Lexer;
import helder.syntax.Scanner.Lang;
import helder.syntax.Transaction;
import helder.test.Test;
import helder.ui.code.CodeLanguage;
import helder.ui.code.CodeModel;

// helder.ui.code's document: the rope against a String edited the same way
// (lines, offsets, UTF-8), the history (runs of typing, the selections
// restored), multi-cursor edits, the commands (pairs, Enter's indentation,
// comments, duplicated and moved lines, the next occurrence, find and
// replace), and highlighting read again from an edited line the same as a
// whole file read afresh (TSX and Haxe, random edits)
function tests() {
	describe("Rope", () -> {
		test("random edits: the text, its lines and UTF-8 offsets as a String's", () -> {
			var seed = 7;
			inline function rand(n:Int):Int {
				seed = (seed * 1103515245 + 12345) & 0x7fffffff;
				return n <= 0 ? 0 : seed % n;
			}
			var pieces = ["a", "bc\n", "\n", "é", "😀", "x\ny\nz", "longer line of text ", "\t{\n}\n", ""];
			var s = "";
			for (k in 0...400)
				s += pieces[rand(pieces.length)];
			var r = new Rope(s);
			for (round in 0...600) {
				var a = rand(s.length + 1), b = a + rand(Std.int(Math.min(40, s.length - a + 1)));
				// (never inside a surrogate pair)
				if (a > 0 && a < s.length && StringTools.fastCodeAt(s, a) >= 0xDC00 && StringTools.fastCodeAt(s, a) < 0xE000) a--;
				if (b > 0 && b < s.length && StringTools.fastCodeAt(s, b) >= 0xDC00 && StringTools.fastCodeAt(s, b) < 0xE000) b++;
				if (b > s.length) b = s.length;
				if (b < a) b = a;
				var t = rand(3) == 0 ? "" : pieces[rand(pieces.length)] + (rand(10) == 0 ? [for (_ in 0...300) "w"].join("") : "");
				s = s.substr(0, a) + t + s.substr(b);
				r.replace(a, b, t);
			}
			equals(r.toString(), s);
			equals(r.length, s.length);
			var lines = s.split("\n");
			equals(r.lineCount, lines.length);
			var at = 0, ok = true;
			for (l in 0...lines.length) {
				if (r.lineStart(l) != at || r.lineText(l) != lines[l] || r.lineOf(at) != l || r.lineOf(at + lines[l].length) != l) ok = false;
				at += lines[l].length + 1;
			}
			assert(ok);
			for (len in r.chunkLengths())
				assert(len <= Rope.MAX);
			var bytesOk = true;
			for (k in 0...200) {
				var p = rand(s.length + 1);
				if (p > 0 && p < s.length && StringTools.fastCodeAt(s, p) >= 0xDC00 && StringTools.fastCodeAt(s, p) < 0xE000) p++;
				var b8 = haxe.io.Bytes.ofString(s.substr(0, p)).length;
				if (r.utf8Of(p) != b8 || r.utf16Of(b8) != p) bytesOk = false;
			}
			assert(bytesOk);
			equals(r.utf8Length, haxe.io.Bytes.ofString(s).length);
			equals(r.substring(10, 1500), s.substring(10, 1500));
		});
	});

	describe("History", () -> {
		test("a run of typing undone as one, a space ending it; the selections restored", () -> {
			var m = new CodeModel("");
			for (c in "hello world".split("")) m.type(c);
			equals(m.text(), "hello world");
			assert(m.undo());
			equals(m.text(), "hello ");
			assert(m.undo());
			equals(m.text(), "");
			assert(!m.undo());
			assert(m.redo());
			assert(m.redo());
			equals(m.text(), "hello world");
			equals(m.primary.head, 11);
		});
		test("a move ends a run; a command is a step of its own", () -> {
			var m = new CodeModel("x");
			m.moveDocEnd();
			m.type("a");
			m.type("b");
			m.moveLeft();
			m.type("c");
			equals(m.text(), "xacb");
			m.undo();
			equals(m.text(), "xab");
			equals(m.primary.head, 2);
			m.duplicateLines();
			equals(m.text(), "xab\nxab");
			m.undo();
			equals(m.text(), "xab");
			m.undo();
			equals(m.text(), "x");
		});
		test("onChange: each edit's changes, a Transaction's against the text before", () -> {
			var m = new CodeModel("one two");
			var seen:Array<String> = [], before = m.text();
			m.onChange = cs -> {
				var tx = new Transaction(cs);
				before = tx.apply(before);
				seen.push(cs.join(","));
			};
			m.select(0, 3);
			m.addNextOccurrence();
			m.setSels([new Sel(0, 0), new Sel(4, 4)]);
			m.type("X");
			equals(seen, ['0-0:"X",4-4:"X"']);
			equals(before, m.text());
			m.undo();
			equals(before, "one two");
		});
	});

	describe("Multi-cursor", () -> {
		test("typing, Backspace and Delete at every caret", () -> {
			var m = new CodeModel("a\nb\nc");
			m.setSels([new Sel(1, 1), new Sel(3, 3), new Sel(5, 5)]);
			m.type("x");
			equals(m.text(), "ax\nbx\ncx");
			m.backspace();
			m.backspace();
			equals(m.text(), "\n\n");
			equals(m.sels.length, 3);
			m.type("yz");
			m.moveLineStart();
			m.deleteForward();
			equals(m.text(), "z\nz\nz");
		});
		test("cursors added above and below keep the column; Escape keeps one", () -> {
			var m = new CodeModel("abcd\nab\nabcdef");
			m.select(3, 3);
			m.addCursorVertical(1);
			m.addCursorVertical(1);
			equals([for (s in m.sels) s.head], [3, 7, 11]);
			m.type("|");
			equals(m.text(), "abc|d\nab|\nabc|def");
			assert(m.collapse());
			equals(m.sels.length, 1);
		});
		test("the next occurrence: the word, then each next one, around the end", () -> {
			var m = new CodeModel("let foo = foo + bar(foo);");
			m.select(5, 5);
			assert(m.addNextOccurrence());
			equals(m.primary.toString(), "4-7");
			assert(m.addNextOccurrence());
			assert(m.addNextOccurrence());
			assert(!m.addNextOccurrence());
			equals(m.sels.length, 3);
			m.type("baz");
			equals(m.text(), "let baz = baz + bar(baz);");
		});
		test("selections that meet are merged", () -> {
			var m = new CodeModel("abcdef");
			m.setSels([new Sel(0, 3), new Sel(2, 5), new Sel(5, 5)]);
			equals(m.sels.length, 1);
			equals(m.sels[0].toString(), "0-5");
		});
	});

	describe("Commands", () -> {
		test("brackets and quotes paired, typed over, deleted together, wrapped around a selection", () -> {
			var m = new CodeModel("");
			m.type("f");
			m.type("(");
			equals(m.text(), "f()");
			m.type("'");
			equals(m.text(), "f('')");
			m.type("'");
			m.type(")");
			equals(m.text(), "f('')");
			equals(m.primary.head, 5);
			m.moveLeft();
			m.moveLeft();
			m.backspace();
			equals(m.text(), "f()");
			m.select(0, 1);
			m.type("[");
			equals(m.text(), "[f]()");
			equals(m.primary.toString(), "1-2");
		});
		test("Enter keeps the indentation, adds one after an opening bracket, the closer on its own line", () -> {
			var m = new CodeModel("\tif (a) {}");
			m.insertSpaces = false;
			m.select(9, 9);
			m.newline();
			equals(m.text(), "\tif (a) {\n\t\t\n\t}");
			m.type("x");
			m.newline();
			equals(m.text(), "\tif (a) {\n\t\tx\n\t\t\n\t}");
			var t = new CodeModel("<view>\n  <text></text>\n</view>");
			t.tabSize = 2;
			t.select(15, 15);
			t.newline();
			equals(t.text(), "<view>\n  <text>\n    \n  </text>\n</view>");
		});
		test("Home to the first character, then the line's start; words by kind", () -> {
			var m = new CodeModel("    foo.bar(baz)");
			m.moveDocEnd();
			m.moveLineStart();
			equals(m.primary.head, 4);
			m.moveLineStart();
			equals(m.primary.head, 0);
			m.moveLineStart();
			equals(m.primary.head, 4);
			m.moveWordRight();
			equals(m.primary.head, 7);
			m.moveWordRight();
			equals(m.primary.head, 8);
			m.moveWordRight(true);
			equals(m.primary.toString(), "8-11");
			m.moveDocEnd();
			m.backspace(true);
			equals(m.text(), "    foo.bar(baz");
		});
		test("indent, outdent, comments toggled", () -> {
			var m = new CodeModel("a\n  b\n\nc");
			m.tabSize = 2;
			m.insertSpaces = true;
			m.selectAll();
			m.indent();
			equals(m.text(), "  a\n    b\n\n  c");
			m.outdent();
			m.outdent();
			equals(m.text(), "a\nb\n\nc");
			m.toggleComment();
			equals(m.text(), "// a\n// b\n\n// c");
			m.toggleComment();
			equals(m.text(), "a\nb\n\nc");
			m.select(0, 0);
			m.indent();
			equals(m.text(), "  a\nb\n\nc");
		});
		test("lines duplicated and moved, the selections with them", () -> {
			var m = new CodeModel("one\ntwo\nthree");
			m.select(5, 5);
			m.duplicateLines();
			equals(m.text(), "one\ntwo\ntwo\nthree");
			equals(m.primary.head, 9);
			assert(m.moveLinesDown());
			equals(m.text(), "one\ntwo\nthree\ntwo");
			assert(!m.moveLinesDown());
			assert(m.moveLinesUp());
			assert(m.moveLinesUp());
			assert(m.moveLinesUp());
			equals(m.text(), "two\none\ntwo\nthree");
			equals(m.primary.head, 1);
			assert(!m.moveLinesUp());
		});
		test("find (case, whole words, regular expressions) and replace all as one edit", () -> {
			var m = new CodeModel("Foo foo food\nfoo");
			equals(m.findAll("foo").length, 8);
			equals(m.findAll("foo", true).length, 6);
			equals(m.findAll("foo", false, true).length, 6);
			equals(m.findAll("fo+d", false, false, true), [8, 12]);
			assert(m.replaceMatches(m.findAll("foo", false, true), "bar"));
			equals(m.text(), "bar bar food\nbar");
			m.undo();
			equals(m.text(), "Foo foo food\nfoo");
		});
		test("copy and paste: one piece a cursor; an empty selection's line", () -> {
			var m = new CodeModel("a1\nb2\nc3");
			m.setSels([new Sel(0, 1), new Sel(3, 4), new Sel(6, 7)]);
			var t = m.copyText();
			equals(t, "a\nb\nc");
			m.moveLineEnd();
			m.insert(t);
			equals(m.text(), "a1a\nb2b\nc3c");
			m.select(0, 0);
			equals(m.copyText(), "a1a\n");
		});
		test("diagnostics placed from lines and columns, moving with edits", () -> {
			var m = new CodeModel("let a = 1;\nlet b: string = 2;\n");
			m.setDiagnostics([
				{file: "src/main.ts", line: 2, column: 5, endColumn: 6, severity: "error", message: "Type 'number' is not assignable to type 'string'."},
				{file: "other.ts", line: 1, column: 1, endColumn: 2, severity: "error", message: "elsewhere"}
			], "/p/src/main.ts");
			equals(m.diagnostics.length, 1);
			var d = m.diagnostics[0];
			equals(m.text().substring(d.start, d.end), "b");
			m.select(0, 0);
			m.type("//");
			equals(m.text().substring(d.start, d.end), "b");
			equals(m.diagnosticsAt(d.start + 1).length, 1);
		});
		test("decorations move with edits, their ends outside an insertion there", () -> {
			var m = new CodeModel("<view>\n\t<text>Hi</text>\n</view>");
			var id = m.addDecoration(8, 23);
			m.select(8, 8);
			m.type("x");
			var d = m.decorations[0];
			equals(m.text().substring(d.start, d.end), "<text>Hi</text>");
			assert(m.removeDecoration(id));
		});
	});

	describe("Highlighting", () -> {
		test("TSX and Haxe tokens by class", () -> {
			equals(classes(Tsx, 'const a = <view grow={1} title="x">{f(b)}</view>; // done'), [
				"keyword:const", "punctuation:=", "punctuation:<", "tag:view", "attribute:grow", "punctuation:={", "number:1", "punctuation:}", "attribute:title",
				"punctuation:=", 'string:"x"', "punctuation:>{", "function:f", "punctuation:(", "punctuation:)}</", "tag:view", "punctuation:>;", "comment:// done"
			]);
			equals(classes(Tsx, "if (a < b) x = /re[/]/g.test(`t${Y}`);"), [
				"keyword:if", "punctuation:(", "punctuation:<", "punctuation:)", "punctuation:=", "string:/re[/]/g", "punctuation:.", "function:test", "punctuation:(",
				"string:`t", "punctuation:${", "type:Y", "punctuation:}", "string:`", "punctuation:);"
			]);
			equals(classes(Haxe, "@:keep static function f():Int return <text>{'a$b'}</text>;"), [
				"attribute:@:keep", "keyword:static", "keyword:function", "function:f", "punctuation:():", "type:Int", "keyword:return", "punctuation:<", "tag:text",
				"punctuation:>{", "string:'a", "punctuation:$", "string:'", "punctuation:}</", "tag:text", "punctuation:>;"
			]);
		});
		test("a block comment, a template and markup over lines: each line's state", () -> {
			var m = new CodeModel("/* a\nb */ x\nconst v = <view>\n\ttext {`c\nd`}\n</view>;", new SyntaxLanguage(Tsx));
			m.highlight(100);
			equals(lineClasses(m, 1), ["comment:b */"]);
			equals(lineClasses(m, 3), ["punctuation:{", "string:`c"]);
			equals(lineClasses(m, 4), ["string:d`", "punctuation:}"]);
			equals(lineClasses(m, 5), ["punctuation:</", "tag:view", "punctuation:>;"]);
		});
		for (lang in [Tsx, Haxe])
			test('read again from each edit: the same as a whole read (${lang == Tsx ? "TSX" : "Haxe"})', () -> {
				var src = lang == Tsx ? TSX_SAMPLE : HX_SAMPLE;
				var m = new CodeModel(src, new SyntaxLanguage(lang));
				m.highlight(m.lineCount);
				var seed = 3, edits = ["/*", "*/", "`", "'", "\"", "{", "}", "<view>", "</view>", "\n", "x", "${", "//", "<", ">"];
				var readOnEdits = 0;
				for (round in 0...300) {
					seed = (seed * 1103515245 + 12345) & 0x7fffffff;
					var at = seed % (m.length + 1);
					seed = (seed * 1103515245 + 12345) & 0x7fffffff;
					var len = seed % 4;
					if (at + len > m.length) len = m.length - at;
					m.select(at, at + len);
					m.insert(edits[seed % edits.length]);
					readOnEdits += m.highlight(m.lineCount);
				}
				var fresh = new CodeModel(m.text(), new SyntaxLanguage(lang));
				fresh.highlight(fresh.lineCount);
				var same = true;
				for (l in 0...m.lineCount)
					if (m.lineTokens(l).join(",") != fresh.lineTokens(l).join(",")) {
						same = false;
						trace('line $l: ${m.line(l)}: ${m.lineTokens(l)} / ${fresh.lineTokens(l)}');
						break;
					}
				assert(same);
				// (fewer lines read than 300 whole reads)
				assert(readOnEdits < 300 * m.lineCount / 2);
			});
		test("an edit inside a line reads that line alone", () -> {
			var m = new CodeModel(TSX_SAMPLE, new SyntaxLanguage(Tsx));
			m.highlight(m.lineCount);
			m.select(m.lineStart(3) + 2, m.lineStart(3) + 2);
			m.type("q");
			equals(m.highlight(m.lineCount), 1);
			m.select(m.lineStart(2), m.lineStart(2));
			m.insert("/*");
			// (that line, and the next, whose comment was open already)
			equals(m.highlight(m.lineCount), 2);
			var ex = m.lineOf(m.text().indexOf("export"));
			m.select(m.lineStart(ex), m.lineStart(ex));
			m.insert("`");
			// (a template opened: on to the end)
			equals(m.highlight(m.lineCount), m.lineCount - ex);
			m.backspace();
			equals(m.highlight(m.lineCount), m.lineCount - ex);
			equals(m.highlight(m.lineCount), 0);
		});
	});
}

private function classes(lang:Lang, line:String):Array<String> {
	var lx = new Lexer(lang), out = [];
	lx.line(line, lx.start(), out);
	return [for (k in 0...Std.int(out.length / 3)) (out[k * 3 + 2] : TokenClass).name() + ":" + line.substring(out[k * 3], out[k * 3 + 1])];
}

private function lineClasses(m:CodeModel, l:Int):Array<String> {
	var t = m.lineTokens(l), s = m.line(l);
	return [for (k in 0...Std.int(t.length / 3)) (t[k * 3 + 2] : TokenClass).name() + ":" + s.substring(t[k * 3], t[k * 3 + 1])];
}

private final TSX_SAMPLE = "import { signal } from \"helder/view\";\n\nconst count = signal(0);\n/* a comment\n over lines */\nexport function App(props: { title: string }) {\n\tconst re = /a[/]b/g, t = `x ${count()} y`;\n\treturn (\n\t\t<view grow={1} align-items=\"center\">\n\t\t\t<text font-size={32}>{count}</text>\n\t\t\t<view:button onPress={() => count((c) => c + 1)}>+1</view:button>\n\t\t\t{props.title}\n\t\t</view>\n\t);\n}\n";

private final HX_SAMPLE = "package a;\n\n@:keep class A implements Markup {\n\tstatic var s = \"multi\nline\";\n\tfunction v() {\n\t\tvar r = ~/[<]/g;\n\t\t#if debug trace('x ${s} $s'); #end\n\t\treturn <view padding={8}>\n\t\t\t{[for (i in 0...3) <text>{'$${i} \"q\"'}</text>]}\n\t\t\t<Show when={x < 3}/>\n\t\t</view>;\n\t}\n}\n";
