package helder.ui.menu;

import helder.test.Test;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.platform.PlatformMenuItem;
import helder.ui.Ui;
import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;
import helder.ui.menu.Menu;
import helder.ui.menu.Menus;

// helder.ui.menu: the model resolved (the keymap's shortcuts, the handlers'
// states, separators, submenus, roles), a context menu drawn and driven by
// the keyboard and the pointer, a drawn menu bar (Right along it, a hover
// moving while one is open), the platform's menus given the model and set
// again when a state changes
function tests() {
	Actions.declare("menu-test", MenuAction);
	function setup() {
		Keymap.mac = false;
		var ui = new Ui(new helder.story.StoryText(), 400, 300), log = [];
		ui.keymap = new Keymap().bind("secondary-o", Open).bind("f11", Full).bind("secondary-k secondary-z", Zoom(2));
		var on = false;
		var view = new Node("view");
		view.focusable = true;
		ui.root.append(view);
		view.on(MenuAction, a -> {
			log.push(Std.string(a));
			if (a == Full) on = !on;
			true;
		}, a -> switch a {
			case Close: Disabled;
			case Full: on ? Checked : Unchecked;
			case _: Enabled;
		});
		ui.setFocus(view);
		return {ui: ui, log: log, view: view};
	}
	final MODEL = [
		Item("Open…", Open), Separator, Separator, Item("Full Screen", Full), Submenu("Zoom", [Item("200%", Zoom(2))]), Item("Close", Close),
		Role(Copy), Item("Nobody", StandardAction.Undo), Separator
	];
	describe("Menus", () -> {
		test("resolved: shortcuts from the keymap, states, separators, submenus, roles", () -> {
			var f = setup(), actions = [];
			var r = Menus.resolve(f.ui, MODEL, null, actions);
			equals([for (i in r) i.separator == true ? "-" : i.label], ["Open…", "-", "Full Screen", "Zoom", "Close", "Copy", "Nobody"]);
			equals(r[0].shortcut, "Ctrl+O");
			equals(r[0].keys.label(), "Ctrl+O");
			equals(r[2].shortcut, "F11");
			equals(r[2].checked, false);
			equals(r[3].items[0].shortcut, "Ctrl+K Ctrl+Z");
			equals(r[3].items[0].keys, null);
			equals(r[4].disabled, true);
			equals(r[5].role, "copy");
			equals(r[5].disabled, true);
			equals(r[6].disabled, true);
			equals(actions.length, 6);
		});
		test("a drawn context menu: Down past what is disabled, Enter dispatches from its node; the focus given back", () -> {
			var f = setup();
			Menus.popup(f.ui, MODEL, 50, 40, f.view);
			f.ui.update();
			var m = DrawnMenu.current;
			notEquals(m, null);
			equals(f.ui.overlay.children.length, 1);
			equals(m.highlighted, 0);
			f.ui.keyDown(Key.DOWN, 0);
			equals(m.highlighted, 2);
			f.ui.keyDown(Key.DOWN, 0);
			f.ui.keyDown(Key.RIGHT, 0);
			notEquals(m.submenu, null);
			equals(f.ui.overlay.children.length, 2);
			f.ui.keyDown(Key.LEFT, 0);
			equals(m.submenu, null);
			f.ui.keyDown(Key.UP, 0);
			f.ui.keyDown(Key.ENTER, 0);
			equals(f.log, ["Full"]);
			equals(f.ui.overlay.children.length, 0);
			equals(f.ui.focus, f.view);
			// (again: checked now; Escape closes it, nothing dispatched)
			Menus.popup(f.ui, MODEL, 50, 40, f.view);
			equals(@:privateAccess DrawnMenu.current.items[2].checked, true);
			f.ui.keyDown(Key.ESCAPE, 0);
			equals(f.ui.overlay.children.length, 0);
			equals(f.log, ["Full"]);
		});
		test("a drawn context menu by the pointer: a hover opens a submenu, a click chooses", () -> {
			var f = setup();
			Menus.popup(f.ui, MODEL, 50, 40, f.view);
			f.ui.update();
			var m = DrawnMenu.current;
			var zoom = m.popup.children[3];
			f.ui.pointerMove(zoom.absX + 5, zoom.absY + 5);
			f.ui.update();
			notEquals(m.submenu, null);
			var item = m.submenu.popup.children[0];
			f.ui.pointerDown(item.absX + 5, item.absY + 5, 1);
			f.ui.pointerUp(item.absX + 5, item.absY + 5, 1);
			equals(f.log, ["Zoom(2)"]);
			equals(f.ui.overlay.children.length, 0);
			// (a press outside closes them all)
			Menus.popup(f.ui, MODEL, 50, 40, f.view);
			f.ui.update();
			f.ui.pointerDown(390, 290, 1);
			equals(f.ui.overlay.children.length, 0);
		});
		test("a drawn menu bar: F10, Right to the next menu, a hover while open, a choice", () -> {
			var f = setup();
			var bar = new MenuBar(f.ui, [{label: "File", items: [Item("Open…", Open)]}, {label: "View", items: [Item("Full Screen", Full)]}]);
			f.ui.root.insert(bar.node, 0);
			f.ui.update();
			equals(bar.native, false);
			f.ui.keyDown(Key.F10, 0);
			equals(bar.current.labels(), ["Open…"]);
			f.ui.keyDown(Key.RIGHT, 0);
			equals(bar.current.labels(), ["Full Screen"]);
			f.ui.update();
			var file = bar.node.children[0];
			f.ui.pointerMove(file.absX + 3, file.absY + 3);
			equals(bar.current.labels(), ["Open…"]);
			f.ui.keyDown(Key.ENTER, 0);
			equals(f.log, ["Open"]);
			equals(bar.current, null);
			bar.dispose();
		});
		test("the platform's: its context menu and bar given the model, the bar set again when a state changes", () -> {
			var f = setup();
			var p = new FakeViews();
			f.ui.platform = p;
			Menus.popup(f.ui, MODEL, 10, 20, f.view);
			equals(p.menus.length, 1);
			equals(p.menus[0].items[0].shortcut, "Ctrl+O");
			p.menus[0].chosen(0);
			equals(f.log, ["Open"]);
			var bar = new MenuBar(f.ui, [{label: "View", items: [Item("Full Screen", Full)]}, {label: "Window", role: Window, items: [Role(Minimize)]}]);
			equals(bar.native, true);
			equals(p.bars, 1);
			equals(p.bar[1].role, "window");
			f.ui.update();
			equals(p.bars, 1);
			p.chosen(0);
			equals(f.log, ["Open", "Full"]);
			f.ui.update();
			equals(p.bars, 2);
			equals(p.bar[0].items[0].checked, true);
			bar.dispose();
		});
	});
}

enum MenuAction {
	Open;
	Full;
	Close;
	Zoom(by:Int);
}

class FakeViews implements helder.ui.platform.PlatformViews {
	public final menus:Array<{items:Array<PlatformMenuItem>, chosen:Int->Void}> = [];
	public var bar:Array<PlatformMenuItem> = [];
	public var bars = 0;
	public var chosen:Int->Void = _ -> {};

	public function new() {}

	public function editor(multiline:Bool):Null<helder.ui.platform.PlatformEditor>
		return null;

	public function poll() {}

	public function menu(items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void):Bool {
		menus.push({items: items, chosen: chosen});
		return true;
	}

	public function menuBar(menus:Array<PlatformMenuItem>, chosen:Int->Void):Bool {
		if (menus.length > 0) bars++;
		bar = menus;
		this.chosen = chosen;
		return true;
	}
}
