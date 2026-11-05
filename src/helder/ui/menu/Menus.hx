package helder.ui.menu;

import helder.ui.Node;
import helder.ui.PlatformMenuItem;
import helder.ui.Shortcut;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;
import helder.ui.menu.Menu;

// Menus of the model (Menu, MenuItem) shown: the platform's own where
// Ui.hostOf says native for "context-menu" and "menubar" and the window
// has them (Ui.platform: macOS's NSMenu, Windows' HMENU), else helder's
// (DrawnMenu, MenuBar's drawn bar: Linux). A chosen item dispatches its
// action from the node the menu is for (a context menu's, else the focus).
class Menus {
	// what roles' labels name ("About Viewer", "Quit Viewer")
	public static var appName = "helder";

	// the items as the platform's menus take them: labels, the keymap's
	// shortcut for each action (its first binding where the context stack
	// of from is), enabled and checked from Ui.actionState; ids index actions
	public static function resolve(ui:Ui, items:Array<MenuItem>, from:Null<Node>, actions:Array<EnumValue>):Array<PlatformMenuItem> {
		var stack = ui.contextStack(from);
		var out:Array<PlatformMenuItem> = [];
		for (it in items)
			switch it {
				case Separator:
					// (none first, last or twice)
					if (out.length > 0 && out[out.length - 1].separator != true) out.push({id: -1, label: "", separator: true});
				case Submenu(label, sub):
					out.push({id: -1, label: label, items: resolve(ui, sub, from, actions)});
				case Item(label, action):
					out.push(item(ui, label, action, stack, from, actions, null));
				case Role(role, label):
					var a = role.action();
					if (a != null) out.push(item(ui, label ?? role.label(appName), a, stack, from, actions, role));
			}
		if (out.length > 0 && out[out.length - 1].separator == true) out.pop();
		return out;
	}

	static function item(ui:Ui, label:String, action:EnumValue, stack:Array<helder.ui.actions.KeyContext>, from:Null<Node>,
			actions:Array<EnumValue>, role:Null<MenuRole>):PlatformMenuItem {
		var id = actions.length;
		actions.push(action);
		var state = ui.actionState(action, from);
		var keys = ui.keymap.keysFor(action, stack);
		var shortcut = keys.length == 0 ? null : [for (k in keys[0]) k.label()].join(" ");
		var single = keys.length > 0 && keys[0].length == 1 ? new Shortcut(keys[0][0].key, keys[0][0].held(), false) : null;
		// (macOS's editing roles: its text editors' own copy: and paste: first, enabled)
		var edit = Keymap.mac && role != null && [Undo, Redo, Cut, Copy, Paste, SelectAll].contains(role);
		var r:PlatformMenuItem = {id: id, label: label, disabled: !edit && !state.enabled};
		if (shortcut != null) r.shortcut = shortcut;
		if (single != null) r.keys = single;
		if (state == Checked || state == Unchecked) r.checked = state == Checked;
		if (role != null) r.role = role;
		return r;
	}

	// a context menu at x, y (window layout pixels) for from (its actions
	// dispatched from there; default: the focus)
	public static function popup(ui:Ui, items:Array<MenuItem>, x:Float, y:Float, ?from:Node) {
		var actions = [];
		var resolved = resolve(ui, items, from, actions);
		var done = (id:Int) -> if (id >= 0 && id < actions.length) ui.dispatchAction(actions[id], from != null && from.ui == ui ? from : null);
		var at = from ?? ui.focus ?? ui.root;
		if (ui.hostOf(at, "context-menu") == Native && ui.platform.menu(resolved, x, y, done)) return;
		DrawnMenu.open(ui, resolved, x, y, null, done);
	}
}

// A window's menu bar from the model: the platform's (macOS's, the
// system's at the top of the screen; Windows', the window's) where
// Ui.hostOf(root, "menubar") is native and the platform has one, else a
// drawn row of the menus' titles (node: put it at the top of the window's
// content; markup's <MenuBarView menus={...}/> does). The platform's is
// set again whenever its labels or states change (checked before each
// update); a drawn one's menus are resolved as they open: Alt or F10 opens
// the first, Left and Right move along the bar, a hover moves while one is open.
class MenuBar {
	public final ui:Ui;
	public var menus(default, null):Array<Menu>;
	// the drawn bar (hidden while the platform's is used)
	public final node:Node;
	public var native(default, null) = false;
	var signature = "";
	var epoch = -1;
	var keymapVersion = -1;
	var checked = 0.0;
	var actions:Array<EnumValue> = [];
	var open:Null<DrawnMenu> = null;
	var openIndex = -1;
	final titles:Array<Node> = [];
	final refresh:Void->Void;
	var removeKey:Void->Void;

	public function new(ui:Ui, menus:Array<Menu>) {
		this.ui = ui;
		this.menus = menus;
		node = new Node("menubar");
		node.semantics = {role: helder.ui.access.Role.MenuBar};
		refresh = update;
		build();
		ui.beforeUpdate.push(refresh);
		removeKey = ui.shortcut("F10", () -> if (!native && menus.length > 0) show(0));
		update();
	}

	public function setMenus(menus:Array<Menu>) {
		this.menus = menus;
		signature = "";
		epoch = -1;
		build();
		update();
	}

	public function dispose() {
		ui.beforeUpdate.remove(refresh);
		removeKey();
		if (native) ui.platform.menuBar([], _ -> {});
		if (open != null) open.close(true);
	}

	// (the platform's bar set when its items changed)
	function update() {
		var host = ui.hostOf(ui.root, "menubar") == Native;
		if (!host) {
			if (native) {
				ui.platform.menuBar([], _ -> {});
				native = false;
				node.style.display = Flex;
			}
			return;
		}
		// (checked again after input, a keymap's change, else each second: nothing made in a frame that changed none)
		var now = haxe.Timer.stamp();
		if (native && ui.inputEpoch == epoch && ui.keymap.version == keymapVersion && now - checked < 1) return;
		epoch = ui.inputEpoch;
		keymapVersion = ui.keymap.version;
		checked = now;
		var a:Array<EnumValue> = [];
		var top:Array<PlatformMenuItem> = [for (m in menus) {
			var r:PlatformMenuItem = {id: -1, label: m.label, items: Menus.resolve(ui, m.items, null, a)};
			if (m.role != null) r.role = m.role;
			r;
		}];
		var s = sign(top);
		if (s == signature && native) return;
		signature = s;
		actions = a;
		if (ui.platform.menuBar(top, id -> if (id >= 0 && id < actions.length) ui.dispatchAction(actions[id]))) {
			native = true;
			node.style.display = None;
		} else {
			native = false;
			node.style.display = Flex;
		}
	}

	static function sign(items:Array<PlatformMenuItem>):String {
		var b = new StringBuf();
		for (it in items) {
			b.add(it.id + "|" + it.label + "|" + it.shortcut + "|" + it.disabled + "|" + it.checked + "|" + it.separator + "|" + it.role);
			if (it.items != null) b.add("[" + sign(it.items) + "]");
			b.add(";");
		}
		return b.toString();
	}

	function build() {
		node.removeChildren();
		titles.resize(0);
		var dark = ui.dark;
		node.style.set({
			direction: Row,
			alignItems: Center,
			height: 28,
			padding: [0.0, 4, 0, 4],
			columnGap: 2,
			background: dark ? 0xFF202023 : 0xFFF4F4F5,
			color: dark ? 0xFFE4E4E7 : 0xFF18181B,
			fontSize: 13,
			borders: [0.0, 0, 1, 0],
			borderColor: dark ? 0xFF2E2E33 : 0xFFE4E4E7,
			shrink: 0
		});
		for (i in 0...menus.length) {
			var t = new Node("menubar-item");
			t.style.set({padding: [3.0, 9, 3, 9], radius: 4, cursor: helder.ui.Cursor.Default});
			t.semantics = {role: helder.ui.access.Role.MenuItem, label: menus[i].label, expanded: false};
			t.append(new TextNode(menus[i].label, "menubar-label"));
			var index = i;
			t.onPointerDown = e -> {
				// (the focus left in the menu, not taken by the press)
				e.preventDefault();
				e.stop();
				if (openIndex == index) close() else show(index, false);
			};
			t.onPointerEnter = _ -> if (open != null && openIndex != index) show(index, false);
			node.append(t);
			titles.push(t);
		}
		node.onKeyDown = null;
	}

	// opens menu i under its title (focus: its first row highlighted)
	public function show(i:Int, focus = true) {
		if (open != null) {
			var o = open;
			open = null;
			o.close(false, true);
		}
		mark(openIndex, false);
		openIndex = i;
		mark(i, true);
		var a = [];
		var items = Menus.resolve(ui, menus[i].items, null, a);
		var from = ui.focus;
		var m = DrawnMenu.open(ui, items, 0, 0, titles[i], id -> {
			if (id >= 0 && id < a.length) ui.dispatchAction(a[id], from != null && from.ui == ui ? from : null);
		});
		m.onSideways = d -> {
			open = null;
			show((i + d + menus.length) % menus.length);
		};
		m.onClosed = () -> if (open == m) {
			open = null;
			mark(openIndex, false);
			openIndex = -1;
		};
		open = m;
	}

	public function close() {
		if (open != null) open.close(false);
	}

	public var current(get, never):Null<DrawnMenu>;

	inline function get_current()
		return open;

	function mark(i:Int, on:Bool) {
		if (i < 0 || i >= titles.length) return;
		titles[i].style.background = on ? (ui.dark ? 0xFF3F3F46 : 0xFFE4E4E7) : 0;
		if (titles[i].semantics != null) titles[i].semantics.expanded = on;
		ui.requestFrame();
	}
}

// <MenuBarView menus={...}/> (UiFlow): the window's menu bar (MenuBar) while it is
// mounted; where the platform's is used, an empty node in its place
class MenuBarMount implements helder.view.Flow.Mountable<Node> {
	final menus:Array<Menu>;
	final ref:Null<MenuBar->Void>;

	public function new(props:{menus:Array<Menu>, ?ref:MenuBar->Void}) {
		this.menus = props.menus;
		this.ref = props.ref;
	}

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var box = new Node("menubar-box");
		box.style.shrink = 0;
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(box, i < 0 ? parent.children.length : i);
		var bar:Null<MenuBar> = null;
		helder.view.graph.Graph.onSettled(() -> {
			if (box.ui == null) return;
			bar = new MenuBar(box.ui, menus);
			box.append(bar.node);
			if (ref != null) ref(bar);
		});
		helder.view.graph.Graph.onCleanup(() -> if (bar != null) bar.dispose());
		return [box];
	}
}
