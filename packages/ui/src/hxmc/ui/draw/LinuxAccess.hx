package hxmc.ui.draw;

import hxmc.ui.access.AccessNode;
import hxmc.ui.access.AccessTree;
import hxmc.ui.access.Role;
import hxmc.unsafe.*;

// The UiWindows' accessibility trees on Linux (AT-SPI 2, over D-Bus), for
// Orca and the other assistive technology: the process connects to the
// accessibility bus (its address from the session bus's org.a11y.Bus, or
// AT_SPI_BUS_ADDRESS), embeds its application in the registry's desktop and
// answers for the objects under /org/a11y/atspi/accessible: root (the
// application), and each node by its id (a window's root node is its frame,
// named by its title). Interfaces: Accessible (role, name, description,
// states, parent, children, relations, attributes), Component (extents in
// screen or window pixels, hit tests, focus), Action (a press: Click),
// Value (a range: stepped toward a value set), Text (a text input's text),
// Application; their properties through org.freedesktop.DBus.Properties. A
// change of focus emits StateChanged "focused", a live region's change
// Announcement (its new text). libdbus is loaded at run
// time: without it, or without a bus, there is no adapter (and nothing to
// adapt to). Messages are dispatched at each turn of the loop (pollAccess).
class LinuxAccess {
	static inline var ROOT = "/org/a11y/atspi/accessible/root";
	static inline var PREFIX = "/org/a11y/atspi/accessible/";
	// the cache AT-SPI clients ask an application for its objects at once:
	// empty (they ask each object instead)
	static inline var CACHE = "/org/a11y/atspi/cache";
	static var state = 0; // 0: not tried, 1: connected, -1: none
	// (no tree is built until a client asks for something: most sessions run with none)
	static var asked = false;
	static var conn = Ptr.nil();
	static var unique = "";
	static final all:Array<LinuxAccess> = [];
	static var vtable:Ptr = Ptr.nil();
	static var err:Ptr = Ptr.nil();

	final ui:Ui;
	final window:hxmc.os.Window;
	var tree:Null<AccessTree>;
	final parents = new Map<Int, Int>();

	public function new(window:hxmc.os.Window, ui:Ui) {
		this.window = window;
		this.ui = ui;
		if (state == 0) connect();
		all.push(this);
	}

	public function dispose()
		all.remove(this);

	// --- the connection ---

	static function connect() {
		state = -1;
		var lib = Arena.scopedValue(a -> Posix.dlopen(a.cstring("libdbus-1.so.3"), 2)); // RTLD_NOW
		if (lib.isNull()) return;
		if (DBus.load(name -> Posix.dlsym(lib, name)) != null) return;
		err = LibC.malloc(64);
		DBus.dbus_error_init(err);
		var address = Sys.getEnv("AT_SPI_BUS_ADDRESS");
		if (address == null || address == "") {
			var session = DBus.dbus_bus_get_private(0, err);
			if (session.isNull()) return clearError();
			DBus.dbus_connection_set_exit_on_disconnect(session, 0);
			var m = Arena.scopedValue(a -> DBus.dbus_message_new_method_call(a.cstring("org.a11y.Bus"), a.cstring("/org/a11y/bus"), a.cstring("org.a11y.Bus"),
				a.cstring("GetAddress")));
			var reply = DBus.dbus_connection_send_with_reply_and_block(session, m, 2000, err);
			DBus.dbus_message_unref(m);
			if (reply.isNull()) return clearError();
			address = readString(reply);
			DBus.dbus_message_unref(reply);
			DBus.dbus_connection_close(session);
			DBus.dbus_connection_unref(session);
			if (address == null) return;
		}
		conn = Arena.scopedValue(a -> DBus.dbus_connection_open_private(a.cstring(address), err));
		if (conn.isNull()) return clearError();
		DBus.dbus_connection_set_exit_on_disconnect(conn, 0);
		if (DBus.dbus_bus_register(conn, err) == 0) return clearError();
		unique = (cast DBus.dbus_bus_get_unique_name(conn) : CString).toString();
		vtable = LibC.malloc(48);
		var v:Ptr<Ptr> = vtable;
		for (i in 0...6)
			v[i] = Ptr.nil();
		v[1] = Callback.addr(message);
		Arena.scoped(a -> {
			DBus.dbus_connection_register_fallback(conn, a.cstring("/org/a11y/atspi/accessible"), vtable, Ptr.nil());
			DBus.dbus_connection_register_fallback(conn, a.cstring(CACHE), vtable, Ptr.nil());
		});
		// the application in the desktop (its answer, the desktop's reference, not awaited)
		var embed = Arena.scopedValue(a -> DBus.dbus_message_new_method_call(a.cstring("org.a11y.atspi.Registry"), a.cstring(ROOT),
			a.cstring("org.a11y.atspi.Socket"), a.cstring("Embed")));
		Arena.scoped(a -> {
			var it = a.alloc(128), sub = a.alloc(128);
			DBus.dbus_message_iter_init_append(embed, it);
			DBus.dbus_message_iter_open_container(it, "r".code, Ptr.nil(), sub);
			basicString(a, sub, "s".code, unique);
			basicString(a, sub, "o".code, ROOT);
			DBus.dbus_message_iter_close_container(it, sub);
		});
		DBus.dbus_connection_send(conn, embed, Ptr.nil());
		DBus.dbus_message_unref(embed);
		DBus.dbus_connection_flush(conn);
		state = 1;
	}

	static function clearError() {
		DBus.dbus_error_free(err);
		DBus.dbus_error_init(err);
	}

	static function readString(m:Ptr):Null<String>
		return Arena.scopedValue(a -> {
			var it = a.alloc(128), p:Ptr<Ptr> = a.alloc(8);
			if (DBus.dbus_message_iter_init(m, it) == 0 || DBus.dbus_message_iter_get_arg_type(it) != "s".code) null else {
				DBus.dbus_message_iter_get_basic(it, p);
				(cast p.value : CString).toString();
			}
		});

	// the messages that came: answered (each loop turn)
	public static function dispatch() {
		if (state != 1) return;
		DBus.dbus_connection_read_write(conn, 0);
		while (DBus.dbus_connection_dispatch(conn) == 0) {}
	}

	// the tree after a frame (a focus change emitted)
	public function update() {
		if (state != 1 || !asked) return;
		var t = ui.accessTree();
		var c = t.changes(tree);
		if (c.nodes.length > 0 || c.removed.length > 0) {
			parents.clear();
			for (id in t.order)
				for (k in t.nodes.get(id).children)
					parents.set(k, id);
		}
		var focusChanged = tree != null && tree.focus != t.focus;
		var was = tree == null ? 0 : tree.focus;
		var said = t.announcements(tree);
		tree = t;
		if (focusChanged) {
			if (was != 0 && t.nodes.exists(was)) stateChanged(was, "focused", false);
			if (t.focus != 0) stateChanged(t.focus, "focused", true);
		}
		for (s in said)
			announce(s.id, s.text, s.live);
		if (focusChanged || said.length > 0) DBus.dbus_connection_flush(conn);
	}

	// a live region's change: Object:Announcement, its text (detail1: the politeness, ATSPI_LIVE_POLITE or _ASSERTIVE)
	function announce(id:Int, text:String, live:hxmc.ui.access.Live)
		Arena.scoped(a -> {
			var s = DBus.dbus_message_new_signal(a.cstring(PREFIX + id), a.cstring("org.a11y.atspi.Event.Object"), a.cstring("Announcement"));
			var it = a.alloc(128), sub = a.alloc(128);
			DBus.dbus_message_iter_init_append(s, it);
			basicString(a, it, "s".code, "");
			basicInt(a, it, "i".code, live == Assertive ? 2 : 1);
			basicInt(a, it, "i".code, 0);
			DBus.dbus_message_iter_open_container(it, "v".code, a.cstring("s"), sub);
			basicString(a, sub, "s".code, text);
			DBus.dbus_message_iter_close_container(it, sub);
			DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("{sv}"), sub);
			DBus.dbus_message_iter_close_container(it, sub);
			DBus.dbus_connection_send(conn, s, Ptr.nil());
			DBus.dbus_message_unref(s);
		});

	function stateChanged(id:Int, name:String, on:Bool)
		Arena.scoped(a -> {
			var s = DBus.dbus_message_new_signal(a.cstring(PREFIX + id), a.cstring("org.a11y.atspi.Event.Object"), a.cstring("StateChanged"));
			var it = a.alloc(128), sub = a.alloc(128);
			DBus.dbus_message_iter_init_append(s, it);
			basicString(a, it, "s".code, name);
			basicInt(a, it, "i".code, on ? 1 : 0);
			basicInt(a, it, "i".code, 0);
			DBus.dbus_message_iter_open_container(it, "v".code, a.cstring("i"), sub);
			basicInt(a, sub, "i".code, 0);
			DBus.dbus_message_iter_close_container(it, sub);
			DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("{sv}"), sub);
			DBus.dbus_message_iter_close_container(it, sub);
			DBus.dbus_connection_send(conn, s, Ptr.nil());
			DBus.dbus_message_unref(s);
		});

	// --- marshalling ---

	static function basicString(a:Arena, it:Ptr, type:Int, s:String) {
		var p:Ptr<Ptr> = a.alloc(8);
		p.value = a.cstring(s);
		DBus.dbus_message_iter_append_basic(it, type, p);
	}

	static function basicInt(a:Arena, it:Ptr, type:Int, v:Int) {
		var p:Ptr<Int32> = a.alloc(8);
		p.value = v;
		DBus.dbus_message_iter_append_basic(it, type, p);
	}

	static function basicDouble(a:Arena, it:Ptr, v:Float) {
		var p:Ptr<Float> = a.alloc(8);
		p.value = v;
		DBus.dbus_message_iter_append_basic(it, "d".code, p);
	}

	// a reference: (bus name, object path)
	static function ref(a:Arena, it:Ptr, name:String, path:String) {
		var sub = a.alloc(128);
		DBus.dbus_message_iter_open_container(it, "r".code, Ptr.nil(), sub);
		basicString(a, sub, "s".code, name);
		basicString(a, sub, "o".code, path);
		DBus.dbus_message_iter_close_container(it, sub);
	}

	static inline function nullRef(a:Arena, it:Ptr)
		ref(a, it, "", "/org/a11y/atspi/null");

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

	function nodeRef(a:Arena, it:Ptr, id:Int)
		ref(a, it, unique, pathOf(id));

	static function appName():String
		return all.length > 0 ? all[0].window.title : "hxmc";

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
		2 => "alert", 7 => "check box", 11 => "combo box", 16 => "dialog", 23 => "frame", 27 => "image", 29 => "label", 31 => "list", 32 => "list item", 33 => "menu",
		35 => "menu item", 37 => "page tab", 38 => "page tab list", 39 => "panel", 42 => "progress bar", 43 => "push button", 44 => "radio button",
		49 => "scroll pane", 51 => "slider", 62 => "toggle button", 64 => "tool tip", 75 => "application", 79 => "entry", 83 => "heading", 88 => "link",
		98 => "list box", 99 => "grouping", 55 => "table", 56 => "table cell", 57 => "table column header", 90 => "table row", 65 => "tree",
		91 => "tree item", 50 => "separator", 52 => "spin button", 63 => "tool bar", 110 => "landmark"
	];

	function roleOf(id:Int):Int
		// (a password's: PASSWORD_TEXT)
		return id == tree.root ? 23 : tree.nodes.get(id).secret ? 40 : atspiRole(tree.nodes.get(id).role);

	function nameOf(id:Int):String
		return id == tree.root ? window.title : tree.nodes.get(id).name;

	static function hasAction(n:AccessNode):Bool
		return switch n.role {
			case Button | CheckBox | Switch | RadioButton | Tab | Link | MenuItem | ListBoxOption | ComboBox: true;
			case _: false;
		}

	function interfaces(n:Null<AccessNode>):Array<String> {
		if (n == null) return ["org.a11y.atspi.Accessible", "org.a11y.atspi.Application"];
		var out = ["org.a11y.atspi.Accessible", "org.a11y.atspi.Component"];
		if (hasAction(n)) out.push("org.a11y.atspi.Action");
		if (n.valueNow != null) out.push("org.a11y.atspi.Value");
		if (n.editable()) out.push("org.a11y.atspi.Text");
		return out;
	}

	// AT-SPI's state set: two 32-bit words
	function states(id:Int):Array<Int> {
		var n = tree.nodes.get(id), bits = [0, 0];
		inline function on(s:Int)
			bits[s >> 5] |= 1 << (s & 31);
		on(30); // VISIBLE
		on(25); // SHOWING
		if (id == tree.root) on(1); // ACTIVE
		if (!n.disabled) {
			on(8); // ENABLED
			on(24); // SENSITIVE
		}
		if (n.focusable) on(11); // FOCUSABLE
		if (tree.focus == id) on(12); // FOCUSED
		if (n.checked != null) {
			on(41); // CHECKABLE
			if (n.checked) on(4); // CHECKED
			if (n.mixed) on(32); // INDETERMINATE
		}
		if (n.selected != null) {
			on(22); // SELECTABLE
			if (n.selected) on(23); // SELECTED
		}
		if (n.multiselectable) on(16); // MULTISELECTABLE
		if (n.expanded != null) {
			on(9); // EXPANDABLE
			on(n.expanded ? 10 : 5); // EXPANDED, COLLAPSED
		}
		if (n.editable()) {
			on(7); // EDITABLE
			on(n.role == MultilineTextInput ? 17 : 26); // MULTI_LINE, SINGLE_LINE
		}
		return bits;
	}

	// a node's box in pixels: the screen's (coordinates 0) or the window's (1, 2)
	function extents(id:Int, coords:Int):Array<Int> {
		var n = tree.nodes.get(id);
		var k = ui.width > 0 ? window.surface.width / ui.width : 1.0;
		var ox = 0, oy = 0;
		if (coords == 0) {
			var d = window.surface.display;
			Arena.scoped(a -> {
				var x:Ptr<Int32> = a.alloc(4), y:Ptr<Int32> = a.alloc(4), child:Ptr<Int64> = a.alloc(8);
				if (hxmc.os.x11.Xlib.XTranslateCoordinates(d, window.surface.handle.toI64(), hxmc.os.x11.Xlib.XDefaultRootWindow(d), 0, 0, x, y, child) != 0) {
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

	// --- the messages ---

	@:hxmc.callback static function message(c:Ptr, m:Ptr, data:Ptr):Int {
		if (DBus.dbus_message_get_type(m) != 1) return 1; // (method calls only; else not handled)
		if (!asked) {
			asked = true;
			for (w in all)
				w.update();
		}
		inline function cs(p:Ptr):String
			return p.isNull() ? "" : (cast p : CString).toString();
		var path = cs(DBus.dbus_message_get_path(m)), iface = cs(DBus.dbus_message_get_interface(m)), member = cs(DBus.dbus_message_get_member(m));
		if (path == CACHE && member == "GetItems") {
			var r = DBus.dbus_message_new_method_return(m);
			Arena.scoped(a -> {
				var it = a.alloc(128), sub = a.alloc(128);
				DBus.dbus_message_iter_init_append(r, it);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("((so)(so)(so)iiassusau)"), sub);
				DBus.dbus_message_iter_close_container(it, sub);
			});
			DBus.dbus_connection_send(conn, r, Ptr.nil());
			DBus.dbus_message_unref(r);
			return 0;
		}
		var t = target(path);
		if (t == null) {
			error(m, "org.freedesktop.DBus.Error.UnknownObject", path);
			return 0;
		}
		var args = readArgs(m);
		var reply = DBus.dbus_message_new_method_return(m);
		var ok = Arena.scopedValue(a -> {
			var it = a.alloc(128);
			DBus.dbus_message_iter_init_append(reply, it);
			answer(a, it, t.a, t.id, iface, member, args);
		});
		if (ok) DBus.dbus_connection_send(conn, reply, Ptr.nil()) else error(m, "org.freedesktop.DBus.Error.UnknownMethod", iface + "." + member);
		DBus.dbus_message_unref(reply);
		return 0;
	}

	static function error(m:Ptr, name:String, text:String)
		Arena.scoped(a -> {
			var e = DBus.dbus_message_new_error(m, a.cstring(name), a.cstring(text));
			DBus.dbus_connection_send(conn, e, Ptr.nil());
			DBus.dbus_message_unref(e);
		});

	// a call's arguments: strings, numbers (as Dynamic)
	static function readArgs(m:Ptr):Array<Dynamic>
		return Arena.scopedValue(a -> {
			var out:Array<Dynamic> = [];
			var it = a.alloc(128), v:Ptr = a.alloc(8);
			if (DBus.dbus_message_iter_init(m, it) != 0)
				do {
					var type = DBus.dbus_message_iter_get_arg_type(it);
					(v : Ptr<Int64>).value = 0;
					if (type == "s".code || type == "o".code || type == "i".code || type == "u".code || type == "d".code || type == "b".code)
						DBus.dbus_message_iter_get_basic(it, v);
					var value:Dynamic = null;
					if (type == "s".code || type == "o".code) {
						var p:Ptr<Ptr> = v;
						var text:String = (cast p.value : CString).toString();
						value = text;
					} else if (type == "i".code || type == "b".code || type == "u".code) {
						var p:Ptr<Int32> = v;
						var i:Int = p.value;
						value = i;
					} else if (type == "d".code) {
						var p:Ptr<Float> = v;
						var d:Float = p.value;
						value = d;
					}
					out.push(value);
				} while (DBus.dbus_message_iter_next(it) != 0);
			out;
		});

	// the answer's values appended: false when the method is not one of ours
	static function answer(a:Arena, it:Ptr, w:Null<LinuxAccess>, id:Int, iface:String, member:String, args:Array<Dynamic>):Bool {
		if (iface == "org.freedesktop.DBus.Properties") {
			if (member == "Get") return property(a, it, w, id, args[0], args[1]);
			if (member == "GetAll") {
				var sub = a.alloc(128), entry = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("{sv}"), sub);
				for (p in propertyNames(w, id, args[0])) {
					DBus.dbus_message_iter_open_container(sub, "e".code, Ptr.nil(), entry);
					basicString(a, entry, "s".code, p);
					property(a, entry, w, id, args[0], p);
					DBus.dbus_message_iter_close_container(sub, entry);
				}
				DBus.dbus_message_iter_close_container(it, sub);
				return true;
			}
			return false;
		}
		if (iface == "org.freedesktop.DBus.Introspectable" && member == "Introspect") {
			basicString(a, it, "s".code, "<node/>");
			return true;
		}
		if (w == null) return application(a, it, iface, member, args);
		var n = w.tree.nodes.get(id);
		switch [iface, member] {
			case ["org.a11y.atspi.Accessible", "GetChildren"]:
				var sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("(so)"), sub);
				for (k in n.children)
					w.nodeRef(a, sub, k);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Accessible", "GetChildAtIndex"]:
				var i:Int = args[0];
				if (i >= 0 && i < n.children.length) w.nodeRef(a, it, n.children[i]) else nullRef(a, it);
			case ["org.a11y.atspi.Accessible", "GetIndexInParent"]:
				var p = w.parents.get(id);
				basicInt(a, it, "i".code, id == w.tree.root ? all.indexOf(w) : p == null ? -1 : w.tree.nodes.get(p).children.indexOf(id));
			case ["org.a11y.atspi.Accessible", "GetRole"]:
				basicInt(a, it, "u".code, w.roleOf(id));
			case ["org.a11y.atspi.Accessible", "GetRoleName" | "GetLocalizedRoleName"]:
				basicString(a, it, "s".code, ROLE_NAMES.get(w.roleOf(id)) ?? "unknown");
			case ["org.a11y.atspi.Accessible", "GetState"]:
				var sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("u"), sub);
				for (b in w.states(id))
					basicInt(a, sub, "u".code, b);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Accessible", "GetAttributes"]:
				// (a live region: live and container-live, as Chromium gives them; a landmark's kind, the current one of a set)
				var sub = a.alloc(128), entry = a.alloc(128), live = n == null ? null : n.live.aria();
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("{ss}"), sub);
				var pairs = [];
				if (n != null && n.role == Navigation) pairs.push(["xml-roles", "navigation"]);
				if (n != null && n.current) pairs.push(["current", "page"]);
				for (p in pairs) {
					DBus.dbus_message_iter_open_container(sub, "e".code, Ptr.nil(), entry);
					basicString(a, entry, "s".code, p[0]);
					basicString(a, entry, "s".code, p[1]);
					DBus.dbus_message_iter_close_container(sub, entry);
				}
				if (live != null)
					for (k in ["live", "container-live"]) {
						DBus.dbus_message_iter_open_container(sub, "e".code, Ptr.nil(), entry);
						basicString(a, entry, "s".code, k);
						basicString(a, entry, "s".code, live);
						DBus.dbus_message_iter_close_container(sub, entry);
					}
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Accessible", "GetRelationSet"]:
				var sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("(ua(so))"), sub);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Accessible", "GetApplication"]:
				ref(a, it, unique, ROOT);
			case ["org.a11y.atspi.Accessible", "GetInterfaces"]:
				var sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("s"), sub);
				for (s in w.interfaces(n))
					basicString(a, sub, "s".code, s);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Component", "GetExtents"]:
				var e = w.extents(id, args[0]), sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "r".code, Ptr.nil(), sub);
				for (v in e)
					basicInt(a, sub, "i".code, v);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Component", "GetPosition"]:
				var e = w.extents(id, args[0]), sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "r".code, Ptr.nil(), sub);
				basicInt(a, sub, "i".code, e[0]);
				basicInt(a, sub, "i".code, e[1]);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Component", "GetSize"]:
				var e = w.extents(id, 1), sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "r".code, Ptr.nil(), sub);
				basicInt(a, sub, "i".code, e[2]);
				basicInt(a, sub, "i".code, e[3]);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Component", "Contains"]:
				var e = w.extents(id, args[2]), x:Int = args[0], y:Int = args[1];
				basicInt(a, it, "b".code, x >= e[0] && y >= e[1] && x < e[0] + e[2] && y < e[1] + e[3] ? 1 : 0);
			case ["org.a11y.atspi.Component", "GetAccessibleAtPoint"]:
				w.nodeRef(a, it, w.at(args[0], args[1], args[2]));
			case ["org.a11y.atspi.Component", "GetLayer"]:
				basicInt(a, it, "u".code, id == w.tree.root ? 7 : 3); // WINDOW, WIDGET
			case ["org.a11y.atspi.Component", "GetMDIZOrder"]:
				var p:Ptr<Int32> = a.alloc(8);
				p.value = 0;
				DBus.dbus_message_iter_append_basic(it, "n".code, p);
			case ["org.a11y.atspi.Component", "GrabFocus"]:
				basicInt(a, it, "b".code, w.ui.accessAction(id, Focus) ? 1 : 0);
			case ["org.a11y.atspi.Component", "GetAlpha"]:
				basicDouble(a, it, 1);
			case ["org.a11y.atspi.Action", "GetActions"]:
				var sub = a.alloc(128), s = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("(sss)"), sub);
				if (hasAction(n)) {
					DBus.dbus_message_iter_open_container(sub, "r".code, Ptr.nil(), s);
					basicString(a, s, "s".code, "click");
					basicString(a, s, "s".code, "");
					basicString(a, s, "s".code, "");
					DBus.dbus_message_iter_close_container(sub, s);
				}
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Action", "GetName" | "GetLocalizedName"]:
				basicString(a, it, "s".code, "click");
			case ["org.a11y.atspi.Action", "GetDescription" | "GetKeyBinding"]:
				basicString(a, it, "s".code, "");
			case ["org.a11y.atspi.Action", "DoAction"]:
				basicInt(a, it, "b".code, w.ui.accessAction(id, Click) ? 1 : 0);
			case ["org.a11y.atspi.Text", "GetText"]:
				var s = n.value ?? "", from:Int = args[0], to:Int = args[1];
				if (to < 0 || to > s.length) to = s.length;
				basicString(a, it, "s".code, from >= 0 && from < to ? s.substring(from, to) : "");
			case _:
				return false;
		}
		return true;
	}

	static function application(a:Arena, it:Ptr, iface:String, member:String, args:Array<Dynamic>):Bool {
		var fs = frames();
		switch [iface, member] {
			case ["org.a11y.atspi.Accessible", "GetChildren"]:
				var sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("(so)"), sub);
				for (f in fs)
					ref(a, sub, unique, pathOf(f.id));
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Accessible", "GetChildAtIndex"]:
				var i:Int = args[0];
				if (i >= 0 && i < fs.length) ref(a, it, unique, pathOf(fs[i].id)) else nullRef(a, it);
			case ["org.a11y.atspi.Accessible", "GetIndexInParent"]:
				basicInt(a, it, "i".code, -1);
			case ["org.a11y.atspi.Accessible", "GetRole"]:
				basicInt(a, it, "u".code, 75);
			case ["org.a11y.atspi.Accessible", "GetRoleName" | "GetLocalizedRoleName"]:
				basicString(a, it, "s".code, "application");
			case ["org.a11y.atspi.Accessible", "GetState"]:
				var sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("u"), sub);
				basicInt(a, sub, "u".code, 0);
				basicInt(a, sub, "u".code, 0);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Accessible", "GetAttributes"]:
				var sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("{ss}"), sub);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Accessible", "GetRelationSet"]:
				var sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("(ua(so))"), sub);
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Accessible", "GetApplication"]:
				ref(a, it, unique, ROOT);
			case ["org.a11y.atspi.Accessible", "GetInterfaces"]:
				var sub = a.alloc(128);
				DBus.dbus_message_iter_open_container(it, "a".code, a.cstring("s"), sub);
				basicString(a, sub, "s".code, "org.a11y.atspi.Accessible");
				basicString(a, sub, "s".code, "org.a11y.atspi.Application");
				DBus.dbus_message_iter_close_container(it, sub);
			case ["org.a11y.atspi.Application", "GetLocale"]:
				basicString(a, it, "s".code, "C");
			case _:
				return false;
		}
		return true;
	}

	static function propertyNames(w:Null<LinuxAccess>, id:Int, iface:String):Array<String>
		return switch iface {
			case "org.a11y.atspi.Accessible": ["Name", "Description", "Parent", "ChildCount", "Locale", "AccessibleId"];
			case "org.a11y.atspi.Application": ["ToolkitName", "Version", "AtspiVersion", "Id"];
			case "org.a11y.atspi.Action": ["NActions"];
			case "org.a11y.atspi.Value": ["MinimumValue", "MaximumValue", "MinimumIncrement", "CurrentValue", "Text"];
			case "org.a11y.atspi.Text": ["CharacterCount", "CaretOffset"];
			case _: [];
		}

	static var appId = 0;

	// a property's value (a variant): false when there is none
	static function property(a:Arena, it:Ptr, w:Null<LinuxAccess>, id:Int, iface:String, name:String):Bool {
		var v = a.alloc(128);
		inline function open(sig:String)
			DBus.dbus_message_iter_open_container(it, "v".code, a.cstring(sig), v);
		inline function close()
			DBus.dbus_message_iter_close_container(it, v);
		var n = w == null ? null : w.tree.nodes.get(id);
		switch [iface, name] {
			case ["org.a11y.atspi.Accessible", "Name"]:
				open("s");
				basicString(a, v, "s".code, w == null ? appName() : w.nameOf(id));
			case ["org.a11y.atspi.Accessible", "Description"]:
				open("s");
				basicString(a, v, "s".code, n == null ? "" : n.description ?? "");
			case ["org.a11y.atspi.Accessible", "Parent"]:
				open("(so)");
				if (w == null) ref(a, v, "org.a11y.atspi.Registry", ROOT) else if (id == w.tree.root) ref(a, v, unique, ROOT) else
					ref(a, v, unique, pathOf(w.parents.get(id) ?? w.tree.root));
			case ["org.a11y.atspi.Accessible", "ChildCount"]:
				open("i");
				basicInt(a, v, "i".code, w == null ? frames().length : n.children.length);
			case ["org.a11y.atspi.Accessible", "Locale"]:
				open("s");
				basicString(a, v, "s".code, "C");
			case ["org.a11y.atspi.Accessible", "AccessibleId"]:
				open("s");
				basicString(a, v, "s".code, w == null ? "" : "hxmc-" + id);
			case ["org.a11y.atspi.Application", "ToolkitName"]:
				open("s");
				basicString(a, v, "s".code, "hxmc");
			case ["org.a11y.atspi.Application", "Version"]:
				open("s");
				basicString(a, v, "s".code, "1");
			case ["org.a11y.atspi.Application", "AtspiVersion"]:
				open("s");
				basicString(a, v, "s".code, "2.1");
			case ["org.a11y.atspi.Application", "Id"]:
				open("i");
				basicInt(a, v, "i".code, appId);
			case ["org.a11y.atspi.Action", "NActions"] if (n != null):
				open("i");
				basicInt(a, v, "i".code, hasAction(n) ? 1 : 0);
			case ["org.a11y.atspi.Value", "MinimumValue" | "MaximumValue" | "MinimumIncrement" | "CurrentValue"] if (n != null && n.valueNow != null):
				open("d");
				var lo = n.valueMin ?? 0.0, hi = n.valueMax ?? 1.0;
				basicDouble(a, v, switch name {
					case "MinimumValue": lo;
					case "MaximumValue": hi;
					case "MinimumIncrement": (hi - lo) / 20;
					case _: n.valueNow;
				});
			case ["org.a11y.atspi.Value", "Text"] if (n != null):
				open("s");
				basicString(a, v, "s".code, n.valueText ?? "");
			case ["org.a11y.atspi.Text", "CharacterCount"] if (n != null):
				open("i");
				basicInt(a, v, "i".code, (n.value ?? "").length);
			case ["org.a11y.atspi.Text", "CaretOffset"] if (n != null):
				open("i");
				basicInt(a, v, "i".code, (n.value ?? "").length);
			case _:
				return false;
		}
		close();
		return true;
	}
}

// libdbus, loaded at run time (dlopen): the calls that may dispatch, block
// or call back are @:wait (in a safe region)
@:build(hxmc.gfx.gl.Loader.build())
class DBus {
	static function dbus_error_init(e:Ptr):Void;
	static function dbus_error_free(e:Ptr):Void;
	@:wait static function dbus_bus_get_private(type:Int, e:Ptr):Ptr;
	@:wait static function dbus_connection_open_private(address:Ptr, e:Ptr):Ptr;
	@:wait static function dbus_bus_register(c:Ptr, e:Ptr):Int;
	static function dbus_bus_get_unique_name(c:Ptr):Ptr;
	static function dbus_connection_set_exit_on_disconnect(c:Ptr, exit:Int):Void;
	@:wait static function dbus_connection_close(c:Ptr):Void;
	static function dbus_connection_unref(c:Ptr):Void;
	@:wait static function dbus_connection_register_fallback(c:Ptr, path:Ptr, vtable:Ptr, data:Ptr):Int;
	@:wait static function dbus_connection_send_with_reply_and_block(c:Ptr, m:Ptr, timeout:Int, e:Ptr):Ptr;
	@:wait static function dbus_connection_send(c:Ptr, m:Ptr, serial:Ptr):Int;
	@:wait static function dbus_connection_flush(c:Ptr):Void;
	@:wait static function dbus_connection_read_write(c:Ptr, timeout:Int):Int;
	@:wait static function dbus_connection_dispatch(c:Ptr):Int;
	static function dbus_message_new_method_call(dest:Ptr, path:Ptr, iface:Ptr, method:Ptr):Ptr;
	static function dbus_message_new_method_return(m:Ptr):Ptr;
	static function dbus_message_new_error(m:Ptr, name:Ptr, text:Ptr):Ptr;
	static function dbus_message_new_signal(path:Ptr, iface:Ptr, name:Ptr):Ptr;
	static function dbus_message_unref(m:Ptr):Void;
	static function dbus_message_get_type(m:Ptr):Int;
	static function dbus_message_get_path(m:Ptr):Ptr;
	static function dbus_message_get_interface(m:Ptr):Ptr;
	static function dbus_message_get_member(m:Ptr):Ptr;
	static function dbus_message_iter_init(m:Ptr, it:Ptr):Int;
	static function dbus_message_iter_get_arg_type(it:Ptr):Int;
	static function dbus_message_iter_get_basic(it:Ptr, value:Ptr):Void;
	static function dbus_message_iter_next(it:Ptr):Int;
	static function dbus_message_iter_init_append(m:Ptr, it:Ptr):Void;
	static function dbus_message_iter_append_basic(it:Ptr, type:Int, value:Ptr):Int;
	static function dbus_message_iter_open_container(it:Ptr, type:Int, signature:Ptr, sub:Ptr):Int;
	static function dbus_message_iter_close_container(it:Ptr, sub:Ptr):Int;
}
