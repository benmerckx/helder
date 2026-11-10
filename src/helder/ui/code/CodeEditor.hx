package helder.ui.code;

import helder.syntax.Transaction;
import helder.ui.code.CodeAction;
import helder.ui.code.CodeLanguage;
import helder.ui.code.CodeModel;
import helder.ui.widgets.TextField;

// A code editor (helder.ui.code; helder.ui's README): a CodeView of a CodeModel,
// with its find and replace panel (secondary-F, secondary-H: the matches
// as you type, case, whole words and regular expressions, the next and
// previous, one replaced or all) and its go to line panel (secondary-G),
// over the text's top right. The studio's hooks: revealRange,
// setSelection, decorations (ranges drawn another way: "selected on the
// canvas"), diagnostics (helder.compiler.service's), and onChange with
// each edit's changes (helder.syntax's Change: a Transaction's). complete
// gives suggestions at the caret (CodeCompletion): asked as a word is
// typed and on Control+Space, shown under the word, Up and Down to choose,
// Enter or Tab to put one in, Escape (or moving away) to close them.
//
//   var editor = new CodeEditor(File.getContent(path), path);
//   editor.onChange = changes -> doc = doc.apply(new Transaction(changes));
//   editor.setDiagnostics(service.check(words, cwd).diagnostics, path);
//   editor.addDecoration(el.start, el.end, Color.rgba(0x3b82f6, 0.12));
class CodeEditor extends Node {
	public final view:CodeView;
	public final model:CodeModel;
	// each edit's changes (against the text before, in order: new Transaction(changes))
	public var onChange:Null<Array<Change>->Void> = null;
	// suggestions for the text at caret (null: none), the word they replace from where they say
	public var complete:Null<(text:String, caret:Int) -> Null<CodeCompletion.Completions>> = null;
	public final completion:CodeCompletion;
	var completeFrom = -1;
	var accepting = false;
	// the file's path: its language by its extension (CodeLanguages)
	public var path(default, set):Null<String> = null;

	// find's state
	public var findOpen(default, null) = false;
	public var replaceOpen(default, null) = false;
	public var query(default, null) = "";
	public var caseSensitive(default, null) = false;
	public var wholeWord(default, null) = false;
	public var regex(default, null) = false;

	final findPanel:Node;
	final findField:TextField;
	final replaceRow:Node;
	final replaceField:TextField;
	final count:TextNode;
	final toggles:Array<Node> = [];
	final gotoPanel:Node;
	final gotoField:TextField;
	public var gotoOpen(default, null) = false;
	var matchesOf = -1;

	public function new(text = "", ?path:String) {
		super("code-editor");
		model = new CodeModel(text);
		view = new CodeView(model);
		style.grow = 1;
		style.minHeight = 0;
		style.minWidth = 0;
		style.overflow = Hidden;
		append(view);
		model.onChange = changes -> {
			if (findOpen) refreshMatches();
			if (onChange != null) onChange(changes);
			if (completion.open && !accepting) suggest(false);
		};
		completion = new CodeCompletion(this);
		completion.onPick = _ -> accept();
		append(completion);
		var typed = view.onTextInput, keys = view.onKeyDown, press = view.onPointerDown, blur = view.onBlur;
		view.onTextInput = e -> {
			typed(e);
			if (e.text != "" && complete != null) suggest(false);
		};
		view.onKeyDown = e -> {
			if (completionKey(e)) {
				e.preventDefault();
				e.stop();
				return;
			}
			keys(e);
		};
		view.onPointerDown = e -> {
			completion.hide();
			press(e);
		};
		view.onBlur = e -> {
			completion.hide();
			blur(e);
		};
		this.path = path;
		on(CodeAction, act);

		findField = field("find", "Find", 180);
		replaceField = field("replace", "Replace", 180);
		count = new TextNode("", "find-count");
		count.style.fontSize = 12;
		count.style.minWidth = 64;
		count.style.alignSelf = Center;
		findField.onChange = t -> {
			query = t;
			refreshMatches();
			selectMatch(model.primary.from, 1);
		};
		findField.onSubmit = _ -> findNext(ui != null && ui.mods & Key.MOD_SHIFT != 0 ? -1 : 1);
		replaceField.onSubmit = _ -> replaceOne();
		var top = row("find-row", [findField, count]);
		var names = [["Aa", "Match case"], ["W", "Whole word"], [".*", "Regular expression"]];
		for (k in 0...names.length) {
			var b = button(names[k][0], names[k][1], () -> toggle(k));
			b.semantics.checked = false;
			toggles.push(b);
			top.append(b);
		}
		top.append(button("↑", "Previous match", () -> findNext(-1)));
		top.append(button("↓", "Next match", () -> findNext(1)));
		top.append(button("×", "Close", closePanels));
		replaceRow = row("replace-row", [replaceField, button("Replace", "Replace", replaceOne), button("All", "Replace all", replaceAll)]);
		findPanel = panel("code-find", "Find");
		findPanel.append(top);

		gotoField = field("goto", "Line (or line:column)", 200);
		gotoField.onSubmit = t -> {
			goToSpec(t);
			closePanels();
		};
		gotoPanel = panel("code-goto", "Go to line");
		gotoPanel.append(gotoField);
	}

	// ---- suggestions

	// asked for the caret's word (force: also before a word starts, Control+Space)
	public function suggest(force:Bool) {
		var caret = model.primary.head;
		var r = complete == null || !model.primary.empty() ? null : complete(text, caret);
		if (r == null || r.items.length == 0 || !force && r.from == caret && !completion.open && !afterDot(caret)) {
			completion.hide();
			return;
		}
		completeFrom = r.from;
		var p = view.pointOf(r.from);
		completion.show(r.items, view.x + p.x - 8, view.y + p.y + view.lineHeight + 2);
	}

	inline function afterDot(caret:Int):Bool
		return caret > 0 && StringTools.fastCodeAt(text, caret - 1) == ".".code;

	// the chosen suggestion put in place of its word
	public function accept() {
		var it = completion.items[completion.chosen];
		completion.hide();
		if (it == null) return;
		accepting = true;
		model.select(completeFrom, model.primary.head);
		model.insert(it.insert ?? it.label, CodeModel.TYPE);
		accepting = false;
		view.changed();
	}

	// (a key while suggestions show: theirs, or they close)
	function completionKey(e:Event):Bool {
		var ctrl = e.mods & (Key.MOD_CONTROL | Key.MOD_META) != 0;
		if (e.key == Key.SPACE && e.mods & Key.MOD_CONTROL != 0 && complete != null) {
			suggest(true);
			return true;
		}
		if (!completion.open) return false;
		switch e.key {
			case Key.DOWN if (!ctrl):
				completion.move(1);
			case Key.UP if (!ctrl):
				completion.move(-1);
			case Key.ENTER | Key.TAB:
				accept();
			case Key.ESCAPE:
				completion.hide();
			case Key.LEFT | Key.RIGHT | Key.HOME | Key.END | Key.PAGE_UP | Key.PAGE_DOWN:
				completion.hide();
				return false;
			case _:
				return false;
		}
		return true;
	}

	function set_path(p:Null<String>):Null<String> {
		path = p;
		model.language = p == null ? null : CodeLanguages.forPath(p);
		return p;
	}

	// the text (setting it: a new document, its history cleared)
	public var text(get, set):String;

	function get_text():String
		return model.text();

	function set_text(t:String):String {
		model.setText(t);
		view.changed(false);
		if (findOpen) refreshMatches();
		return t;
	}

	// ---- the studio's hooks

	// the range brought into view (centred), selected when asked
	public function revealRange(start:Int, end:Int, select = false) {
		if (select) model.select(start, end);
		view.revealRange(start, end, true);
		view.changed(false);
	}

	// one selection, anchor to head (the caret)
	public function setSelection(anchor:Int, head:Int) {
		model.select(anchor, head);
		view.changed();
	}

	// several selections ([anchor, head, anchor, head...]; the last the primary)
	public function setSelections(pairs:Array<Int>) {
		var list = [];
		var k = 0;
		while (k + 1 < pairs.length) {
			list.push(new Sel(pairs[k], pairs[k + 1]));
			k += 2;
		}
		model.setSels(list);
		view.changed();
	}

	// a range drawn another way: its background, border, underline; the whole lines it covers or its characters; its id
	public function addDecoration(start:Int, end:Int, ?background:Color, ?border:Color, ?underline:Color, wholeLine = false):Int {
		var id = model.addDecoration(start, end, background, border, underline, wholeLine);
		view.changed(false);
		return id;
	}

	public function removeDecoration(id:Int):Bool {
		var r = model.removeDecoration(id);
		view.changed(false);
		return r;
	}

	public function clearDecorations() {
		model.clearDecorations();
		view.changed(false);
	}

	// a compiler's diagnostics (Service.check's) of this file (file: its path; others left out)
	public function setDiagnostics(list:Array<helder.compiler.service.Diagnostic>, ?file:String) {
		model.setDiagnostics(list, file ?? path);
		view.changed(false);
	}

	// "Ln 12, Col 5", the selections' count when more than one
	public function status():String {
		var p = model.primary, l = model.lineOf(p.head);
		var s = 'Ln ${l + 1}, Col ${p.head - model.lineStart(l) + 1}';
		if (model.sels.length > 1) s += ' (${model.sels.length} selections)';
		else if (!p.empty()) s += ' (${p.to - p.from} selected)';
		return s;
	}

	// ---- actions

	function act(a:CodeAction):Bool {
		switch a {
			case Find:
				openFind(false);
			case Replace:
				openFind(true);
			case FindNext:
				if (!findOpen) openFind(false) else findNext(1);
			case FindPrevious:
				if (!findOpen) openFind(false) else findNext(-1);
			case ReplaceOne:
				replaceOne();
			case ReplaceAll:
				replaceAll();
			case GoToLine:
				openGoto();
			case ClosePanel:
				if (!findOpen && !gotoOpen) return false;
				closePanels();
			case Cancel if (findOpen || gotoOpen):
				if (!view.run(Cancel)) closePanels();
			case _:
				return view.run(a);
		}
		return true;
	}

	// ---- find and replace

	// the find panel shown (with replace), its query the selection's when on one line, the field focused
	public function openFind(withReplace:Bool) {
		closeGoto();
		var p = model.primary;
		if (!p.empty() && model.lineOf(p.from) == model.lineOf(p.to)) {
			query = model.rope.substring(p.from, p.to);
			findField.setText(query);
		}
		if (!findOpen) {
			findOpen = true;
			themePanel(findPanel);
			append(findPanel);
		}
		if (withReplace != replaceOpen) {
			replaceOpen = withReplace;
			if (withReplace) findPanel.append(replaceRow) else findPanel.remove(replaceRow);
		}
		refreshMatches();
		(withReplace && query != "" ? replaceField : findField).focus();
		findField.selectAll();
	}

	public function closePanels() {
		if (findOpen) {
			findOpen = false;
			remove(findPanel);
			view.matches = [];
			view.currentMatch = -1;
		}
		closeGoto();
		view.focus();
		view.changed(false);
	}

	function closeGoto() {
		if (!gotoOpen) return;
		gotoOpen = false;
		remove(gotoPanel);
	}

	// the matches found again (the query, its options, the text now)
	public function refreshMatches() {
		view.matches = findOpen ? model.findAll(query, caseSensitive, wholeWord, regex) : [];
		matchesOf = model.version;
		updateCount();
		view.changed(false);
	}

	function updateCount() {
		var n = view.matches.length >> 1, k = view.currentMatch;
		count.text = query == "" ? "" : n == 0 ? "No results" : (k >= 0 ? '${k + 1} of $n' : '$n found');
	}

	// the match at or after (dir < 0: before) pos selected and brought into view
	function selectMatch(pos:Int, dir:Int):Bool {
		var m = view.matches, n = m.length >> 1;
		if (n == 0) {
			view.currentMatch = -1;
			updateCount();
			return false;
		}
		var k = -1;
		if (dir > 0) {
			for (i in 0...n)
				if (m[i * 2] >= pos) {
					k = i;
					break;
				}
			if (k < 0) k = 0;
		} else {
			var i = n;
			while (--i >= 0)
				if (m[i * 2] < pos) {
					k = i;
					break;
				}
			if (k < 0) k = n - 1;
		}
		view.currentMatch = k;
		model.select(m[k * 2], m[k * 2 + 1]);
		view.revealRange(m[k * 2], m[k * 2 + 1], false);
		updateCount();
		view.changed(false);
		return true;
	}

	// the next match after the selection (dir < 0: the one before)
	public function findNext(dir:Int):Bool {
		if (matchesOf != model.version) refreshMatches();
		var p = model.primary;
		return selectMatch(dir > 0 ? p.to : p.from, dir);
	}

	// the current match replaced, the next one selected
	public function replaceOne():Bool {
		if (matchesOf != model.version) refreshMatches();
		var m = view.matches, k = view.currentMatch, p = model.primary;
		if (k < 0 || k * 2 + 1 >= m.length || m[k * 2] != p.from || m[k * 2 + 1] != p.to) return findNext(1);
		var at = m[k * 2];
		model.replaceMatches([m[k * 2], m[k * 2 + 1]], replaceField.text);
		refreshMatches();
		return selectMatch(at + replaceField.text.length, 1);
	}

	// every match replaced (one edit)
	public function replaceAll():Int {
		if (matchesOf != model.version) refreshMatches();
		var n = view.matches.length >> 1;
		if (n == 0) return 0;
		model.replaceMatches(view.matches.copy(), replaceField.text);
		refreshMatches();
		view.changed();
		return n;
	}

	// the find options: 0 case, 1 whole word, 2 regular expression
	public function toggle(k:Int) {
		switch k {
			case 0: caseSensitive = !caseSensitive;
			case 1: wholeWord = !wholeWord;
			case _: regex = !regex;
		}
		var on = k == 0 ? caseSensitive : k == 1 ? wholeWord : regex;
		toggles[k].semantics.checked = on;
		toggles[k].style.background = on ? view.codeTheme.colors[CodeTheme.SELECTION] : Color.TRANSPARENT;
		refreshMatches();
	}

	// the query set (a find panel opened), the first match from the caret selected
	public function search(q:String):Int {
		if (!findOpen) openFind(false);
		findField.setText(q);
		query = q;
		refreshMatches();
		selectMatch(model.primary.from, 1);
		return view.matches.length >> 1;
	}

	public function setReplacement(t:String)
		replaceField.setText(t);

	// ---- go to line

	public function openGoto() {
		if (findOpen) {
			findOpen = false;
			remove(findPanel);
			view.matches = [];
		}
		if (!gotoOpen) {
			gotoOpen = true;
			themePanel(gotoPanel);
			append(gotoPanel);
		}
		gotoField.setText("");
		gotoField.focus();
	}

	// to a line (from 1) and column (from 1)
	public function goToLine(line:Int, column = 1) {
		var l = line - 1;
		if (l < 0) l = 0;
		if (l >= model.lineCount) l = model.lineCount - 1;
		var st = model.lineStart(l), len = model.line(l).length, c = column - 1;
		var pos = st + (c < 0 ? 0 : c > len ? len : c);
		model.select(pos, pos);
		view.revealRange(pos, pos, true);
		view.changed(false);
	}

	function goToSpec(t:String) {
		var parts = StringTools.trim(t).split(":");
		var l = Std.parseInt(parts[0]);
		if (l == null) return;
		var c = parts.length > 1 ? Std.parseInt(parts[1]) : null;
		goToLine(l, c ?? 1);
	}

	// ---- the panels' nodes

	function panel(tag:String, label:String):Node {
		var p = new Node(tag);
		p.style.position = Absolute;
		p.style.top = 6;
		p.style.right = 18;
		p.style.padding = 4;
		p.style.rowGap = 4;
		p.style.radius = 6;
		p.style.borderWidth = 1;
		p.style.fontSize = 13;
		p.style.shadow = ({y: 2, blur: 8, color: Color.rgba(0, 0.15)} : Shadow);
		p.keyContext = helder.ui.actions.KeyContext.parse("CodeFind");
		p.semantics = {role: helder.ui.access.Role.Group, label: label};
		return p;
	}

	function themePanel(p:Node) {
		var c = view.codeTheme.colors;
		p.style.background = c[CodeTheme.PANEL];
		p.style.borderColor = c[CodeTheme.PANEL_BORDER];
		p.style.color = c[CodeTheme.FOREGROUND];
		for (f in [findField, replaceField, gotoField]) {
			f.style.background = c[CodeTheme.BACKGROUND];
			f.style.borderColor = c[CodeTheme.PANEL_BORDER];
			f.style.color = c[CodeTheme.FOREGROUND];
		}
	}

	function row(tag:String, kids:Array<Node>):Node {
		var r = new Node(tag);
		r.style.direction = Row;
		r.style.columnGap = 4;
		r.style.alignItems = Center;
		for (k in kids)
			r.append(k);
		return r;
	}

	function field(tag:String, label:String, w:Float):TextField {
		var f = new TextField();
		f.tag = tag;
		f.placeholder = label;
		f.semantics.label = label;
		f.style.width = w;
		f.style.padding = [3, 6, 3, 6];
		f.style.borderWidth = 1;
		f.style.radius = 4;
		return f;
	}

	function button(text:String, label:String, press:Void->Void):Node {
		var b = new Node("find-button");
		b.focusable = true;
		b.semantics = {role: helder.ui.access.Role.Button, label: label};
		b.style.padding = [2, 6, 2, 6];
		b.style.radius = 4;
		b.style.cursor = Pointer;
		b.onClick = _ -> press();
		b.append(new TextNode(text));
		return b;
	}
}
