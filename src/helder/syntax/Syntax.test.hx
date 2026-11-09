package helder.syntax;

import helder.syntax.Document;
import helder.syntax.Edits;
import helder.syntax.Scanner;
import helder.syntax.Transaction;
import helder.test.Test;

// helder.syntax's edits (the test lane: natively, as wasm32-wasi and on
// Eval): each on TSX and Haxe markup, the text after it exactly, its
// inverse giving the text back byte for byte; reading and printing back;
// the time a read and an edit take on a file of 2000 lines
@:test.interp
function tests() {
	describe("reading", () -> {
		test("printed back byte for byte: markup, comments, strings, regular expressions, templates", () -> {
			var tsx = 'const a = <view grow={1} /* c */ title="x">\n\t{items.map((i) => <text>{`$${i} ok`}</text>)}\n</view>;\nconst r = /[<{]/g, d = a / 2 < 3;\n';
			var doc = Document.parse(tsx, Tsx);
			equals(doc.structured, true);
			equals(doc.print(), tsx);
			equals([for (e in doc.elements()) e.name], ["view", "text"]);
			var hx = 'class A implements Markup {\n\tfunction v() return <view padding={8}>{[for (i in 0...3) <text>{\'$${i} "q"\'}</text>]}<Show when={x < 3}/></view>;\n\tvar r = ~/[<]/g;\n}\n';
			var h = Document.parse(hx, Haxe);
			equals(h.print(), hx);
			equals([for (e in h.elements()) e.name], ["view", "text", "Show"]);
		});
		test("a design file: markup alone, from its start", () -> {
			var text = '<Design>\n\t<Frame name="Home" width={390} canvas:at="0 0">\n\t\t<text color="#111">It\'s {"here"}</text>\n\t</Frame>\n</Design>\n';
			var doc = Document.parse(text, Lang.of("app.helder"));
			equals(doc.structured, true);
			equals(doc.print(), text);
			equals([for (e in doc.elements()) e.name], ["Design", "Frame", "text"]);
			edit(text, Markup, d -> Edits.setAttribute(d, d.elementsNamed("text")[0], "color", AString("#ef4444")), StringTools.replace(text, "#111", "#ef4444"));
		});
		test("a comparison, a generic, a generic arrow read as code", () -> {
			var doc = Document.parse("const f = <T,>(x: T) => x; if (a <b) g<string>(c);\n", Tsx);
			equals(doc.elements().length, 0);
			equals(doc.print(), "const f = <T,>(x: T) => x; if (a <b) g<string>(c);\n");
		});
		test("brackets that do not balance: flat, not edited", () -> {
			var doc = Document.parse("#if a\nfunction f() {\n#else\nfunction f() {\n#end\n}\n", Haxe);
			equals(doc.structured, false);
			equals(doc.print(), "#if a\nfunction f() {\n#else\nfunction f() {\n#end\n}\n");
			var failed = try {
				Edits.setLiteral(doc, 0, 1);
				false;
			} catch (e:SourceError) true;
			assert(failed);
		});
		test("offsets as UTF-8 bytes (helder.view.Source's) and back", () -> {
			var doc = Document.parse('const s = "é😀";\nconst v = <view/>;\n', Tsx);
			var el = doc.elementsNamed("view")[0];
			equals(doc.toByte(el.start), haxe.io.Bytes.ofString(doc.text.substr(0, el.start)).length);
			equals(doc.toByte(el.start), 'const s = "'.length + 2 + 4 + '";\nconst v = '.length);
			equals(doc.fromByte(doc.toByte(el.start)), el.start);
			equals(doc.elementAtByte(doc.toByte(el.start)).name, "view");
		});
	});

	describe("attributes", () -> {
		test("a value set, the rest as it was", () -> {
			edit('<view padding={8} color="#fff">\n\t<text>Hi</text>\n</view>', Tsx, d -> Edits.setAttribute(d, d.elementsNamed("view")[0], "padding", ACode("16")),
				'<view padding={16} color="#fff">\n\t<text>Hi</text>\n</view>');
			edit('<view padding={8} color="#fff"/>', Haxe, d -> Edits.setAttribute(d, d.elementsNamed("view")[0], "color", AString("#000")),
				'<view padding={8} color="#000"/>');
		});
		test("one added after the last, on a line of its own when they are", () -> {
			edit('<view padding={8}>x</view>', Tsx, d -> Edits.setAttribute(d, d.elementsNamed("view")[0], "grow", ACode("1")), '<view padding={8} grow={1}>x</view>');
			edit('<field\n\t\ttag="draft"\n\t\tgrow={1}\n\t/>', Haxe, d -> Edits.setAttribute(d, d.elementsNamed("field")[0], "label", AString("Draft")),
				'<field\n\t\ttag="draft"\n\t\tgrow={1}\n\t\tlabel="Draft"\n\t/>');
			edit('<view/>', Tsx, d -> Edits.setAttribute(d, d.elementsNamed("view")[0], "disabled", AFlag), '<view disabled/>');
		});
		test("one removed, with the space before it", () -> {
			edit('<view padding={8} color="#fff" grow={1}/>', Tsx, d -> Edits.removeAttribute(d, d.elementsNamed("view")[0], "color"), '<view padding={8} grow={1}/>');
			edit('<field\n\ttag="draft"\n\tgrow={1}\n/>', Haxe, d -> Edits.removeAttribute(d, d.elementsNamed("field")[0], "grow"), '<field\n\ttag="draft"\n/>');
		});
		test("a string with a quote written as code", () -> {
			edit('<text title="a"/>', Tsx, d -> Edits.setAttribute(d, d.elementsNamed("text")[0], "title", AString('say "hi"')), '<text title={"say \\"hi\\""}/>');
		});
	});

	describe("elements", () -> {
		var list = 'return <view>\n\t\t<text>One</text>\n\t\t<text>Two</text>\n\t</view>;';
		test("a child inserted among its siblings, indented as they are", () -> {
			edit(list, Tsx, d -> Edits.insertChild(d, d.elementsNamed("view")[0], 1, '<text>New</text>'),
				'return <view>\n\t\t<text>One</text>\n\t\t<text>New</text>\n\t\t<text>Two</text>\n\t</view>;');
			edit(list, Haxe, d -> Edits.insertChild(d, d.elementsNamed("view")[0], 2, '<text>Last</text>'),
				'return <view>\n\t\t<text>One</text>\n\t\t<text>Two</text>\n\t\t<text>Last</text>\n\t</view>;');
			edit('<view><text>a</text></view>', Tsx, d -> Edits.insertChild(d, d.elementsNamed("view")[0], 0, '<text>b</text>'), '<view><text>b</text><text>a</text></view>');
		});
		test("into a self-closing element: opened, the child on a line of its own", () -> {
			edit('\tconst a = <view grow={1} />;', Tsx, d -> Edits.insertChild(d, d.elementsNamed("view")[0], 0, '<text>x</text>'),
				'\tconst a = <view grow={1}>\n\t\t<text>x</text>\n\t</view>;');
		});
		test("deleted, with its line", () -> {
			edit(list, Haxe, d -> Edits.delete(d, d.elementsNamed("text")[0]), 'return <view>\n\t\t<text>Two</text>\n\t</view>;');
			edit('<view><text>a</text><text>b</text></view>', Tsx, d -> Edits.delete(d, d.elementsNamed("text")[1]), '<view><text>a</text></view>');
		});
		test("moved: before a sibling, to the end, into another element", () -> {
			edit(list, Tsx, d -> Edits.move(d, d.elementsNamed("text")[1], d.elementsNamed("view")[0], 0),
				'return <view>\n\t\t<text>Two</text>\n\t\t<text>One</text>\n\t</view>;');
			edit(list, Haxe, d -> Edits.move(d, d.elementsNamed("text")[0], d.elementsNamed("view")[0], 2),
				'return <view>\n\t\t<text>Two</text>\n\t\t<text>One</text>\n\t</view>;');
			var two = 'return <view>\n\t<view tag="a">\n\t\t<text>x</text>\n\t</view>\n\t<view tag="b">\n\t\t<view>\n\t\t\t<text>y</text>\n\t\t</view>\n\t</view>\n</view>;';
			edit(two, Tsx, d -> Edits.move(d, d.elementsNamed("text")[0], d.elementWith("tag", "b").elements()[0], 1),
				'return <view>\n\t<view tag="a">\n\t</view>\n\t<view tag="b">\n\t\t<view>\n\t\t\t<text>y</text>\n\t\t\t<text>x</text>\n\t\t</view>\n\t</view>\n</view>;');
		});
		test("wrapped and unwrapped, the lines between indented a step", () -> {
			var one = 'return <view>\n\t<text grow={1}>\n\t\tHi\n\t</text>\n</view>;';
			var wrapped = 'return <view>\n\t<Show when={on}>\n\t\t<text grow={1}>\n\t\t\tHi\n\t\t</text>\n\t</Show>\n</view>;';
			edit(one, Tsx, d -> Edits.wrap(d, d.elementsNamed("text")[0], "Show", [{name: "when", value: ACode("on")}]), wrapped);
			edit(wrapped, Haxe, d -> Edits.unwrap(d, d.elementsNamed("Show")[0]), one);
			edit('<view><b>x</b></view>', Tsx, d -> Edits.wrap(d, d.elementsNamed("b")[0], "i"), '<view><i><b>x</b></i></view>');
			edit('<view><i><b>x</b></i></view>', Haxe, d -> Edits.unwrap(d, d.elementsNamed("i")[0]), '<view><b>x</b></view>');
		});
		test("a component renamed, both its tags", () -> {
			edit('<Card title="a">\n\t<text>x</text>\n</Card>', Tsx, d -> Edits.rename(d, d.elementsNamed("Card")[0], "Panel"), '<Panel title="a">\n\t<text>x</text>\n</Panel>');
			edit('<Card title="a"/>', Haxe, d -> Edits.rename(d, d.elementsNamed("Card")[0], "ui.Panel"), '<ui.Panel title="a"/>');
		});
		test("a component renamed in its file: its function, its elements, its calls; not another's field", () -> {
			edit('function Card(p) {\n\treturn <view/>;\n}\nconst a = <Card><Card/></Card>, b = Card({}), c = ui.Card;\n', Tsx, d -> Edits.renameComponent(d, "Card", "Panel"),
				'function Panel(p) {\n\treturn <view/>;\n}\nconst a = <Panel><Panel/></Panel>, b = Panel({}), c = ui.Card;\n');
		});
		test("spaces: the file's own step", () -> {
			edit('<view>\n  <text>a</text>\n</view>', Tsx, d -> Edits.wrap(d, d.elementsNamed("text")[0], "Show"), '<view>\n  <Show>\n    <text>a</text>\n  </Show>\n</view>');
		});
	});

	describe("code", () -> {
		test("a literal changed: a number in a hole, a string in its quotes, a sign", () -> {
			edit('<view padding={24}/>', Tsx, d -> Edits.setLiteral(d, d.elementsNamed("view")[0].attr("padding").literal().start, 32), '<view padding={32}/>');
			edit("const t = 'a';", Ts, d -> Edits.setLiteral(d, 10, "it's"), "const t = 'it\\'s';");
			edit("var x = -3;", Haxe, d -> Edits.setLiteral(d, 9, 4.5), "var x = 4.5;");
			edit("var x = 1 - 3;", Haxe, d -> Edits.setLiteral(d, 12, 4), "var x = 1 - 4;");
			edit("var x = 'a$$b';", Haxe, d -> Edits.setLiteral(d, 8, "c$d"), "var x = 'c$$d';");
		});
		var story = 'final fleet = story({\n\tname: "Store/fleet",\n\tcaption: "Command a fleet",\n\tseed: 7,\n});\n';
		test("a definition's field set, added, removed (a story's caption)", () -> {
			edit(story, Haxe, d -> Edits.setField(d, d.definition("story", "fleet"), "caption", '"Rule the stars"'),
				'final fleet = story({\n\tname: "Store/fleet",\n\tcaption: "Rule the stars",\n\tseed: 7,\n});\n');
			edit(story, Haxe, d -> Edits.setField(d, d.definition("story"), "store", "true"),
				'final fleet = story({\n\tname: "Store/fleet",\n\tcaption: "Command a fleet",\n\tseed: 7,\n\tstore: true,\n});\n');
			edit(story, Haxe, d -> Edits.removeField(d, d.definition("story"), "caption"), 'final fleet = story({\n\tname: "Store/fleet",\n\tseed: 7,\n});\n');
			var line = 'export const plain = story({name: "Card/plain", render: (c) => card(c)});';
			edit(line, Tsx, d -> Edits.setField(d, d.definition("story", "plain"), "seed", "3"), 'export const plain = story({name: "Card/plain", render: (c) => card(c), seed: 3});');
			edit(line, Tsx, d -> Edits.removeField(d, d.definition("story", "plain"), "render"), 'export const plain = story({name: "Card/plain"});');
			edit(line, Tsx, d -> Edits.removeField(d, d.definition("story", "plain"), "name"), 'export const plain = story({render: (c) => card(c)});');
		});
		test("a shader's field, nested: its uniform's default", () -> {
			var sh = 'export const glow = shader({\n  uniforms: {\n    strength: 0.5,\n  },\n  fragment: (i) => vec4(1),\n});\n';
			edit(sh, Ts, d -> Edits.setField(d, d.definition("shader", "glow").field("uniforms").object(), "strength", "0.8"),
				'export const glow = shader({\n  uniforms: {\n    strength: 0.8,\n  },\n  fragment: (i) => vec4(1),\n});\n');
		});
	});

	describe("transactions", () -> {
		test("offsets mapped through one", () -> {
			var t = new Transaction([new Change(2, 4, "xyz"), new Change(6, 6, "!")], null, "abcdefgh");
			equals(t.apply("abcdefgh"), "abxyzef!gh");
			equals([for (p in [0, 2, 4, 5, 6, 8]) t.map(p)], [0, 2, 5, 6, 7, 10]);
			equals(t.inverse.apply("abxyzef!gh"), "abcdefgh");
		});
		test("overlapping changes refused", () -> {
			var failed = try {
				new Transaction([new Change(1, 4, ""), new Change(3, 5, "")]);
				false;
			} catch (e:SourceError) true;
			assert(failed);
		});
		test("two in a row as one, its inverse the text back", () -> {
			var d = Document.parse('<view a="1"><text/></view>', Tsx);
			var t1 = Edits.setAttribute(d, d.elementsNamed("view")[0], "a", AString("2"));
			var d2 = d.apply(t1);
			var t2 = Edits.rename(d2, d2.elementsNamed("text")[0], "b");
			var both = t1.then(t2, d.text);
			equals(both.apply(d.text), '<view a="2"><b/></view>');
			equals(both.inverse.apply(both.apply(d.text)), d.text);
		});
	});

	describe("speed", () -> {
		test("a file of 2000 lines read, edited and read again in a few ms", () -> {
			var b = new StringBuf();
			b.add("export function App() {\n\treturn <view grow={1} padding={24}>\n");
			for (k in 0...666)
				b.add('\t\t<view tag="row$k" direction="row" column-gap={8}>\n\t\t\t<text font-size={14} color="#18181b">{items[$k].title} {`#$${$k}`}</text>\n\t\t</view>\n');
			b.add("\t</view>;\n}\n");
			var text = b.toString();
			assert(text.split("\n").length >= 2000);
			// (three times: the first cold, the best as an editor's warm loop has it)
			var best = {read: 1e9, edit: 1e9, all: 1e9}, first = 0.0;
			for (run in 0...3) {
				var t0 = haxe.Timer.stamp();
				var d = Document.parse(text, Tsx);
				var t1 = haxe.Timer.stamp();
				var el = d.elementWith("tag", "row333");
				var tx = Edits.setAttribute(d, el, "column-gap", ACode("12"));
				var t2 = haxe.Timer.stamp();
				var after = d.apply(tx);
				var t3 = haxe.Timer.stamp();
				equals(after.elements().length, d.elements().length);
				if (run == 0) first = (t3 - t0) * 1000;
				best = {read: Math.min(best.read, (t1 - t0) * 1000), edit: Math.min(best.edit, (t2 - t1) * 1000), all: Math.min(best.all, (t3 - t0) * 1000)};
			}
			// (natively a few ms; Eval and wasm slower: a bound for all)
			assert(best.all < 1000, 'read, edited and read again in ${best.all} ms');
			inline function ms(x:Float)
				return Math.round(x * 10) / 10;
			Sys.println('helder.syntax: 2000 lines read ${ms(best.read)} ms, an element found and edited ${ms(best.edit)} ms, read, edited and read again ${ms(best.all)} ms (the first time ${ms(first)} ms)');
		});
	});
}

// the edit of text by f: the text after exactly, its inverse the text back, only the changes' ranges different
private function edit(text:String, lang:Lang, f:Document->Transaction, expected:String, ?pos:haxe.PosInfos) {
	var doc = Document.parse(text, lang);
	equals(doc.print(), text, null, pos);
	var tx = f(doc);
	var after = tx.apply(text);
	equals(after, expected, null, pos);
	equals(tx.inverse.apply(after), text, null, pos);
	// (the edited text reads again)
	equals(Document.parse(after, lang).structured, true, null, pos);
}
