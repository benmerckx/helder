package helder.ui.menu;

import helder.ui.Key;
import helder.ui.Node;
import helder.ui.PlatformMenuItem;
import helder.ui.Popup;
import helder.ui.TextNode;
import helder.ui.Ui;

// helder's own menus, where the platform has none it can be trusted with
// (Linux): a popup of rows (a label, a check mark, the shortcut at the
// right, a submenu's arrow), separators; drawn in the window's light or
// dark colours, loosely as GTK's. The keyboard: Up and Down (wrapping,
// past separators and disabled rows), Home, End, Right a submenu (Left
// back; from the bar: the next or previous menu), Enter or Space chooses,
// Escape closes the innermost; a letter the next row it begins. The
// pointer: hover highlights (a submenu opened under it), a click chooses,
// a press outside closes them all. The focus is in the menu while it is
// open and goes back where it was when it closes (Popup's returnFocus).
class DrawnMenu {
	public final popup:Popup;
	public final ui:Ui;
	final items:Array<PlatformMenuItem>;
	final rows:Array<Null<Node>> = [];
	final chosen:Int->Void;
	// the menu it is a submenu of, its open submenu
	public var parent(default, null):Null<DrawnMenu> = null;
	var child:Null<DrawnMenu> = null;
	var active = -1;
	// (from a menu bar: Left and Right move along it)
	public var onSideways:Null<Int->Void> = null;
	public var onClosed:Null<Void->Void> = null;
	var closed = false;

	// (the most recent root menu open, for tests)
	public static var current(default, null):Null<DrawnMenu> = null;

	// opens items at x, y (Point) or anchored below (or right of, a submenu) anchor; chosen
	// gets the item's id, or -1 when the menu closes without a choice
	public static function open(ui:Ui, items:Array<PlatformMenuItem>, x:Float, y:Float, ?anchor:Node, chosen:Int->Void):DrawnMenu {
		var m = new DrawnMenu(ui, items, chosen);
		if (anchor != null) {
			m.popup.anchor = anchor;
			m.popup.placement = Below;
			m.popup.gap = 0;
		} else {
			m.popup.placement = Point;
			m.popup.atX = x;
			m.popup.atY = y;
		}
		ui.open(m.popup);
		m.move(1, -1);
		current = m;
		return m;
	}

	function new(ui:Ui, items:Array<PlatformMenuItem>, chosen:Int->Void) {
		this.ui = ui;
		this.items = items;
		this.chosen = chosen;
		var dark = ui.dark;
		popup = new Popup("menu");
		popup.style.set({
			padding: 4,
			radius: 6,
			minWidth: 180,
			background: dark ? 0xFF2B2B2F : 0xFFFFFFFF,
			borderWidth: 1,
			borderColor: dark ? 0xFF3F3F46 : 0xFFD4D4D8,
			color: dark ? 0xFFE4E4E7 : 0xFF18181B,
			fontSize: 13
		});
		popup.style.shadow = helder.ui.Shadow.parse("0 4px 16px rgba(0, 0, 0, 0.35)");
		popup.semantics = {role: helder.ui.access.Role.Menu};
		popup.onDismiss = () -> close(false);
		popup.onKeyDown = key;
		for (i in 0...items.length) {
			var it = items[i];
			if (it.separator == true) {
				var s = new Node("menu-separator");
				s.style.set({height: 1, margin: [4.0, 6, 4, 6], background: dark ? 0xFF3F3F46 : 0xFFE4E4E7});
				popup.append(s);
				rows.push(null);
				continue;
			}
			var row = new Node("menu-item");
			row.style.set({
				direction: Row,
				alignItems: Center,
				height: 26,
				padding: [0.0, 10, 0, 6],
				radius: 4,
				columnGap: 8,
				cursor: helder.ui.Cursor.Default
			});
			row.focusable = true;
			row.semantics = {
				role: it.checked != null ? helder.ui.access.Role.MenuItemCheckBox : helder.ui.access.Role.MenuItem,
				label: it.label,
				disabled: it.disabled == true,
				checked: it.checked == true ? true : null,
				expanded: it.items != null ? false : null
			};
			var check = new TextNode(it.checked == true ? "✓" : "", "menu-check");
			check.style.set({width: 14});
			var label = new TextNode(it.label, "menu-label");
			label.style.set({grow: 1, maxLines: 1});
			var keys = new TextNode(it.items != null ? "›" : it.shortcut ?? "", "menu-keys");
			keys.style.set({color: dark ? 0xFFA1A1AA : 0xFF71717A, marginLeft: 16});
			if (it.disabled == true) row.style.opacity = 0.45;
			row.append(check);
			row.append(label);
			row.append(keys);
			var index = i;
			row.onPointerEnter = _ -> highlight(index, true);
			row.onClick = e -> {
				e.stop();
				activate(index);
			};
			popup.append(row);
			rows.push(row);
		}
	}

	// highlights row i (open: a submenu opened), the focus there
	function highlight(i:Int, open:Bool) {
		if (i == active && (child != null || !open)) return;
		if (active >= 0 && rows[active] != null) rows[active].style.background = 0;
		active = i;
		var row = rows[i];
		if (row == null) return;
		row.style.background = ui.dark ? 0xFF3F3F46 : 0xFFE4E4E7;
		if (child != null && child.anchorRow != row) {
			if (child.anchorRow.semantics != null) child.anchorRow.semantics.expanded = false;
			child.close(false, true);
			child = null;
		}
		ui.setFocus(row, false);
		if (open && items[i].items != null && items[i].disabled != true && child == null) openChild(i, false);
		ui.requestFrame();
	}

	var anchorRow:Null<Node> = null;

	function openChild(i:Int, focusIt:Bool) {
		var sub = new DrawnMenu(ui, items[i].items, chosen);
		sub.parent = this;
		sub.anchorRow = rows[i];
		sub.popup.anchor = rows[i];
		sub.popup.placement = Right;
		sub.popup.gap = 2;
		child = sub;
		ui.open(sub.popup);
		if (rows[i].semantics != null) rows[i].semantics.expanded = true;
		if (focusIt) sub.move(1, -1) else ui.setFocus(rows[i], false);
	}

	// the next selectable row from `from` (dir 1 or -1)
	function move(dir:Int, from:Int) {
		var n = rows.length;
		if (n == 0) return;
		var i = from;
		for (_ in 0...n) {
			i = (i + dir + n) % n;
			if (rows[i] != null && items[i].disabled != true) {
				highlight(i, false);
				return;
			}
		}
	}

	function activate(i:Int) {
		var it = items[i];
		if (it.disabled == true || it.separator == true) return;
		if (it.items != null) {
			if (child == null) openChild(i, true) else child.move(1, -1);
			return;
		}
		root().closeAll(it.id);
	}

	function root():DrawnMenu {
		var m = this;
		while (m.parent != null)
			m = m.parent;
		return m;
	}

	// closes it and its submenus; chosen told (the root's: id or -1)
	function closeAll(id:Int) {
		close(true, true);
		chosen(id);
		if (onClosed != null) onClosed();
	}

	// closes it (all: and the menus it is a submenu of, else only it and its submenus)
	public function close(all:Bool, quiet = false) {
		if (closed) return;
		closed = true;
		if (child != null) child.close(false, true);
		child = null;
		ui.close(popup);
		if (parent != null) {
			if (parent.child == this) parent.child = null;
			if (all) parent.close(true, quiet) else ui.setFocus(anchorRow, false);
		} else if (!quiet) {
			if (current == this) current = null;
			chosen(-1);
			if (onClosed != null) onClosed();
		}
		if (current == this) current = null;
	}

	public var isOpen(get, never):Bool;

	inline function get_isOpen()
		return !closed;

	// the keys while its rows have the focus
	function key(e:helder.ui.Event) {
		// (only the innermost menu's: the focus is there)
		if (child != null && !child.closed) return;
		var taken = true;
		switch e.key {
			case Key.DOWN: move(1, active);
			case Key.UP: move(-1, active < 0 ? 0 : active);
			case Key.HOME: move(1, -1);
			case Key.END: move(-1, 0);
			case Key.RIGHT:
				if (active >= 0 && items[active].items != null && items[active].disabled != true) openChild(active, true) else if (root().onSideways != null) {
					var r = root();
					r.close(false, true);
					r.onSideways(1);
				}
			case Key.LEFT:
				if (parent != null) close(false, true) else if (onSideways != null) {
					close(false, true);
					onSideways(-1);
				}
			case Key.ENTER | Key.SPACE:
				if (active >= 0) activate(active);
			case Key.ESCAPE:
				if (parent != null) close(false, true) else close(false);
			case Key.TAB: close(true);
			case k if (k > 32 && k < 127 && e.mods & (Key.MOD_CONTROL | Key.MOD_META | Key.MOD_ALT) == 0):
				// (the next row whose label begins with it)
				var c = String.fromCharCode(k).toLowerCase(), n = rows.length;
				for (d in 1...n + 1) {
					var i = ((active < 0 ? -1 : active) + d) % n;
					if (rows[i] != null && items[i].disabled != true && items[i].label.toLowerCase().charAt(0) == c) {
						highlight(i, false);
						break;
					}
				}
			case _: taken = false;
		}
		if (taken) {
			e.preventDefault();
			e.stop();
		}
	}

	// (tests: the rows' labels, the highlighted one, choosing it)
	public function labels():Array<String>
		return [for (it in items) it.separator == true ? "-" : it.label];

	public var highlighted(get, never):Int;

	inline function get_highlighted()
		return active;

	public var submenu(get, never):Null<DrawnMenu>;

	inline function get_submenu()
		return child;
}
