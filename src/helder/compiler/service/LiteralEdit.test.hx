package helder.compiler.service;

import helder.markup.Live;
import helder.test.Test;

// live literals' compile-time half (helder.markup.Live) and helder dev's
// comparison of a save with the built source (LiteralEdit): only the
// tables' spans changed, each still a literal of its form, else a build
function tests() {
	var src = '<view padding={24} background="#fafafa">\n\t<text color="#3b82f6" font-size={28}>todos</text>\n</view>';
	function span(text:String, ?from = 0):{start:Int, end:Int} {
		var i = src.indexOf(text, from);
		return {start: i, end: i + text.length};
	}
	var entries:Array<helder.markup.Live.Entry> = [
		{id: "a", start: span("24").start, end: span("24").end, form: "number"},
		{id: "b", start: span('"#fafafa"').start, end: span('"#fafafa"').end, form: "quoted"},
		{id: "c", start: span('"#3b82f6"').start, end: span('"#3b82f6"').end, form: "quoted"},
		{id: "d", start: span("28").start, end: span("28").end, form: "number"},
		{id: "e", start: span("todos").start, end: span("todos").end, form: "text"},
	];
	test("a string's kind: a colour, a length, else a string", () -> {
		equals(Live.stringKind("#3b82f6"), "color");
		equals(Live.stringKind("rgba(0, 0, 0, 0.5)"), "color");
		equals(Live.stringKind("4 6"), "length");
		equals(Live.stringKind("50%"), "length");
		equals(Live.stringKind("todos"), "string");
	});
	test("an id: the file, line, byte column and kind", () -> {
		equals(Live.id("/a/Todo.hx", src, span('"#3b82f6"').start, "color"), "/a/Todo.hx:2:14:color");
	});
	test("an anchor: the line with the literals' values left out", () -> {
		var s = span('"#3b82f6"');
		equals(Live.anchor(src, s.start, s.end), "<text color=\x01 font-size={_}>todos</text>");
		var moved = '<view>\n\t<text color="#ef4444" font-size={30}>todos</text>\n</view>';
		var m = moved.indexOf('"#ef4444"');
		equals(Live.anchor(moved, m, m + 9), Live.anchor(src, s.start, s.end));
	});
	test("unchanged: no patches", () -> {
		equals(patches(src, src, entries).length, 0);
	});
	test("a colour and a number changed, longer and shorter: their new sources, by the built ids", () -> {
		var now = StringTools.replace(StringTools.replace(src, '"#3b82f6"', '"#ef4444ff"'), "{24}", "{8}");
		var d = patches(src, now, entries);
		equals(d.length, 2);
		equals(d[0].id, "a");
		equals(d[0].source, "8");
		equals(d[1].id, "c");
		equals(d[1].source, '"#ef4444ff"');
	});
	test("a text changed, a hexadecimal and an escape", () -> {
		var d = patches(src, StringTools.replace(src, ">todos<", ">all done<"), entries);
		equals(d.length, 1);
		equals(d[0].source, "all done");
		var hex = "Color.rgb(0x18181B)";
		equals(patches(hex, "Color.rgb(0x3b82f6)", [{id: "h", start: 10, end: 18, form: "number"}])[0].source, "0x3b82f6");
		var q = 'label="a"';
		equals(patches(q, 'label="say \\"hi\\""', [{id: "q", start: 6, end: 9, form: "quoted"}])[0].source, '"say \\"hi\\""');
	});
	test("anything else: a build, its line said", () -> {
		var why = null;
		assert(LiteralEdit.diff(src, StringTools.replace(src, "font-size", "font-weight"), entries, w -> why = w) == null);
		equals(why, "line 2: not a live literal's value");
		// (a literal made an expression, a text emptied, a quote changed)
		assert(LiteralEdit.diff(src, StringTools.replace(src, "{28}", "{28 + 1}"), entries) == null);
		assert(LiteralEdit.diff(src, StringTools.replace(src, ">todos<", "><"), entries) == null);
		assert(LiteralEdit.diff(src, StringTools.replace(src, '"#fafafa"', "'#fafafa'"), entries) == null);
		assert(LiteralEdit.diff(src, src + "\n", entries) == null);
	});
	test("diagnostics: the pretty format and the classic one as data", () -> {
		var d = Diagnostic.Diagnostics.parse("[ERROR] app/Todo.hx:12: characters 5-9\n\n 12 | var x:Int = \"a\";\n    |     ^^^^\n    | String should be Int\n\nsrc/a.ts:3: characters 1-4 : Warning : unused");
		equals(d.length, 2);
		equals(d[0].file, "app/Todo.hx");
		equals(d[0].line, 12);
		equals(d[0].column, 5);
		equals(d[0].endColumn, 9);
		equals(d[0].severity, "error");
		equals(d[0].message, "String should be Int");
		equals(d[1].severity, "warning");
		equals(d[1].message, "unused");
	});
}

// (the patches of a save that needs no build)
function patches(built:String, now:String, entries:Array<helder.markup.Live.Entry>):Array<{id:String, source:String}> {
	var d = LiteralEdit.diff(built, now, entries);
	if (d == null) throw "a build, not patches";
	return d;
}
