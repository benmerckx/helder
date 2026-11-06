package helder.ui.draw;

import helder.os.linux.DBus;
import helder.ui.access.AccessAction;
import helder.ui.access.AccessNode;
import helder.ui.access.AccessTree;
import helder.ui.access.Role;
import hxmc.unsafe.*;

// The UiWindows' accessibility trees on Linux (AT-SPI 2, over D-Bus), for
// Orca and the other assistive technology: the process connects to the
// accessibility bus (its address from the session bus's org.a11y.Bus, or
// AT_SPI_BUS_ADDRESS) with helder's own D-Bus client (helder.os.linux.DBus),
// embeds its application in the registry's desktop and answers for the
// objects under /org/a11y/atspi/accessible: root (the application), and
// each node by its id (a window's root node is its frame, named by its
// title). Interfaces, where a node has what they give: Accessible (role,
// name, description, states, parent, children, attributes: a heading's and
// a tree item's level, an item's place in its set, a live region's
// politeness), Component (extents in screen or window pixels, hit tests,
// focus, scrolled into view), Action (click, expand or collapse), Value (a
// range's, set through its CurrentValue: stepped there), Text (a text
// input's or a label's text by characters, words, sentences and lines, its
// caret and selection), EditableText (its text set, inserted, deleted),
// Selection (a list's, a tab list's, a table's selectable items), Table and
// TableCell (rows and columns, a column's header), Application; their
// properties through org.freedesktop.DBus.Properties. Offsets are AT-SPI's:
// characters (code points), not UTF-16 units. Events, from what changed
// since the last frame (AccessTree.changes): ChildrenChanged (a child
// added or removed, at its index), PropertyChange (a name, a description,
// a value), StateChanged (focused, checked, indeterminate, selected,
// expanded, enabled), SelectionChanged on the container of an item
// selected, TextChanged and TextCaretMoved (a text input's edit, its
// caret), Announcement (a live region's new text). No tree is built until a
// client first asks for something. Without a session bus or an
// accessibility bus there is no adapter (and nothing to adapt to). Messages
// are answered at each turn of the loop (dispatch: UiWindow.pollAccess).
class LinuxAccess {
	static inline var ROOT = "/org/a11y/atspi/accessible/root";
	static inline var PREFIX = "/org/a11y/atspi/accessible/";
	static inline var NULL_PATH = "/org/a11y/atspi/null";
	static inline var EVENT = "org.a11y.atspi.Event.Object";
	// the cache AT-SPI clients ask an application for its objects at once:
	// empty (they ask each object instead)
	static inline var CACHE = "/org/a11y/atspi/cache";
	static var state = 0; // 0: not tried, 1: connected, -1: none
	// (no tree is built until a client asks for something: most sessions run with none)
	static var asked = false;
	static var bus:Null<DBus> = null;
	static var unique = "";
	static var appId = 0;
	static final all:Array<LinuxAccess> = [];

	final ui:Ui;
	final window:helder.os.Window;
	var tree:Null<AccessTree>;
	var parents = new Map<Int, Int>();

	public function new(window:helder.os.Window, ui:Ui) {
		this.window = window;
		this.ui = ui;
		if (state == 0) connect();
		all.push(this);
	}

	public function dispose()
		all.remove(this);

	// whether a client asked for the tree (its changes then sent)
	public static function listening():Bool
		return state == 1 && asked;

	// --- the connection ---

	static function connect() {
		state = -1;
		var address = Sys.getEnv("AT_SPI_BUS_ADDRESS");
		if (address == null || address == "") {
			var session = DBus.session();
			if (session == null) return;
			var r = session.call("org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress", "", [], 2);
			session.close();
			if (r == null || r.type != DBus.METHOD_RETURN || r.body.length == 0) return;
			address = r.body[0];
		}
		for (a in address.split(";")) {
			bus = DBus.connect(a);
			if (bus != null) break;
		}
		if (bus == null) return;
		unique = bus.name;
		// the application in the desktop (its answer, the desktop's reference, not awaited)
		bus.callLater("org.a11y.atspi.Registry", ROOT, "org.a11y.atspi.Socket", "Embed", "(so)", [[unique, ROOT]]);
		state = 1;
	}

	// the messages that came: answered (each loop turn)
	public static function dispatch() {
		if (state != 1) return;
		var m = bus.poll();
		while (m != null) {
			if (m.type == DBus.METHOD_CALL) message(m);
			m = bus.poll();
		}
	}

	// --- the tree after a frame: its events ---

	public function update() {
		if (state != 1 || !asked) return;
		var t = ui.accessTree();
		var old = tree;
		var c = t.changes(old);
		if (c.nodes.length > 0 || c.removed.length > 0) parents = t.parents();
		var said = t.announcements(old);
		tree = t;
		if (old == null) return;
		for (n in c.nodes) {
			var b = old.nodes.get(n.id);
			if (b == null) continue;
			changed(old, b, n);
		}
		if (old.focus != t.focus) {
			if (old.focus != 0 && t.nodes.exists(old.focus)) stateChanged(old.focus, "focused", false);
			if (t.focus != 0) stateChanged(t.focus, "focused", true);
		}
		for (s in said)
			emit(s.id, "Announcement", "", s.live == Assertive ? 2 : 1, 0, new Variant("s", s.text));
	}

	// a node's events: what differs from how it was
	function changed(old:AccessTree, b:AccessNode, n:AccessNode) {
		// (children: the ones gone at their old index, the new at theirs)
		if (b.children.join(",") != n.children.join(",")) {
			var i = b.children.length;
			while (i-- > 0)
				if (n.children.indexOf(b.children[i]) < 0) emit(n.id, "ChildrenChanged", "remove", i, 0, refOf(b.children[i]));
			for (i in 0...n.children.length)
				if (b.children.indexOf(n.children[i]) < 0) emit(n.id, "ChildrenChanged", "add", i, 0, refOf(n.children[i]));
		}
		if (b.name != n.name && n.id != tree.root) emit(n.id, "PropertyChange", "accessible-name", 0, 0, new Variant("s", n.name));
		if (b.description != n.description) emit(n.id, "PropertyChange", "accessible-description", 0, 0, new Variant("s", n.description ?? ""));
		if (b.valueNow != n.valueNow && n.valueNow != null) emit(n.id, "PropertyChange", "accessible-value", 0, 0, new Variant("d", n.valueNow));
		if (b.checked != n.checked) stateChanged(n.id, "checked", n.checked == true);
		if (b.mixed != n.mixed) stateChanged(n.id, "indeterminate", n.mixed);
		if (b.expanded != n.expanded && n.expanded != null) stateChanged(n.id, "expanded", n.expanded);
		if (b.disabled != n.disabled) {
			stateChanged(n.id, "enabled", !n.disabled);
			stateChanged(n.id, "sensitive", !n.disabled);
		}
		if (b.readOnly != n.readOnly) stateChanged(n.id, "read-only", n.readOnly);
		if (b.selected != n.selected && n.selected != null) {
			stateChanged(n.id, "selected", n.selected);
			var box = container(n.id);
			if (box != 0 && n.selected) emit(box, "SelectionChanged", "", 0, 0, new Variant("i", 0));
		}
		// (a text input's edit: what was deleted, then what was inserted, by the common ends)
		var was = textOf(b), now = textOf(n);
		if (was != null && now != null && was != now) {
			var x = chars(was), y = chars(now), p = 0;
			while (p < x.length && p < y.length && x[p] == y[p])
				p++;
			var q = 0;
			while (q < x.length - p && q < y.length - p && x[x.length - 1 - q] == y[y.length - 1 - q])
				q++;
			if (x.length - p - q > 0) emit(n.id, "TextChanged", "delete", p, x.length - p - q, new Variant("s", x.slice(p, x.length - q).join("")));
			if (y.length - p - q > 0) emit(n.id, "TextChanged", "insert", p, y.length - p - q, new Variant("s", y.slice(p, y.length - q).join("")));
		}
		if (now != null && n.caret >= 0 && (b.caret != n.caret || was != now)) emit(n.id, "TextCaretMoved", "", cp(now, n.caret), 0, new Variant("i", 0));
		if (now != null && (b.textStart != n.textStart || b.textEnd != n.textEnd) && (b.textStart != b.textEnd || n.textStart != n.textEnd))
			emit(n.id, "TextSelectionChanged", "", 0, 0, new Variant("i", 0));
	}

	function stateChanged(id:Int, name:String, on:Bool)
		emit(id, "StateChanged", name, on ? 1 : 0, 0, new Variant("i", 0));

	// an event of org.a11y.atspi.Event.Object (detail, detail1, detail2, any data, properties)
	function emit(id:Int, member:String, detail:String, d1:Int, d2:Int, data:Variant)
		bus.signal(pathOf(id), EVENT, member, "siiva{sv}", [detail, d1, d2, data, []]);

	// --- the objects ---

	// the window and node an object path names (id 0: the application)
	static function target(path:String):Null<{a:Null<LinuxAccess>, id:Int}> {
		if (path == ROOT) return {a: null, id: 0};
		if (!StringTools.startsWith(path, PREFIX)) return null;
		var id = Std.parseInt(path.substr(PREFIX.length));
		if (id == null) return null;
		for (w in all)
			if (w.tree != null && w.tree.nodes.exists(id)) return {a: w, id: id};
		return null;
	}

	static function pathOf(id:Int):String
		return id == 0 ? ROOT : PREFIX + id;

	static function refOf(id:Int):Variant
		return new Variant("(so)", [unique, pathOf(id)]);

	static inline function ref(id:Int):Array<Dynamic>
		return [unique, pathOf(id)];

	static inline function nullRef():Array<Dynamic>
		return ["", NULL_PATH];

	static function appName():String
		return all.length > 0 ? all[0].window.title : "helder";

	// the application's children: each window's root
	static function frames():Array<{a:LinuxAccess, id:Int}>
		return [for (w in all) if (w.tree != null) {a: w, id: w.tree.root}];

	static function atspiRole(r:Role):Int
		return switch r {
			case Button: 43;
			case CheckBox: 7;
			case Switch: 62;
			case RadioGroup: 99;
			case RadioButton: 44;
			case Slider: 51;
			case ProgressIndicator: 42;
			case TextInput | MultilineTextInput: 79;
			case Label: 29;
			case Image: 27;
			case TabList: 38;
			case Tab: 37;
			case ScrollView: 49;
			case List: 31;
			case ListItem | ListBoxOption: 32;
			case Heading: 83;
			case Link: 88;
			case Dialog: 16;
			case AlertDialog: 2;
			case Menu: 33;
			case MenuItem: 35;
			case MenuItemCheckBox: 8;
			case MenuItemRadio: 45;
			case ListBox: 98;
			case ComboBox: 11;
			case Tooltip: 64;
			// (ATSPI_ROLE_TABLE, TABLE_ROW, TABLE_CELL, TABLE_COLUMN_HEADER)
			case Table: 55;
			case Row: 90;
			case Cell: 56;
			case ColumnHeader: 57;
			// (ATSPI_ROLE_TREE, TREE_ITEM)
			case Tree: 65;
			case TreeItem: 91;
			case Separator: 50;
			case SpinButton: 52;
			case MenuBar: 34;
			case Toolbar: 63;
			// (ATSPI_ROLE_LANDMARK)
			case Navigation: 110;
			case Group | TabPanel: 39;
		}

	static final ROLE_NAMES = [
		2 => "alert", 7 => "check box", 8 => "check menu item", 45 => "radio menu item", 11 => "combo box", 16 => "dialog", 23 => "frame", 27 => "image", 29 => "label", 31 => "list", 32 => "list item", 33 => "menu",
		35 => "menu item", 37 => "page tab", 38 => "page tab list", 39 => "panel", 40 => "password text", 42 => "progress bar", 43 => "push button", 44 => "radio button",
		49 => "scroll pane", 51 => "slider", 62 => "toggle button", 64 => "tool tip", 75 => "application", 79 => "entry", 83 => "heading", 88 => "link",
		98 => "list box", 99 => "grouping", 55 => "table", 56 => "table cell", 57 => "table column header", 90 => "table row", 65 => "tree",
		91 => "tree item", 50 => "separator", 52 => "spin button", 63 => "tool bar", 110 => "landmark", 34 => "menu bar"
	];

	function roleOf(id:Int):Int {
		if (id == tree.root) return 23; // FRAME
		var n = tree.nodes.get(id);
		// (a password's: PASSWORD_TEXT; a button that stays pressed: TOGGLE_BUTTON)
		return n.secret ? 40 : n.role == Button && n.checked != null ? 62 : atspiRole(n.role);
	}

	function nameOf(id:Int):String
		return id == tree.root ? window.title : tree.nodes.get(id).name;

	// what its actions are called (DoAction's index into them)
	static function actions(n:AccessNode):Array<String> {
		var out = [];
		if (n.pressable()) out.push("click");
		if (n.expanded != null && !n.disabled) out.push(n.expanded ? "collapse" : "expand");
		return out;
	}

	// a text input's text or a label's (null: none)
	static function textOf(n:Null<AccessNode>):Null<String>
		return n == null ? null : n.editable() ? n.value ?? "" : n.role == Label ? n.name : null;

	// the items a container selects among: a table's rows, else its children that are selected or not
	function items(n:AccessNode):Array<AccessNode> {
		var src = n.role == Table ? tree.tableRows(n.id) : [for (k in n.children) tree.nodes.get(k)];
		return [for (c in src) if (c.selected != null) c];
	}

	// the container whose selection an item is part of (0: none)
	function container(id:Int):Int {
		var t = tree.ancestor(id, Table, parents);
		if (t != 0) return t;
		var p = parents.get(id);
		return p == null ? 0 : p;
	}

	function interfaces(n:Null<AccessNode>):Array<String> {
		if (n == null) return ["org.a11y.atspi.Accessible", "org.a11y.atspi.Application"];
		var out = ["org.a11y.atspi.Accessible", "org.a11y.atspi.Component"];
		if (actions(n).length > 0) out.push("org.a11y.atspi.Action");
		if (n.valueNow != null) out.push("org.a11y.atspi.Value");
		if (textOf(n) != null) out.push("org.a11y.atspi.Text");
		if (n.editable() && !n.readOnly) out.push("org.a11y.atspi.EditableText");
		if (items(n).length > 0) out.push("org.a11y.atspi.Selection");
		if (n.role == Table) out.push("org.a11y.atspi.Table");
		if ((n.role == Cell || n.role == ColumnHeader) && n.rowIndex >= 0) out.push("org.a11y.atspi.TableCell");
		return out;
	}

	// AT-SPI's state set: two 32-bit words
	function states(id:Int):Array<Int> {
		var n = tree.nodes.get(id), bits = [0, 0];
		inline function on(s:Int)
			bits[s >> 5] |= 1 << (s & 31);
		on(30); // VISIBLE
		// (SHOWING: in the window)
		if (n.x + n.width > 0 && n.y + n.height > 0 && n.x < ui.width && n.y < ui.height) on(25);
		if (id == tree.root) on(1); // ACTIVE
		if (!n.disabled) {
			on(8); // ENABLED
			on(24); // SENSITIVE
		}
		if (n.focusable) on(11); // FOCUSABLE
		if (tree.focus == id) on(12); // FOCUSED
		if (n.checked != null) {
			on(41); // CHECKABLE
			if (n.checked) on(n.role == Button ? 20 : 4); // PRESSED, CHECKED
			if (n.mixed) on(32); // INDETERMINATE
		}
		if (n.selected != null) {
			on(22); // SELECTABLE
			if (n.selected) on(23); // SELECTED
		}
		if (n.multiselectable) on(18); // MULTISELECTABLE
		if (n.expanded != null) {
			on(9); // EXPANDABLE
			on(n.expanded ? 10 : 5); // EXPANDED, COLLAPSED
		}
		if (n.role == ComboBox) on(42); // HAS_POPUP
		if (n.editable()) {
			if (!n.readOnly) on(7); // EDITABLE
			on(n.role == MultilineTextInput ? 17 : 26); // MULTI_LINE, SINGLE_LINE
			on(38); // SELECTABLE_TEXT
		}
		if (n.readOnly) on(43); // READ_ONLY
		if (n.role == Label) on(38);
		if (n.role == Slider || n.role == ProgressIndicator) on(14); // HORIZONTAL
		return bits;
	}

	// a node's box in pixels: the screen's (coordinates 0) or the window's (1, 2)
	function extents(id:Int, coords:Int):Array<Int> {
		var n = tree.nodes.get(id);
		var k = ui.width > 0 ? window.surface.width / ui.width : 1.0;
		var ox = 0, oy = 0;
		// (X11's screen; Wayland has none: the window's)
		if (coords == 0 && Std.isOfType(@:privateAccess window.native, helder.os.x11.X11Window)) {
			var d = window.surface.display;
			Arena.scoped(a -> {
				var x:Ptr<Int32> = a.alloc(4), y:Ptr<Int32> = a.alloc(4), child:Ptr<Int64> = a.alloc(8);
				if (helder.os.x11.Xlib.XTranslateCoordinates(d, window.surface.handle.toI64(), helder.os.x11.Xlib.XDefaultRootWindow(d), 0, 0, x, y, child) != 0) {
					ox = x.value;
					oy = y.value;
				}
			});
		}
		return [ox + Math.round(n.x * k), oy + Math.round(n.y * k), Math.round(n.width * k), Math.round(n.height * k)];
	}

	// the deepest node holding a point (in coords' pixels)
	function at(x:Int, y:Int, coords:Int):Int {
		var id = tree.root;
		while (true) {
			var next = 0;
			for (k in tree.nodes.get(id).children) {
				var e = extents(k, coords);
				if (x >= e[0] && y >= e[1] && x < e[0] + e[2] && y < e[1] + e[3]) next = k;
			}
			if (next == 0) return id;
			id = next;
		}
	}

	function act(id:Int, action:AccessAction, ?value:String):Bool
		return ui.accessAction(id, action, value);

	// --- text: offsets in characters ---

	// a string's characters (code points, each as a string)
	static function chars(s:String):Array<String> {
		var out = [], i = 0;
		while (i < s.length) {
			var c = s.charCodeAt(i);
			var n = c >= 0xD800 && c < 0xDC00 && i + 1 < s.length ? 2 : 1;
			out.push(s.substr(i, n));
			i += n;
		}
		return out;
	}

	// a UTF-16 index as a character offset
	static function cp(s:String, u:Int):Int {
		var i = 0, n = 0;
		while (i < u && i < s.length) {
			var c = s.charCodeAt(i);
			i += c >= 0xD800 && c < 0xDC00 && i + 1 < s.length ? 2 : 1;
			n++;
		}
		return n;
	}

	// a character offset as a UTF-16 index
	static function u16(s:String, c:Int):Int {
		var cs = chars(s), i = 0;
		for (k in 0...Std.int(Math.max(0, Math.min(c, cs.length))))
			i += cs[k].length;
		return i;
	}

	// the text's pieces of a kind, as [start, end) character ranges covering
	// it: characters (0), words with the spaces after them (1, 2), sentences
	// with theirs (3, 4), lines with their line break (5, 6)
	static function pieces(cs:Array<String>, kind:Int):Array<Array<Int>> {
		var out = [], i = 0, n = cs.length;
		inline function space(c:String)
			return c == " " || c == "\t" || c == "\n";
		inline function blank(c:String)
			return c == " " || c == "\t";
		while (i < n) {
			var end = i;
			switch kind {
				case 0:
					end = i + 1;
				case 1 | 2:
					while (end < n && !space(cs[end]))
						end++;
					while (end < n && space(cs[end]))
						end++;
				case 3 | 4:
					while (end < n && ".!?\n".indexOf(cs[end]) < 0)
						end++;
					if (end < n) end++;
					while (end < n && blank(cs[end]))
						end++;
				case _:
					while (end < n && cs[end] != "\n")
						end++;
					if (end < n) end++;
			}
			if (end <= i) end = i + 1;
			out.push([i, end]);
			i = end;
		}
		if (out.length == 0) out.push([0, 0]);
		return out;
	}

	// the piece holding an offset (shift -1: the one before it, 1: after it): its text, start and end
	static function piece(s:String, offset:Int, kind:Int, shift:Int):Array<Dynamic> {
		var cs = chars(s), ps = pieces(cs, kind), at = ps.length - 1;
		for (i in 0...ps.length)
			if (offset < ps[i][1]) {
				at = i;
				break;
			}
		at += shift;
		if (at < 0 || at >= ps.length || cs.length == 0) return ["", 0, 0];
		var p = ps[at];
		return [cs.slice(p[0], p[1]).join(""), p[0], p[1]];
	}

	// GetStringAtOffset's granularity: the piece without its trailing spaces (a word, a sentence, a line)
	static function granule(s:String, offset:Int, granularity:Int):Array<Dynamic> {
		var kind = switch granularity {
			case 0: 0;
			case 1: 1;
			case 2: 3;
			case _: 5;
		}
		var p = piece(s, offset, kind, 0);
		if (kind == 0) return p;
		var t:String = p[0], trimmed = StringTools.rtrim(t);
		return [trimmed, p[1], (p[1] : Int) + chars(trimmed).length];
	}

	// a range of characters' box (an estimate: the node's box shared out by
	// its characters on one line; lines by the line breaks)
	function charBox(n:AccessNode, s:String, from:Int, to:Int, coords:Int):Array<Int> {
		var e = extents(n.id, coords), cs = chars(s);
		if (cs.length == 0) return [e[0], e[1], 0, e[3]];
		var lines = pieces(cs, 5), line = 0;
		for (i in 0...lines.length)
			if (from >= lines[i][0] && from < lines[i][1]) line = i;
		var l = lines[line], len = Math.max(1, l[1] - l[0]), h = e[3] / lines.length;
		var x0 = e[0] + Math.round(e[2] * (from - l[0]) / len), x1 = e[0] + Math.round(e[2] * Math.min(to - l[0], len) / len);
		return [x0, Math.round(e[1] + h * line), Std.int(Math.max(0, x1 - x0)), Math.round(h)];
	}

	// --- the messages ---

	static function message(m:DBusMessage) {
		if (!asked) {
			asked = true;
			for (w in all)
				w.update();
		}
		var path = m.path ?? "", iface = m.iface ?? "", member = m.member ?? "";
		if (path == CACHE && member == "GetItems") {
			bus.reply(m, "a((so)(so)(so)iiassusau)", [[]]);
			return;
		}
		if (iface == "org.freedesktop.DBus.Introspectable" && member == "Introspect") {
			bus.reply(m, "s", ["<node/>"]);
			return;
		}
		var t = target(path);
		if (t == null) {
			bus.error(m, "org.freedesktop.DBus.Error.UnknownObject", path);
			return;
		}
		var r = answer(t.a, t.id, iface, member, m.body);
		if (r == null) bus.error(m, "org.freedesktop.DBus.Error.UnknownMethod", iface + "." + member) else bus.reply(m, r.sig, r.args);
	}

	static inline function out(sig:String, args:Array<Dynamic>):{sig:String, args:Array<Dynamic>}
		return {sig: sig, args: args};

	// a call's answer: null when the method is not one of ours
	static function answer(w:Null<LinuxAccess>, id:Int, iface:String, member:String, args:Array<Dynamic>):Null<{sig:String, args:Array<Dynamic>}> {
		if (iface == "org.freedesktop.DBus.Properties") {
			switch member {
				case "Get":
					var v = property(w, id, args[0], args[1]);
					return v == null ? null : out("v", [v]);
				case "GetAll":
					var entries:Array<Dynamic> = [];
					for (p in propertyNames(w, id, args[0])) {
						var v = property(w, id, args[0], p);
						if (v != null) entries.push([p, v]);
					}
					return out("a{sv}", [entries]);
				case "Set":
					var v:Variant = args[2];
					if (args[0] == "org.a11y.atspi.Application" && args[1] == "Id") {
						appId = v.value;
						return out("", []);
					}
					if (w != null && args[0] == "org.a11y.atspi.Value" && args[1] == "CurrentValue") {
						w.act(id, SetValue, Std.string(v.value));
						return out("", []);
					}
					return null;
				case _: return null;
			}
		}
		if (w == null) return application(iface, member, args);
		return w.method(id, iface, member, args);
	}

	function method(id:Int, iface:String, member:String, args:Array<Dynamic>):Null<{sig:String, args:Array<Dynamic>}> {
		var n = tree.nodes.get(id);
		switch iface {
			case "org.a11y.atspi.Accessible":
				switch member {
					case "GetChildren":
						return out("a(so)", [[for (k in n.children) ref(k)]]);
					case "GetChildAtIndex":
						var i:Int = args[0];
						return out("(so)", [i >= 0 && i < n.children.length ? ref(n.children[i]) : nullRef()]);
					case "GetIndexInParent":
						var p = parents.get(id);
						return out("i", [id == tree.root ? all.indexOf(this) : p == null ? -1 : tree.nodes.get(p).children.indexOf(id)]);
					case "GetRole":
						return out("u", [roleOf(id)]);
					case "GetRoleName" | "GetLocalizedRoleName":
						return out("s", [ROLE_NAMES.get(roleOf(id)) ?? "unknown"]);
					case "GetState":
						return out("au", [states(id)]);
					case "GetAttributes":
						return out("a{ss}", [attributes(n)]);
					case "GetRelationSet":
						return out("a(ua(so))", [[]]);
					case "GetApplication":
						return out("(so)", [ref(0)]);
					case "GetInterfaces":
						return out("as", [interfaces(n)]);
					case _:
				}
			case "org.a11y.atspi.Component":
				switch member {
					case "GetExtents":
						return out("(iiii)", [extents(id, args[0])]);
					case "GetPosition":
						var e = extents(id, args[0]);
						return out("(ii)", [[e[0], e[1]]]);
					case "GetSize":
						var e = extents(id, 1);
						return out("(ii)", [[e[2], e[3]]]);
					case "Contains":
						var e = extents(id, args[2]), x:Int = args[0], y:Int = args[1];
						return out("b", [x >= e[0] && y >= e[1] && x < e[0] + e[2] && y < e[1] + e[3]]);
					case "GetAccessibleAtPoint":
						return out("(so)", [ref(at(args[0], args[1], args[2]))]);
					case "GetLayer":
						return out("u", [id == tree.root ? 7 : 3]); // WINDOW, WIDGET
					case "GetMDIZOrder":
						return out("n", [0]);
					case "GrabFocus":
						return out("b", [act(id, Focus)]);
					case "GetAlpha":
						return out("d", [1.0]);
					case "ScrollTo" | "ScrollToPoint":
						return out("b", [act(id, ScrollIntoView)]);
					case "SetExtents" | "SetPosition" | "SetSize":
						return out("b", [false]);
					case _:
				}
			case "org.a11y.atspi.Action":
				var names = actions(n);
				switch member {
					case "GetActions":
						return out("a(sss)", [[for (a in names) [a, "", ""]]]);
					case "GetName" | "GetLocalizedName":
						var i:Int = args[0];
						return out("s", [i >= 0 && i < names.length ? names[i] : ""]);
					case "GetDescription" | "GetKeyBinding":
						return out("s", [""]);
					case "DoAction":
						var i:Int = args[0];
						var done = i >= 0 && i < names.length && act(id, switch names[i] {
							case "expand": Expand;
							case "collapse": Collapse;
							case _: Click;
						});
						return out("b", [done]);
					case _:
				}
			case "org.a11y.atspi.Text":
				var s = textOf(n);
				if (s == null) return null;
				var cs = chars(s), len = cs.length;
				inline function clamp(i:Int)
					return i < 0 ? 0 : i > len ? len : i;
				switch member {
					case "GetText":
						var from = clamp(args[0]), to:Int = args[1];
						to = to < 0 || to > len ? len : to;
						return out("s", [from < to ? cs.slice(from, to).join("") : ""]);
					case "GetCharacterAtOffset":
						var i:Int = args[0];
						return out("i", [i >= 0 && i < len ? cs[i].charCodeAt(0) >= 0xD800 && cs[i].length == 2 ? 0x10000 + ((cs[i].charCodeAt(0) - 0xD800) << 10) + (cs[i].charCodeAt(1) - 0xDC00) : cs[i].charCodeAt(0) : 0]);
					case "GetTextAtOffset" | "GetTextBeforeOffset" | "GetTextAfterOffset":
						var p = piece(s, args[0], args[1], member == "GetTextAtOffset" ? 0 : member == "GetTextBeforeOffset" ? -1 : 1);
						return out("sii", p);
					case "GetStringAtOffset":
						return out("sii", granule(s, args[0], args[1]));
					case "SetCaretOffset":
						var c = u16(s, args[0]);
						return out("b", [act(id, SetSelection, '$c,$c')]);
					case "GetNSelections":
						return out("i", [n.textStart >= 0 && n.textStart != n.textEnd ? 1 : 0]);
					case "GetSelection":
						return out("ii", n.textStart >= 0 && n.textStart != n.textEnd ? [cp(s, n.textStart), cp(s, n.textEnd)] : [0, 0]);
					case "AddSelection" | "SetSelection":
						var from:Int = member == "AddSelection" ? args[0] : args[1], to:Int = member == "AddSelection" ? args[1] : args[2];
						return out("b", [n.editable() && act(id, SetSelection, u16(s, from) + "," + u16(s, to))]);
					case "RemoveSelection":
						var c = n.caret < 0 ? 0 : n.caret;
						return out("b", [n.editable() && act(id, SetSelection, '$c,$c')]);
					case "GetCharacterExtents":
						var i = clamp(args[0]);
						return out("iiii", charBox(n, s, i, i + 1, args[1]));
					case "GetRangeExtents":
						var a = charBox(n, s, clamp(args[0]), clamp(args[0]) + 1, args[2]), b = charBox(n, s, Std.int(Math.max(0, clamp(args[1]) - 1)), clamp(args[1]), args[2]);
						var x0 = Std.int(Math.min(a[0], b[0])), y0 = Std.int(Math.min(a[1], b[1]));
						return out("iiii", [x0, y0, Std.int(Math.max(a[0] + a[2], b[0] + b[2])) - x0, Std.int(Math.max(a[1] + a[3], b[1] + b[3])) - y0]);
					case "GetOffsetAtPoint":
						var x:Int = args[0], y:Int = args[1];
						for (i in 0...len) {
							var b = charBox(n, s, i, i + 1, args[2]);
							if (x >= b[0] && x < b[0] + b[2] && y >= b[1] && y < b[1] + b[3]) return out("i", [i]);
						}
						return out("i", [-1]);
					case "GetAttributes" | "GetAttributeRun":
						return out("a{ss}ii", [[], 0, len]);
					case "GetDefaultAttributes" | "GetDefaultAttributeSet":
						return out("a{ss}", [[]]);
					case "GetAttributeValue":
						return out("s", [""]);
					case "GetBoundedRanges":
						return out("a(iisv)", [[]]);
					case "ScrollSubstringTo" | "ScrollSubstringToPoint":
						return out("b", [act(id, ScrollIntoView)]);
					case _:
				}
			case "org.a11y.atspi.EditableText":
				if (!n.editable() || n.readOnly) return null;
				var s = n.value ?? "", cs = chars(s);
				inline function clamp(i:Int)
					return i < 0 ? 0 : i > cs.length ? cs.length : i;
				switch member {
					case "SetTextContents":
						return out("b", [act(id, SetValue, args[0])]);
					case "InsertText":
						if (n.secret) return out("b", [false]);
						var at = clamp(args[0]), text:String = args[1], length:Int = args[2];
						var add = length < 0 ? text : chars(text).slice(0, length).join("");
						return out("b", [act(id, SetValue, cs.slice(0, at).join("") + add + cs.slice(at).join(""))]);
					case "DeleteText":
						if (n.secret) return out("b", [false]);
						var from = clamp(args[0]), to = clamp(args[1]);
						return out("b", [from < to && act(id, SetValue, cs.slice(0, from).join("") + cs.slice(to).join(""))]);
					case "CopyText":
						return out("", []);
					case "CutText" | "PasteText":
						return out("b", [false]);
					case _:
				}
			case "org.a11y.atspi.Selection":
				var its = items(n), chosen = [for (c in its) if (c.selected) c];
				inline function item(i:Int)
					return i >= 0 && i < its.length ? its[i] : null;
				switch member {
					case "GetSelectedChild":
						var i:Int = args[0];
						return out("(so)", [i >= 0 && i < chosen.length ? ref(chosen[i].id) : nullRef()]);
					case "SelectChild":
						var c = item(args[0]);
						return out("b", [c != null && act(c.id, Select)]);
					case "DeselectSelectedChild":
						var i:Int = args[0];
						return out("b", [n.multiselectable && i >= 0 && i < chosen.length && act(chosen[i].id, Click)]);
					case "DeselectChild":
						var c = item(args[0]);
						return out("b", [n.multiselectable && c != null && c.selected && act(c.id, Click)]);
					case "IsChildSelected":
						var c = item(args[0]);
						return out("b", [c != null && c.selected]);
					case "SelectAll" | "ClearSelection":
						return out("b", [false]);
					case _:
				}
			case "org.a11y.atspi.Table":
				if (n.role != Table) return null;
				var rows = tree.tableRows(id), cols = n.colCount;
				inline function selectedRow(r:Int)
					return r >= 0 && r < rows.length && rows[r].selected == true;
				switch member {
					case "GetAccessibleAt":
						var c = tree.cellAt(id, args[0], args[1]);
						return out("(so)", [c == null ? nullRef() : ref(c.id)]);
					case "GetIndexAt":
						var r:Int = args[0], c:Int = args[1];
						return out("i", [r * cols + c]);
					case "GetRowAtIndex":
						var i:Int = args[0];
						return out("i", [cols == 0 ? -1 : Std.int(i / cols)]);
					case "GetColumnAtIndex":
						var i:Int = args[0];
						return out("i", [cols == 0 ? -1 : i % cols]);
					case "GetRowDescription":
						return out("s", [""]);
					case "GetColumnDescription":
						var h = tree.columnHeader(id, args[0]);
						return out("s", [h == null ? "" : h.name]);
					case "GetRowExtentAt" | "GetColumnExtentAt":
						return out("i", [1]);
					case "GetRowHeader":
						return out("(so)", [nullRef()]);
					case "GetColumnHeader":
						var h = tree.columnHeader(id, args[0]);
						return out("(so)", [h == null ? nullRef() : ref(h.id)]);
					case "GetSelectedRows":
						return out("ai", [[for (r in 0...rows.length) if (selectedRow(r)) r]]);
					case "GetSelectedColumns":
						return out("ai", [[]]);
					case "IsRowSelected":
						return out("b", [selectedRow(args[0])]);
					case "IsColumnSelected":
						return out("b", [false]);
					case "IsSelected":
						return out("b", [selectedRow(args[0])]);
					case "AddRowSelection":
						var r:Int = args[0];
						return out("b", [r >= 0 && r < rows.length && rows[r].selected != null && act(rows[r].id, Select)]);
					case "RemoveRowSelection" | "AddColumnSelection" | "RemoveColumnSelection":
						return out("b", [false]);
					case "GetRowColumnExtentsAtIndex":
						var i:Int = args[0];
						if (cols == 0 || i < 0 || i >= rows.length * cols) return out("biiiib", [false, 0, 0, 0, 0, false]);
						var r = Std.int(i / cols);
						return out("biiiib", [true, r, i % cols, 1, 1, selectedRow(r)]);
					case _:
				}
			case "org.a11y.atspi.TableCell":
				switch member {
					case "GetRowHeaderCells":
						return out("a(so)", [[]]);
					case "GetColumnHeaderCells":
						var t = tree.ancestor(id, Table, parents), h = t == 0 ? null : tree.columnHeader(t, n.colIndex);
						return out("a(so)", [h == null || h.id == id ? [] : [ref(h.id)]]);
					case "GetRowColumnSpan":
						return out("iiii", [n.rowIndex, n.colIndex, 1, 1]);
					case _:
				}
			case _:
		}
		return null;
	}

	// its attributes: a landmark's kind, the current one of a set, a level,
	// an item's place in its set, a live region's politeness (as Chromium gives them)
	function attributes(n:AccessNode):Array<Dynamic> {
		var pairs:Array<Dynamic> = [["toolkit", "helder"]];
		if (n.role == Navigation) pairs.push(["xml-roles", "navigation"]);
		if (n.current) pairs.push(["current", "page"]);
		if (n.level != null) pairs.push(["level", Std.string(n.level)]);
		if (n.setSize > 0) {
			pairs.push(["posinset", Std.string(n.posInSet)]);
			pairs.push(["setsize", Std.string(n.setSize)]);
		}
		var live = n.live.aria();
		if (live != null) {
			pairs.push(["live", live]);
			pairs.push(["container-live", live]);
		}
		return pairs;
	}

	static function application(iface:String, member:String, args:Array<Dynamic>):Null<{sig:String, args:Array<Dynamic>}> {
		var fs = frames();
		return switch [iface, member] {
			case ["org.a11y.atspi.Accessible", "GetChildren"]: out("a(so)", [[for (f in fs) ref(f.id)]]);
			case ["org.a11y.atspi.Accessible", "GetChildAtIndex"]:
				var i:Int = args[0];
				out("(so)", [i >= 0 && i < fs.length ? ref(fs[i].id) : nullRef()]);
			case ["org.a11y.atspi.Accessible", "GetIndexInParent"]: out("i", [-1]);
			case ["org.a11y.atspi.Accessible", "GetRole"]: out("u", [75]);
			case ["org.a11y.atspi.Accessible", "GetRoleName" | "GetLocalizedRoleName"]: out("s", ["application"]);
			case ["org.a11y.atspi.Accessible", "GetState"]: out("au", [[0, 0]]);
			case ["org.a11y.atspi.Accessible", "GetAttributes"]: out("a{ss}", [[["toolkit", "helder"]]]);
			case ["org.a11y.atspi.Accessible", "GetRelationSet"]: out("a(ua(so))", [[]]);
			case ["org.a11y.atspi.Accessible", "GetApplication"]: out("(so)", [ref(0)]);
			case ["org.a11y.atspi.Accessible", "GetInterfaces"]: out("as", [["org.a11y.atspi.Accessible", "org.a11y.atspi.Application"]]);
			case ["org.a11y.atspi.Application", "GetLocale"]: out("s", ["C"]);
			case _: null;
		}
	}

	static function propertyNames(w:Null<LinuxAccess>, id:Int, iface:String):Array<String>
		return switch iface {
			case "org.a11y.atspi.Accessible": ["Name", "Description", "Parent", "ChildCount", "Locale", "AccessibleId", "HelpText"];
			case "org.a11y.atspi.Application": ["ToolkitName", "Version", "AtspiVersion", "Id"];
			case "org.a11y.atspi.Action": ["NActions"];
			case "org.a11y.atspi.Value": ["MinimumValue", "MaximumValue", "MinimumIncrement", "CurrentValue", "Text"];
			case "org.a11y.atspi.Text": ["CharacterCount", "CaretOffset"];
			case "org.a11y.atspi.Selection": ["NSelectedChildren"];
			case "org.a11y.atspi.Table": ["NRows", "NColumns", "Caption", "Summary", "NSelectedRows", "NSelectedColumns"];
			case "org.a11y.atspi.TableCell": ["ColumnSpan", "Position", "RowSpan", "Table"];
			case _: [];
		}

	// a property's value (null: none)
	static function property(w:Null<LinuxAccess>, id:Int, iface:String, name:String):Null<Variant> {
		var n = w == null ? null : w.tree.nodes.get(id);
		return switch [iface, name] {
			case ["org.a11y.atspi.Accessible", "Name"]: new Variant("s", w == null ? appName() : w.nameOf(id));
			case ["org.a11y.atspi.Accessible", "Description" | "HelpText"]: new Variant("s", n == null ? "" : n.description ?? "");
			case ["org.a11y.atspi.Accessible", "Parent"]:
				new Variant("(so)", w == null ? ["org.a11y.atspi.Registry", ROOT] : id == w.tree.root ? ref(0) : ref(w.parents.get(id) ?? w.tree.root));
			case ["org.a11y.atspi.Accessible", "ChildCount"]: new Variant("i", w == null ? frames().length : n.children.length);
			case ["org.a11y.atspi.Accessible", "Locale"]: new Variant("s", "C");
			case ["org.a11y.atspi.Accessible", "AccessibleId"]: new Variant("s", w == null ? "" : "helder-" + id);
			case ["org.a11y.atspi.Application", "ToolkitName"]: new Variant("s", "helder");
			case ["org.a11y.atspi.Application", "Version"]: new Variant("s", "1");
			case ["org.a11y.atspi.Application", "AtspiVersion"]: new Variant("s", "2.1");
			case ["org.a11y.atspi.Application", "Id"]: new Variant("i", appId);
			case _ if (n == null): null;
			case ["org.a11y.atspi.Action", "NActions"]: new Variant("i", actions(n).length);
			case ["org.a11y.atspi.Value", "MinimumValue" | "MaximumValue" | "MinimumIncrement" | "CurrentValue"] if (n.valueNow != null):
				var lo = n.valueMin ?? 0.0, hi = n.valueMax ?? 1.0;
				new Variant("d", switch name {
					case "MinimumValue": lo;
					case "MaximumValue": hi;
					case "MinimumIncrement": (hi - lo) / 20;
					case _: n.valueNow;
				});
			case ["org.a11y.atspi.Value", "Text"]: new Variant("s", n.valueText ?? "");
			case ["org.a11y.atspi.Text", "CharacterCount"] if (textOf(n) != null): new Variant("i", chars(textOf(n)).length);
			case ["org.a11y.atspi.Text", "CaretOffset"] if (textOf(n) != null): new Variant("i", n.caret < 0 ? 0 : cp(textOf(n), n.caret));
			case ["org.a11y.atspi.Selection", "NSelectedChildren"]: new Variant("i", [for (c in w.items(n)) if (c.selected) c].length);
			case ["org.a11y.atspi.Table", "NRows"]: new Variant("i", n.rowCount);
			case ["org.a11y.atspi.Table", "NColumns"]: new Variant("i", n.colCount);
			case ["org.a11y.atspi.Table", "Caption" | "Summary"]: new Variant("(so)", nullRef());
			case ["org.a11y.atspi.Table", "NSelectedRows"]: new Variant("i", [for (r in w.tree.tableRows(id)) if (r.selected == true) r].length);
			case ["org.a11y.atspi.Table", "NSelectedColumns"]: new Variant("i", 0);
			case ["org.a11y.atspi.TableCell", "ColumnSpan" | "RowSpan"]: new Variant("i", 1);
			case ["org.a11y.atspi.TableCell", "Position"]: new Variant("(ii)", [n.rowIndex, n.colIndex]);
			case ["org.a11y.atspi.TableCell", "Table"]:
				var t = w.tree.ancestor(id, Table, w.parents);
				new Variant("(so)", t == 0 ? nullRef() : ref(t));
			case _: null;
		}
	}
}
