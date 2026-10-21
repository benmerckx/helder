import Compiler;
import DisplayJson;
import js.Browser.document;
import js.Browser.window;
import js.Syntax;
import js.html.Element;
import js.lib.Promise;

// What the editor asks the compiler (World answers, through the worker,
// with the open files' text as it is): byte offsets into the open file
typedef Lsp = {
	complete:(offset:Int, explicit:Bool) -> Promise<Null<Dynamic>>,
	hover:(offset:Int) -> Promise<Null<Dynamic>>,
	signature:(offset:Int) -> Promise<Null<Dynamic>>,
}

// The source editor: CodeMirror 6 (editor.js, bundled by Build from
// landing/editor's pinned packages: the global CM), Haxe highlighted by its
// legacy mode, and the compiler's display requests behind it: completion
// (after a `.`, two letters, or Ctrl-Space), hover (a pointer) and, for
// touch screens without one, the info bar under the editor: the signature
// of the call the cursor is in, else the type of what it is on. The
// compiler's errors and warnings are its diagnostics. Each file keeps its
// own state (undo history, selection) while the world is open.
class Editor {
	static var CM(get, never):Dynamic;

	static inline function get_CM():Dynamic
		return js.Lib.global.CM;

	public var onChange:String->Void = _ -> {};
	public var lsp:Lsp;

	final view:Dynamic;
	final info:Element;
	final states = new Map<String, Dynamic>();
	var path:Null<String>;
	var infoTimer = -1;
	var quiet = false;

	public function new(parent:Element, info:Element) {
		this.info = info;
		view = Syntax.construct(CM.EditorView, {parent: parent, state: state("")});
		keyBar();
	}

	static function regexp(s:String):Dynamic
		return Syntax.construct(js.lib.RegExp, s);

	function extensions():Array<Dynamic> {
		var tags = CM.tags;
		var rules:Array<Dynamic> = [
			{tag: tags.keyword, color: "#c4b5fd"},
			{tag: [tags.string, tags.special(tags.string)], color: "#86efac"},
			{tag: tags.comment, color: "#6b7099", fontStyle: "italic"},
			{tag: [tags.number, tags.bool, tags.atom], color: "#fdba74"},
			{tag: [tags.typeName, tags.className], color: "#67e8f9"},
			{tag: [tags.definition(tags.variableName), Reflect.field(tags, "function")(tags.variableName)], color: "#f9a8d4"},
			{tag: tags.meta, color: "#facc15"},
			{tag: Reflect.field(tags, "operator"), color: "#a5b4fc"},
			{tag: tags.special(tags.variableName), color: "#fca5a5"},
		];
		var style = CM.HighlightStyle.define(rules);
		var theme = CM.EditorView.theme({
			"&": {height: "100%", fontSize: "13px", backgroundColor: "transparent", color: "#dbe1ff"},
			".cm-scroller": {fontFamily: "'JetBrains Mono', ui-monospace, Menlo, monospace", lineHeight: "1.6"},
			".cm-content": {caretColor: "#22d3ee", padding: "10px 0"},
			".cm-cursor, .cm-dropCursor": {borderLeftColor: "#22d3ee", borderLeftWidth: "2px"},
			"&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": {backgroundColor: "#7c3aed55 !important"},
			".cm-activeLine": {backgroundColor: "#ffffff08"},
			".cm-gutters": {backgroundColor: "transparent", color: "#4b5078", border: "none"},
			".cm-activeLineGutter": {backgroundColor: "transparent", color: "#9aa0c8"},
			".cm-completionInfo": {maxWidth: "360px", padding: "8px 10px", fontSize: "12px"},
			".cm-tooltip": {backgroundColor: "#0e1022", border: "1px solid rgba(148,163,255,.25)", borderRadius: "10px", color: "#e8eaff"},
			".cm-tooltip-autocomplete ul li[aria-selected]": {backgroundColor: "#7c3aed", color: "#fff"},
			".cm-completionDetail": {color: "#9aa0c8", fontStyle: "normal", marginLeft: "1em"},
			".cm-diagnostic": {fontFamily: "'JetBrains Mono', monospace", fontSize: "12px"},
			".cm-lintRange-error": {backgroundImage: "none", textDecoration: "underline wavy #fb7185"},
			".cm-lintRange-warning": {backgroundImage: "none", textDecoration: "underline wavy #facc15"},
		}, {dark: true});
		return [
			CM.lineNumbers(), CM.highlightActiveLineGutter(), CM.highlightSpecialChars(), CM.history(), CM.drawSelection(), CM.dropCursor(),
			CM.indentOnInput(), CM.bracketMatching(), CM.closeBrackets(), CM.highlightActiveLine(), CM.highlightSelectionMatches(),
			CM.indentUnit.of("\t"), CM.EditorState.tabSize.of(4),
			CM.StreamLanguage.define(CM.haxe), CM.syntaxHighlighting(style), theme,
			CM.autocompletion(with({activateOnTyping: true, icons: true, maxRenderedOptions: 80}, "override", [complete])),
			CM.hoverTooltip(hover, {hoverTime: 450}),
			// (tooltips on the page: the code panel's rounded corners clip)
			CM.tooltips({parent: document.body}),
			CM.lintGutter(),
			CM.keymap.of(([CM.indentWithTab] : Array<Dynamic>).concat(CM.closeBracketsKeymap).concat(CM.defaultKeymap).concat(CM.searchKeymap).concat(CM.historyKeymap).concat(CM.completionKeymap)),
			CM.EditorView.updateListener.of(update),
			CM.EditorView.lineWrapping,
		];
	}

	// o with a field whose name is a Haxe keyword
	static function with(o:Dynamic, name:String, v:Dynamic):Dynamic {
		Reflect.setField(o, name, v);
		return o;
	}

	function state(text:String):Dynamic
		return CM.EditorState.create({doc: text, extensions: extensions()});

	// a file in the editor: its own state, kept while the world is open
	public function open(path:String, text:String) {
		if (this.path != null) states.set(this.path, view.state);
		this.path = path;
		var s = states.get(path);
		quiet = true;
		view.setState(s != null && s.doc.toString() == text ? s : state(text));
		quiet = false;
		setInfo(null);
	}

	// another world: every file's state forgotten
	public function reset() {
		states.clear();
		path = null;
	}

	public function text():String
		return view.state.doc.toString();

	// the open file's text replaced (a reset), as an edit
	public function replace(text:String)
		view.dispatch({changes: {from: 0, to: view.state.doc.length, insert: text}});

	public function focus()
		view.focus();

	function update(u:Dynamic) {
		if (u.docChanged && !quiet) onChange(text());
		if (u.docChanged || u.viewportChanged || u.geometryChanged) drawMap();
		if (u.docChanged || u.selectionSet) {
			window.clearTimeout(infoTimer);
			infoTimer = window.setTimeout(infoAtCursor, 550);
		}
	}

	// the byte offset of a position (the compiler's offsets are UTF-8)
	function offset(st:Dynamic, pos:Int):Int
		return new js.html.TextEncoder().encode(st.sliceDoc(0, pos)).length;

	function complete(ctx:Dynamic):Dynamic {
		var word:Dynamic = ctx.matchBefore(regexp("\\w*"));
		var before:String = ctx.state.sliceDoc(word.from - 1, word.from);
		if (!ctx.explicit && before != "." && word.to - word.from < 2) return null;
		var at = offset(ctx.state, word.from);
		return lsp.complete(at, ctx.explicit).then((r:Dynamic) -> {
			if (r == null || r.items == null) return null;
			var seen = new Map<String, Bool>(), options = [];
			for (item in (r.items : Array<DisplayItem>)) {
				var i = DisplayJson.itemInfo(item);
				if (i.label == null || i.label == "" || seen.exists(i.label + i.kind)) continue;
				seen.set(i.label + i.kind, true);
				options.push({label: i.label, type: i.kind, detail: i.detail, info: i.doc != null && i.doc != "" ? StringTools.trim(i.doc) : null, boost: -options.length / 1000});
			}
			return {from: word.from, options: options, validFor: regexp("^\\w*$")};
		});
	}

	function hover(v:Dynamic, pos:Int, side:Int):Promise<Dynamic> {
		var st:Dynamic = v.state;
		var word:Dynamic = st.wordAt(pos);
		if (word == null) return Promise.resolve(null);
		return lsp.hover(offset(st, word.from + 1)).then(r -> {
			var h = DisplayJson.hover(r);
			if (h == null) return null;
			return {
				pos: word.from, end: word.to, above: true,
				create: () -> {
					var d = document.createDivElement();
					d.className = "cm-hover";
					var code = document.createElement("code");
					code.textContent = h.text;
					d.append(code);
					if (h.doc != null) {
						var p = document.createParagraphElement();
						p.textContent = h.doc;
						d.append(p);
					}
					return {dom: d};
				}
			};
		});
	}

	// the info bar: the call the cursor is in (its signature, the argument
	// it is at), else what it is on (its type)
	function infoAtCursor() {
		var st:Dynamic = view.state;
		var pos:Int = st.selection.main.head;
		var before:String = st.sliceDoc(Std.int(Math.max(0, pos - 600)), pos);
		var depth = 0, call = -1, i = before.length - 1;
		while (i >= 0) {
			var c = before.charAt(i);
			if (c == ")") depth++ else if (c == "(") {
				if (depth == 0) {
					call = i;
					break;
				}
				depth--;
			} else if (c == ";" || c == "{" || c == "}") break;
			i--;
		}
		if (call >= 0) {
			lsp.signature(offset(st, pos)).then(r -> {
				var s = DisplayJson.signature(r);
				if (s == null) return hoverInfo(st, pos);
				var parts = [for (k in 0...s.params.length) k == s.active ? '<b>${esc(s.params[k])}</b>' : esc(s.params[k])];
				setInfo('<span class="sig">(${parts.join(", ")}) → ${esc(s.ret)}</span>');
			});
		} else hoverInfo(st, pos);
	}

	function hoverInfo(st:Dynamic, pos:Int) {
		var word:Dynamic = st.wordAt(pos);
		if (word == null) return setInfo(null);
		lsp.hover(offset(st, word.from + 1)).then(r -> {
			var h = DisplayJson.hover(r);
			setInfo(h == null ? null : '<code>${esc(h.text)}</code>');
		});
	}

	static function esc(s:String):String
		return StringTools.htmlEscape(s);

	// (the bar keeps its height, empty or not: the editor above it never moves)
	function setInfo(html:Null<String>)
		info.innerHTML = html ?? "";

	// the compiler's messages about the open file, as diagnostics
	public function diagnostics(messages:Array<Message>) {
		var doc:Dynamic = view.state.doc;
		var list = [];
		for (m in messages) {
			if (m.file != "/lib/src/" + path || m.line < 1 || m.line > doc.lines) continue;
			var from:Int, to:Int;
			if (m.lines) {
				from = doc.line(m.from).from;
				to = doc.line(Std.int(Math.min(m.to, doc.lines))).to;
			} else {
				var l:Dynamic = doc.line(m.line);
				from = Std.int(Math.min(l.from + m.from, l.to));
				to = Std.int(Math.max(from, Math.min(l.from + m.to, l.to)));
			}
			list.push({from: from, to: to, severity: m.warning ? "warning" : "error", message: m.text});
		}
		view.dispatch(CM.setDiagnostics(view.state, list));
		errorLines = [for (m in messages) if (!m.warning && m.file == "/lib/src/" + path) m.line];
		drawMap();
	}

	// the cursor at a line (1-based) and column, in view
	public function goto(line:Int, column:Int) {
		var doc:Dynamic = view.state.doc;
		var l:Dynamic = doc.line(Std.int(Math.max(1, Math.min(line, doc.lines))));
		var at = Std.int(Math.min(l.from + column, l.to));
		view.dispatch({selection: {anchor: at}, effects: CM.EditorView.scrollIntoView(at, {y: "center"})});
		view.focus();
	}

	// touch screens: keys a phone's keyboard hides, above it while the editor has the focus
	function keyBar() {
		var bar = document.getElementById("keybar");
		for (b in bar.querySelectorAll("button")) {
			var el:Element = cast b;
			// (pointerdown: the editor keeps the focus, the keyboard stays)
			el.addEventListener("pointerdown", (e:js.html.Event) -> {
				e.preventDefault();
				var k = el.dataset.key;
				switch k {
					case "left" | "right":
						var pos:Int = view.state.selection.main.head;
						var to = Std.int(Math.max(0, Math.min(view.state.doc.length, pos + (k == "left" ? -1 : 1))));
						view.dispatch({selection: {anchor: to}, scrollIntoView: true});
					case "complete":
						CM.startCompletion(view);
					case "undo":
						CM.undo(view);
					case _:
						var text = k == "tab" ? "\t" : el.textContent;
						view.dispatch(view.state.replaceSelection(text));
				}
			});
		}
		// (the world's view follows the visual viewport while coding on a phone:
		// the keyboard shrinks it rather than the page scrolling under the caret)
		var vv:Dynamic = (cast window).visualViewport;
		if (vv != null) {
			function place() {
				var root = document.documentElement.style;
				root.setProperty("--vvh", '${vv.height}px');
				root.setProperty("--vvtop", '${vv.offsetTop}px');
				window.requestAnimationFrame(_ -> onLayout());
			}
			vv.addEventListener("resize", place);
			vv.addEventListener("scroll", place);
			place();
		}
	}

	public var onLayout:Void->Void = () -> {};

	// ---- the map: the code's lines in small, where the view is, where the errors are ----

	var map:Null<js.html.CanvasElement>;
	var errorLines:Array<Int> = [];
	var mapQueued = false;

	public function minimap(c:js.html.CanvasElement) {
		map = c;
		var held = false;
		function seek(e:js.html.PointerEvent) {
			var r = c.getBoundingClientRect();
			var f = Math.max(0, Math.min(1, (e.clientY - r.top) / r.height));
			var lines:Int = view.state.doc.lines, lineH = mapLine(r.height, lines);
			var line = lines * lineH <= r.height ? Std.int((e.clientY - r.top) / lineH) + 1 : Math.ceil(f * lines);
			var at:Int = view.state.doc.line(Std.int(Math.max(1, Math.min(lines, line)))).from;
			view.dispatch({effects: CM.EditorView.scrollIntoView(at, {y: "center"})});
		}
		c.addEventListener("pointerdown", (e:js.html.PointerEvent) -> {
			held = true;
			c.setPointerCapture(e.pointerId);
			seek(e);
		});
		c.addEventListener("pointermove", (e:js.html.PointerEvent) -> if (held) seek(e));
		c.addEventListener("pointerup", () -> held = false);
		c.addEventListener("pointercancel", () -> held = false);
		(view.scrollDOM : Element).addEventListener("scroll", drawMap, {passive: true});
		drawMap();
	}

	static function mapLine(h:Float, lines:Int):Float
		return Math.max(0.6, Math.min(3, h / Math.max(1, lines)));

	public function drawMap() {
		if (map == null || mapQueued) return;
		mapQueued = true;
		window.requestAnimationFrame(_ -> {
			mapQueued = false;
			var c = map;
			if (window.getComputedStyle(c).visibility != "visible") return;
			var dpr = Math.min(window.devicePixelRatio, 2);
			var w = c.clientWidth, h = c.clientHeight;
			if (w == 0 || h == 0) return;
			c.width = Math.round(w * dpr);
			c.height = Math.round(h * dpr);
			var g = c.getContext2d();
			g.setTransform(dpr, 0, 0, dpr, 0, 0);
			g.clearRect(0, 0, w, h);
			var doc:Dynamic = view.state.doc;
			var lines:Int = doc.lines;
			var lineH = mapLine(h, lines);
			// (more lines than fit: the map is the whole file, squeezed)
			var squeeze = lines * lineH > h ? h / (lines * lineH) : 1.0;
			var cw = (w - 8) / 90;
			for (i in 1...lines + 1) {
				var text:String = doc.line(i).text;
				var trimmed = StringTools.trim(text);
				if (trimmed == "") continue;
				var indent = 0;
				for (k in 0...text.length) {
					var ch = text.charAt(k);
					if (ch == "\t") indent += 4 else if (ch == " ") indent++ else break;
				}
				g.fillStyle = errorLines.contains(i) ? "#fb7185"
					: StringTools.startsWith(trimmed, "//") || StringTools.startsWith(trimmed, "*") || StringTools.startsWith(trimmed, "/*") ? "#4b5078"
					: ~/\b(class|function|typedef|enum|interface|abstract)\b/.match(trimmed) ? "#f9a8d4"
					: StringTools.startsWith(trimmed, "import") ? "#67e8f9" : "#a9b0dd";
				var y = (i - 1) * lineH * squeeze;
				g.fillRect(4 + indent * cw, y, Math.max(cw, Math.min(trimmed.length, 90 - indent) * cw), Math.max(0.6, lineH * squeeze - (lineH > 1.5 ? 0.8 : 0)));
			}
			// the view: what of the file the editor shows
			var sd:Element = view.scrollDOM;
			var total = lines * lineH * squeeze;
			var top = sd.scrollHeight > 0 ? sd.scrollTop / sd.scrollHeight * total : 0;
			var size = sd.scrollHeight > 0 ? Math.max(6, sd.clientHeight / sd.scrollHeight * total) : total;
			g.fillStyle = "rgba(34, 211, 238, 0.14)";
			g.fillRect(0, top, w, size);
			g.strokeStyle = "rgba(34, 211, 238, 0.6)";
			g.lineWidth = 1;
			g.strokeRect(0.5, top + 0.5, w - 1, size - 1);
		});
	}
}
