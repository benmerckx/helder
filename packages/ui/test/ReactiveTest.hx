import hxmc.esx.Esx;
import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Flow.*;
import hxmc.ui.reactive.Reactive.*;
import hxmc.ui.access.*;
import hxmc.ui.widgets.Widgets.Button;
import hxmc.ui.widgets.Widgets.Checkbox;
import hxmc.ui.widgets.Widgets.Slider;
import hxmc.ui.widgets.Widgets.Field;
import hxmc.ui.widgets.Widgets.Select;
import hxmc.ui.widgets.Widgets.Menu;
import hxmc.ui.widgets.Widgets.ContextMenu;
import hxmc.ui.widgets.Widgets.Table;
import hxmc.ui.widgets.Widgets.Tree;
import hxmc.ui.widgets.Widgets.Split;
import hxmc.ui.widgets.Widgets.Tooltip;
import hxmc.ui.widgets.Widgets.Dialog;

// hxmc.ui.reactive's tests, on Eval (make ui-check runs them after UiTest):
// signals, memos and effects (tracking, batching, no glitches, ownership
// and cleanup), then markup rendered into nodes (Render): elements and
// style attributes, text runs, reactive text and attributes, regions,
// For and Show, components, events through a Ui; then context, onMount,
// Index, Switch and Match, Show's branches kept, ErrorBoundary; Motion's
// transitions, springs and colours on a Clock ticked by hand; the
// accessibility tree of widgets in markup, its actions and changes; the
// popover widgets (Select, Menu, ContextMenu, Tooltip, Dialog) driven by pointer and keys;
// a VirtualList of 100000 rows scrolled
class ReactiveTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	public static function main() {
		signals();
		rendering();
		flow();
		motion();
		access();
		popovers();
		virtual();
		table();
		tree();
		split();
		Sys.println('ReactiveTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('ReactiveTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function signals() {
		var a = signal(1), b = signal(2);
		var runs = 0, seen = 0;
		var e = effect(() -> {
			runs++;
			seen = a.value + b.value;
		});
		check("effect runs at once", runs == 1 && seen == 3);
		a.value = 10;
		check("effect reruns on a write", runs == 2 && seen == 12);
		a.value = 10;
		check("the same value notifies nothing", runs == 2);
		batch(() -> {
			a.value = 1;
			b.value = 1;
		});
		check("a batch runs effects once", runs == 3 && seen == 2);
		// memos: lazy, cached, no glitches (a diamond)
		var x = signal(1);
		var computeB = 0, computeC = 0;
		var bm = memo(() -> {
			computeB++;
			x.value * 2;
		});
		var cm = memo(() -> {
			computeC++;
			x.value + 1;
		});
		var log = [];
		effect(() -> log.push(bm.value + "/" + cm.value));
		x.value = 5;
		check("diamond: one consistent run per write", log.join(" ") == "2/2 10/6", log.join(" "));
		var y = signal(3);
		var parity = memo(() -> y.value % 2);
		var pruns = 0;
		effect(() -> {
			parity.value;
			pruns++;
		});
		y.value = 5;
		check("a memo whose result is the same stops propagation", pruns == 1);
		y.value = 6;
		check("and propagates when it differs", pruns == 2);
		// untrack
		var u = signal(1), ur = 0;
		effect(() -> {
			untrack(() -> u.value);
			ur++;
		});
		u.value = 2;
		check("untrack does not track", ur == 1);
		// ownership: inner effects disposed when the outer reruns; cleanups
		var outer = signal(0), inner = signal(0), innerRuns = 0, cleaned = 0;
		effect(() -> {
			outer.value;
			effect(() -> {
				inner.value;
				innerRuns++;
			});
			onCleanup(() -> cleaned++);
		});
		inner.value = 1;
		check("inner effect runs", innerRuns == 2);
		outer.value = 1;
		check("outer rerun disposes the inner one and cleans up", cleaned == 1 && innerRuns == 3);
		inner.value = 2;
		check("only the new inner effect runs", innerRuns == 4, '$innerRuns');
		// a root's dispose
		var r = signal(0), rruns = 0;
		var dispose = root(d -> {
			effect(() -> {
				r.value;
				rruns++;
			});
			d;
		});
		dispose();
		r.value = 1;
		check("a disposed root's effects stop", rruns == 1);
		e.dispose();
		a.value = 100;
		check("a disposed effect stops", runs == 3);
	}

	static function Counter(props:{start:Int, ?label:String}):Esx {
		var count = signal(props.start);
		return <view direction="row" column-gap={4}>
			<text>{props.label ?? "count"}: {count}</text>
			<view tag="inc" focusable onClick={_ -> count.value++} padding={2}>+</view>
		</view>;
	}

	static final theme = context("light");

	// a component reading the theme where it is rendered
	static function Themed(props:{tag:String}):Esx
		return <text tag={props.tag}>{"theme " + use(theme)}</text>;

	static function Thrower(props:{when:Signal<Bool>}):Esx {
		return <text>{() -> {
			if (props.when.value) throw "boom";
			"fine";
		}}</text>;
	}

	static function popovers() {
		var ui = new Ui(new MonoText(), 400, 300);
		var fruit = signal("pear"), log = [], dialog = signal(false), field = signal("");
		Render.render(<view padding={10} row-gap={10} align-items="start">
			<Select tag="fruit" value={fruit} options={["apple", "pear", "plum"]} label="Fruit"/>
			<Menu tag="file" label="File" items={[{label: "New", onSelect: () -> log.push("new")}, {label: "Open", onSelect: () -> log.push("open"), shortcut: "Mod+O"}]}/>
			<Tooltip text="Saves the file" tag="tip"><text>Save</text></Tooltip>
			<ContextMenu tag="ctx" items={[{label: "Cut", onSelect: () -> log.push("cut")}, {label: "Copy", onSelect: () -> log.push("copy"), shortcut: "Mod+C"}]}>
				<view tag="area" focusable width={200} height={40}/>
			</ContextMenu>
			<Dialog open={dialog} title="Rename"><Field tag="rename" value={field}/></Dialog>
		</view>, ui.root);
		ui.update();
		function click(n:Node) {
			ui.update();
			var x = n.absX + n.width / 2, y = n.absY + n.height / 2;
			ui.pointerDown(x, y, 1);
			ui.pointerUp(x, y, 1);
			ui.update();
		}
		var select = ui.root.find("fruit");
		click(select);
		var list = ui.overlay.find("fruit-list");
		check("popover: a click opens the select's list under it", list != null && list.absY >= select.absY + select.height && ui.focus == ui.overlay.find("fruit-pear"),
			'${list} focus ${ui.focus}');
		ui.keyDown(Key.DOWN, 0);
		check("popover: Down moves to the next option", ui.focus == ui.overlay.find("fruit-plum"), '${ui.focus}');
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		check("popover: Enter chooses, closes, gives the focus back", fruit.value == "plum" && ui.overlay.children.length == 0 && ui.focus == select, '${fruit.value} ${ui.focus}');
		ui.keyDown(Key.UP, 0);
		check("popover: Up on the closed select", fruit.value == "pear");
		click(select);
		click(ui.overlay.find("fruit-apple"));
		check("popover: a click on an option chooses it", fruit.value == "apple" && ui.overlay.children.length == 0);
		click(select);
		ui.keyDown(Key.ESCAPE, 0);
		ui.update();
		check("popover: Escape closes", ui.overlay.children.length == 0 && fruit.value == "apple");
		click(select);
		ui.pointerDown(390, 290, 1);
		ui.pointerUp(390, 290, 1);
		ui.update();
		check("popover: a click outside closes", ui.overlay.children.length == 0);
		var t = ui.accessTree();
		var combo = [for (id in t.order) t.nodes.get(id)].filter(n -> n.role == ComboBox)[0];
		check("popover: the select's role, name and value", combo != null && combo.expanded == false && combo.name == "Fruit" && combo.children.length == 1 && t.nodes.get(combo.children[0]).name == "apple", combo == null ? "none" : combo.name + " " + combo.expanded + " " + [for (c in combo.children) t.nodes.get(c).name].join(","));
		// a menu: chosen with the keys
		var file = ui.root.find("file");
		ui.setFocus(file);
		ui.keyDown(Key.DOWN, 0);
		ui.update();
		check("popover: the menu opens on Down, its first item focused", ui.focus == ui.overlay.find("file-0"));
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		check("popover: a menu item chosen", log.join(",") == "open" && ui.overlay.children.length == 0 && ui.focus == file, log.join(","));
		// a context menu: at the pointer, flipped where it does not fit
		var area = ui.root.find("area");
		ui.pointerDown(area.absX + 30, area.absY + 10, 3);
		ui.pointerUp(area.absX + 30, area.absY + 10, 3);
		ui.update();
		var cm = ui.overlay.find("ctx-items");
		check("popover: a right click opens the context menu where it was pressed", cm != null && cm.absX == area.absX + 30 && cm.absY == area.absY + 10
			&& ui.focus == ui.overlay.find("ctx-0"), cm == null ? "none" : '${cm.absX},${cm.absY} focus ${ui.focus}');
		ui.pointerDown(area.absX + 190, area.absY + 30, 3);
		ui.pointerUp(area.absX + 190, area.absY + 30, 3);
		ui.update();
		cm = ui.overlay.find("ctx-items");
		check("popover: a second right click moves it", cm != null && ui.overlay.children.length == 1
			&& cm.absX == area.absX + 190 && cm.absY == area.absY + 30, cm == null ? "none" : '${cm.absX}+${cm.width},${cm.absY}');
		click(ui.overlay.find("ctx-1"));
		check("popover: a context menu item chosen by a click", log.join(",") == "open,copy" && ui.overlay.children.length == 0, log.join(","));
		ui.pointerDown(area.absX + 30, area.absY + 10, 3);
		ui.pointerUp(area.absX + 30, area.absY + 10, 3);
		ui.update();
		ui.pointerDown(area.absX + 5, area.absY + 10, 1);
		ui.pointerUp(area.absX + 5, area.absY + 10, 1);
		ui.update();
		check("popover: a left click in its children closes the context menu", ui.overlay.children.length == 0);
		ui.setFocus(area);
		ui.keyDown(Key.F10, Key.MOD_SHIFT);
		ui.update();
		cm = ui.overlay.find("ctx-items");
		check("popover: Shift+F10 opens it at the children's corner", cm != null && cm.absX == area.absX && cm.absY == area.absY && ui.focus == ui.overlay.find("ctx-0"),
			cm == null ? "none" : '${cm.absX},${cm.absY}');
		ui.keyDown(Key.ESCAPE, 0);
		ui.update();
		ui.keyDown(Key.MENU, 0);
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		check("popover: the menu key, then Enter on the first item", log.join(",") == "open,copy,cut" && ui.overlay.children.length == 0 && ui.focus == area, log.join(",") + ' ${ui.focus}');
		// shortcuts: a menu's anywhere, shown in it; a context menu's in its children; a Hotkey while mounted
		var at = log.length;
		ui.setFocus(null);
		ui.keyDown("o".code, Key.MOD_CONTROL);
		ui.keyDown("c".code, Key.MOD_CONTROL);
		ui.setFocus(area);
		ui.keyDown("c".code, Key.MOD_META);
		check("popover: a menu's shortcut anywhere, a context menu's in its children", log.slice(at).join(",") == "open,copy", log.slice(at).join(","));
		ui.setFocus(file);
		ui.keyDown(Key.DOWN, 0);
		ui.update();
		var label = ui.overlay.find("file-1");
		var shown = label == null ? "" : [for (c in label.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join("|");
		check("popover: a menu item's shortcut shown", shown == "Open|Ctrl+O", shown);
		ui.keyDown(Key.ESCAPE, 0);
		ui.update();
		var on = signal(true), saved = 0;
		var dispose = Render.render(<view><Show when={on}><Hotkey keys="Mod+S" action={() -> saved++}/></Show></view>, ui.root);
		ui.keyDown("s".code, Key.MOD_CONTROL);
		on.value = false;
		ui.keyDown("s".code, Key.MOD_CONTROL);
		dispose();
		check("popover: a Hotkey while mounted", saved == 1, '$saved');
		// a tooltip: after the pointer rests half a second
		var tip = ui.root.find("tip");
		Clock.tick(100);
		ui.pointerMove(tip.absX + 2, tip.absY + 2);
		Clock.tick(100.1);
		Clock.tick(100.3);
		check("popover: no tooltip before the delay", ui.overlay.children.length == 0);
		Clock.tick(100.7);
		ui.update();
		var shown = ui.overlay.find("tooltip");
		check("popover: the tooltip above, after the delay", shown != null && shown.absY + shown.height <= tip.absY, '${shown}');
		ui.pointerMove(390, 290);
		ui.update();
		check("popover: hidden when the pointer leaves", ui.overlay.children.length == 0);
		// a dialog: modal, its field focused, Escape closes it
		dialog.value = true;
		ui.update();
		check("popover: the dialog open, its field focused", ui.overlay.find("dialog") != null && ui.focus == ui.overlay.find("rename"), '${ui.focus}');
		ui.keyDown(Key.ESCAPE, 0);
		ui.update();
		check("popover: Escape closes the dialog", !dialog.value && ui.overlay.children.length == 0);
	}

	static function table() {
		var ui = new Ui(new MonoText(), 400, 300);
		ui.root.style.fontSize = 10;
		var rows = [for (i in 0...200) {name: "file" + StringTools.lpad("" + ((i * 37) % 200), "0", 3), size: (i * 13) % 50}];
		var picked:Signal<Null<{name:String, size:Int}>> = signal(null), opened = [];
		Render.render(<view padding={10}><Table tag="t" rows={rows} selected={picked} height={150} rowHeight={20} label="Files"
			onActivate={r -> opened.push(r.name)}
			columns={[
				{title: "Name", cell: r -> r.name, compare: (a, b) -> Reflect.compare(a.name, b.name)},
				{title: "Size", width: "60px", cell: r -> "" + r.size, compare: (a, b) -> a.size - b.size},
				{title: "Note", width: "auto", cell: r -> "-"}
			]}/></view>, ui.root);
		ui.update();
		var list = ui.root.find("t-rows");
		// (each row in the list's wrapper, tagged row)
		function rowNodes():Array<Node>
			return [for (c in list.children) if (c.tag == "row") c.children[0]];
		function rowNamed(name:String):Node
			return rowNodes().filter(r -> (cast r.children[0].children[0] : TextNode).text == name)[0];
		function names():Array<String>
			return [for (r in rowNodes()) (cast r.children[0].children[0] : TextNode).text];
		check("table: the rows in view, unsorted", names()[0] == "file000" && names()[1] == "file037", names().slice(0, 3).join(","));
		function click(n:Node) {
			ui.update();
			ui.pointerDown(n.absX + 2, n.absY + 2, 1);
			ui.pointerUp(n.absX + 2, n.absY + 2, 1);
			ui.update();
		}
		click(ui.root.find("t-head-0"));
		check("table: sorted by a header", names()[0] == "file000" && names()[1] == "file001", names().slice(0, 3).join(","));
		click(ui.root.find("t-head-0"));
		check("table: again, the other way", names()[0] == "file199", names()[0]);
		var t = 0.0;
		Ui.now = () -> t;
		var second = rowNamed("file198");
		click(second);
		check("table: a click selects a row", picked.value != null && picked.value.name == "file198", picked.value == null ? "none" : picked.value.name);
		for (_ in 0...10)
			ui.keyDown(Key.DOWN, 0);
		ui.update();
		check("table: Down moves the selection, the view following", picked.value.name == "file188" && list.scrollY > 0, picked.value.name + " " + list.scrollY);
		ui.keyDown(Key.ENTER, 0);
		check("table: Enter activates", opened.join(",") == "file188", opened.join(","));
		ui.keyDown(Key.HOME, 0);
		ui.update();
		check("table: Home, the first row, the view at the top", picked.value.name == "file199" && list.scrollY == 0, picked.value.name + " " + list.scrollY);
		var first = rowNamed("file199");
		t = 10;
		click(first);
		t = 10.2;
		click(first);
		check("table: a double click activates", opened.join(",") == "file188,file199", opened.join(","));
		var tree = ui.accessTree(), roles = [for (id in tree.order) tree.nodes.get(id).role];
		check("table: a grid of rows, column headers and cells", roles.indexOf(Table) >= 0 && roles.indexOf(ColumnHeader) >= 0 && roles.indexOf(Row) >= 0 && roles.indexOf(Cell) >= 0);
		Ui.now = haxe.Timer.stamp;
	}

	static function tree() {
		var ui = new Ui(new MonoText(), 300, 300);
		ui.root.style.fontSize = 10;
		var kids = ["src" => ["main", "ui"], "ui" => ["Node", "Style"], "docs" => ["guide"]];
		var picked:Signal<Null<String>> = signal(null), open:Signal<Array<String>> = signal([]), opened = [];
		Render.render(<view padding={10}><Tree tag="tr" roots={["src", "docs", "README"]} children={(s:String) -> kids.get(s)} render={(s:String) -> s}
			expanded={open} selected={picked} height={200} rowHeight={20} label="Files" onActivate={s -> opened.push(s)}/></view>, ui.root);
		ui.update();
		var list = ui.root.find("tr-rows");
		function items():Array<Node>
			return [for (c in list.children) if (c.tag == "row" && c.children.length > 0 && c.children[0].children.length > 1) c.children[0]];
		function shown():String
			return [for (r in items()) {
				var label = r.children[1];
				var t = Std.isOfType(label, TextNode) ? (cast label : TextNode).text : "?";
				(r.semantics.level > 1 ? "  " : "") + (r.semantics.expanded == true ? "-" : r.semantics.expanded == false ? "+" : "") + t;
			}].join(",");
		check("tree: the roots, closed", shown() == "+src,+docs,README", shown());
		function click(n:Node) {
			ui.update();
			ui.pointerDown(n.absX + 2, n.absY + 2, 1);
			ui.pointerUp(n.absX + 2, n.absY + 2, 1);
			ui.update();
		}
		click(items()[0].children[0]);
		check("tree: its triangle opens an item, without selecting it", shown() == "-src,  main,  +ui,+docs,README" && picked.value == null, shown());
		var t = 0.0;
		Ui.now = () -> t;
		click(items()[1]);
		check("tree: a click selects", picked.value == "main", "" + picked.value);
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.RIGHT, 0);
		ui.update();
		check("tree: Down, then Right opens", picked.value == "ui" && shown() == "-src,  main,  -ui,  Node,  Style,+docs,README", shown());
		ui.keyDown(Key.RIGHT, 0);
		ui.keyDown(Key.ENTER, 0);
		check("tree: Right again, its first child; Enter activates a leaf", picked.value == "Node" && opened.join(",") == "Node", picked.value + " " + opened.join(","));
		ui.keyDown(Key.LEFT, 0);
		check("tree: Left on a leaf, its parent", picked.value == "ui");
		ui.keyDown(Key.LEFT, 0);
		ui.update();
		check("tree: Left on an open item closes it", picked.value == "ui" && shown() == "-src,  main,  +ui,+docs,README", shown());
		ui.keyDown(Key.END, 0);
		check("tree: End, the last row", picked.value == "README");
		var docs = items()[3];
		t = 10;
		click(docs);
		t = 10.2;
		click(docs);
		check("tree: a double click opens an item", shown() == "-src,  main,  +ui,-docs,  guide,README" && open.value.indexOf("docs") >= 0, shown());
		var tree = ui.accessTree(), roles = [for (id in tree.order) tree.nodes.get(id).role];
		var levels = [for (id in tree.order) if (tree.nodes.get(id).role == TreeItem) tree.nodes.get(id).level];
		check("tree: a tree of items with their levels", roles.indexOf(Tree) >= 0 && levels.join(",") == "1,2,2,1,2,1", levels.join(","));
		var item = [for (id in tree.order) if (tree.nodes.get(id).role == TreeItem) tree.nodes.get(id)][0];
		check("tree: an item named by its text, not its triangle", item.name == "src" && item.expanded == true, item.name);
		Ui.now = haxe.Timer.stamp;
	}

	static function split() {
		var ui = new Ui(new MonoText(), 400, 200);
		var size = signal(120.0);
		Render.render(<view height={200}><Split tag="sp" size={size} min={50} label="Sidebar" first={<view tag="side"/>} second={<view tag="main"/>}/></view>, ui.root);
		ui.update();
		var side = ui.root.find("side").parent, main = ui.root.find("main").parent, div = ui.root.find("sp-divider");
		check("split: the first pane at its size, the divider, the rest", side.width == 120 && div.absX == 120 && div.width == 6 && main.absX == 126 && main.width == 274,
			side.width + " " + div.absX + " " + main.width);
		ui.pointerDown(122, 100, 1);
		ui.pointerMove(202, 100);
		ui.pointerUp(202, 100, 1);
		ui.update();
		check("split: dragged by where it was grabbed", size.value == 200 && side.width == 200, "" + size.value);
		ui.pointerDown(202, 100, 1);
		ui.pointerMove(10, 100);
		ui.pointerMove(1000, 100);
		ui.pointerUp(1000, 100, 1);
		check("split: within its bounds (the room less min)", size.value == 400 - 6 - 50, "" + size.value);
		ui.setFocus(div);
		ui.keyDown(Key.HOME, 0);
		var home = size.value;
		ui.keyDown(Key.RIGHT, 0);
		check("split: the keys move it (Home: min)", home == 50 && size.value == 60, home + " " + size.value);
		var tree = ui.accessTree(), sep = [for (id in tree.order) if (tree.nodes.get(id).role == Separator) tree.nodes.get(id)];
		check("split: a separator with the size as its value", sep.length == 1 && sep[0].valueNow == 60 && sep[0].name == "Sidebar" && sep[0].focusable);
	}

	static function virtual() {
		var ui = new Ui(new MonoText(), 300, 300);
		var items = signal([for (i in 0...100000) "item " + i]);
		var made = 0;
		var dispose = Render.render(<view><VirtualList tag="list" each={items} itemHeight={20} height={200}
			render={(item:Signal<String>, i:Int) -> {
				made++;
				<text>{() -> item.value}</text>;
			}}/></view>, ui.root);
		ui.update();
		var list = ui.root.find("list");
		function rows():Array<String>
			return [for (c in list.children) if (c.tag == "row") (cast c.children[0] : TextNode).text];
		check("virtual: only the rows in view (and 3 more)", rows().length == 14 && rows()[0] == "item 0" && made == 14, rows().join(","));
		check("virtual: scrolls the whole list", list.contentHeight == 2000000, '${list.contentHeight}');
		ui.wheel(list.absX + 5, list.absY + 5, 0, 1000);
		ui.update();
		var r = rows();
		check("virtual: rows made as it scrolls", r.length == 17 && r.indexOf("item 47") >= 0 && r.indexOf("item 63") >= 0 && r.indexOf("item 0") < 0, r.join(","));
		var at = [for (c in list.children) if (c.tag == "row") c].filter(c -> (cast c.children[0] : TextNode).text == "item 50")[0];
		check("virtual: a row at its index's height", at != null && at.y == 1000, at == null ? "none" : '${at.y}');
		items.value = [for (i in 0...60) "new " + i];
		ui.update();
		r = rows();
		check("virtual: a shorter list: its rows, the scroll clamped", r.length > 0 && r.indexOf("new 59") >= 0 && list.scrollY == 60 * 20 - 200, r.join(",") + " " + list.scrollY);
		dispose();
		check("virtual: disposed", ui.root.find("list") == null);
	}

	static function access() {
		var ui = new Ui(new MonoText(), 400, 300);
		var checked = signal(false), vol = signal(0.5), name = signal("");
		var saved = 0;
		Render.render(<view>
			<text>Settings</text>
			<Button tag="save" label="Save" onClick={() -> saved++}/>
			<Checkbox tag="check" checked={checked} label="Remember"/>
			<Slider tag="vol" value={vol} step={0.1} label="Volume"/>
			<Field tag="name" value={name} placeholder="Name"/>
			<view><text>nested</text><image label="a picture" src={new Image(4, 4)} width={4} height={4}/></view>
		</view>, ui.root);
		ui.update();
		var t = ui.accessTree();
		var top = t.nodes.get(t.root);
		var kids = [for (id in top.children) t.nodes.get(id)];
		var shape = [for (k in kids) k.role.aria() + ":" + k.name].join(",");
		check("access: the tree (groups without a role left out, names from content)",
			shape == "text:Settings,button:Save,checkbox:Remember,slider:Volume,textbox:Name,text:nested,img:a picture", shape);
		var box = kids[2], slider = kids[3], field = kids[4];
		check("access: states", box.checked == false && box.focusable && slider.valueNow == 0.5 && slider.valueMin == 0 && slider.valueMax == 1 && field.value == "");
		check("access: a button's text is its name, not a node", kids[1].children.length == 0);
		var save = ui.root.find("save");
		check("access: bounds", kids[1].x == save.absX && kids[1].width == save.width);
		// actions
		check("access: Click", ui.accessAction(kids[1].id, Click) && saved == 1);
		ui.accessAction(box.id, Click);
		ui.update();
		var t2 = ui.accessTree();
		var c = t2.changes(t);
		check("access: a click toggles the checkbox; only it changed", t2.nodes.get(box.id).checked == true && c.nodes.length == 1 && c.nodes[0].id == box.id,
			[for (n in c.nodes) n.role.aria()].join(","));
		ui.accessAction(slider.id, Increment);
		ui.update();
		var t3 = ui.accessTree();
		check("access: Increment steps the slider and focuses it", Math.abs(t3.nodes.get(slider.id).valueNow - 0.6) < 1e-9 && t3.focus == slider.id);
		check("access: SetValue types into a field", ui.accessAction(field.id, SetValue, "Ada") && name.value == "Ada");
		ui.update();
		var t4 = ui.accessTree();
		check("access: the field's value", t4.nodes.get(field.id).value == "Ada");
		check("access: Focus", ui.accessAction(field.id, Focus) && ui.focus == ui.root.find("name"));
		check("access: no change, no update", t4.changesJson(t4) == null && t4.changesJson(null) != null);
		check("access: an action on a node gone", !ui.accessAction(9999999, Click));
	}

	static function motion() {
		var target = signal(0.0);
		var t = Motion.transition(() -> target.value, 1.0, Motion.linear);
		check("motion: a transition starts at its target", t.value == 0 && !Clock.active);
		target.value = 10;
		check("motion: it moves on ticks", t.value == 0 && Clock.active);
		Clock.tick(100);
		check("motion: from the first tick", t.value == 0, '${t.value}');
		Clock.tick(100.5);
		check("motion: half way", t.value == 5, '${t.value}');
		target.value = 20;
		Clock.tick(101);
		check("motion: a new target, from where it is", t.value == 5, '${t.value}');
		Clock.tick(101.25);
		check("motion: a quarter to the new target", Math.abs(t.value - 8.75) < 1e-9, '${t.value}');
		Clock.tick(102);
		check("motion: there, and done", t.value == 20 && !Clock.active, '${t.value}');
		// a spring settles on its target (an underdamped one, overshooting)
		var s = Motion.spring(() -> target.value, 170, 12);
		target.value = 0;
		var time = 200.0, peak = 20.0, steps = 0;
		while (Clock.active && steps < 1000) {
			Clock.tick(time);
			time += 1 / 60;
			steps++;
			if (s.value < peak) peak = s.value;
		}
		check("motion: a spring settles", s.value == 0 && !Clock.active && steps < 400, '${s.value} after $steps steps');
		check("motion: overshooting", peak < -1 && peak > -10, '$peak');
		// a colour
		var c = signal("#000000");
		var col = Motion.color(() -> c.value, 1.0, Motion.linear);
		c.value = "#ffffff";
		Clock.tick(300);
		Clock.tick(300.5);
		check("motion: a colour half way", col.value == "#808080FF", col.value);
		Clock.tick(301);
		check("motion: the colour reached", col.value == "#FFFFFFFF" && !Clock.active, col.value);
		// stopped with its owner
		var other = signal(0.0);
		var stop = root(dispose -> {
			Motion.transition(() -> other.value, 1.0);
			dispose;
		});
		other.value = 5;
		stop();
		Clock.tick(400);
		check("motion: a disposed transition stops", !Clock.active);
	}

	static function flow() {
		var ui = new Ui(new MonoText(), 300, 200);
		// context: a Provider's value for what it renders, the default elsewhere
		Render.render(<view>
			<Themed tag="outside"/>
			<Provider context={theme} value={"dark"}><Themed tag="inside"/></Provider>
		</view>, ui.root);
		var text = (tag:String) -> (cast ui.root.find(tag) : TextNode).text;
		check("context: the default", text("outside") == "theme light", text("outside"));
		check("context: provided", text("inside") == "theme dark", text("inside"));
		check("context: provide()", provide(theme, "blue", () -> use(theme)) == "blue" && use(theme) == "light");
		// onMount: after the nodes are in the tree
		var parentAtMount:Null<Node> = null, mounted = 0;
		var probe:Null<Node> = null;
		Render.render(<view tag="probe" ref={n -> {
			probe = n;
			onMount(() -> {
				mounted++;
				parentAtMount = n.parent;
			});
		}}/>, ui.root);
		check("onMount: after the insertion", mounted == 1 && parentAtMount == ui.root);
		// Index: rows by index, an item's signal set in place
		var names = signal(["a", "b", "c"]);
		var rowsMade = 0;
		Render.render(<view tag="index"><Index each={names} render={(n:Signal<String>, i:Int) -> {
			rowsMade++;
			<text>{() -> i + ":" + n.value}</text>;
		}}/></view>, ui.root);
		var idx = ui.root.find("index");
		var shownRows = () -> [for (c in idx.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("Index: rows", shownRows() == "0:a,1:b,2:c" && rowsMade == 3, shownRows());
		names.value = ["x", "b"];
		check("Index: items set in place, extra rows removed", shownRows() == "0:x,1:b" && rowsMade == 3, shownRows());
		names.value = ["x", "b", "y", "z"];
		check("Index: rows added", shownRows() == "0:x,1:b,2:y,3:z" && rowsMade == 5, shownRows());
		// For: a row kept when the list changes stays bound (its computations
		// belong to the list's owner, not to the effect that runs again)
		var first = signal("one"), second = signal("two");
		var list = signal([first]);
		Render.render(<view tag="kept"><For each={list} render={(sg:Signal<String>) -> <text>{sg}</text>}/></view>, ui.root);
		list.value = [first, second];
		first.value = "ONE";
		var kept = ui.root.find("kept");
		var keptText = [for (c in kept.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("For: a kept row stays bound", keptText == "ONE,two", keptText);
		list.value = [second];
		first.value = "gone";
		second.value = "TWO";
		keptText = [for (c in kept.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("For: a removed row's computations disposed, the rest bound", keptText == "TWO" && @:privateAccess first.observers.length == 0, keptText);
		// Switch and Match
		var n = signal(1);
		Render.render(<view tag="switch"><Switch fallback="many">
			<Match when={() -> n.value == 0}><text>none</text></Match>
			<Match when={() -> n.value == 1}><text>one</text></Match>
		</Switch></view>, ui.root);
		var sw = ui.root.find("switch");
		var switched = () -> [for (c in sw.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("Switch: the first case true", switched() == "one", switched());
		n.value = 0;
		check("Switch: another case", switched() == "none", switched());
		n.value = 5;
		check("Switch: the fallback", switched() == "many", switched());
		// Show renders its children again only when the branch changes
		var count = signal(1), made = 0;
		Render.render(<view tag="show"><Show when={() -> count.value > 0}><view ref={_ -> made++}/></Show></view>, ui.root);
		count.value = 2;
		count.value = 3;
		check("Show: the branch kept while it stays chosen", made == 1, '$made');
		count.value = 0;
		count.value = 4;
		check("Show: made again when chosen again", made == 2, '$made');
		// ErrorBoundary: an error while rendering, one later, reset
		var fail = signal(false);
		Render.render(<view tag="boundary"><ErrorBoundary fallback={(e:Dynamic, reset:Void->Void) -> <text tag="fallback" onClick={_ -> reset()}>{"error: " + e}</text>}>
			<Thrower when={fail}/>
		</ErrorBoundary></view>, ui.root);
		var bd = ui.root.find("boundary");
		var bounded = () -> [for (c in bd.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("ErrorBoundary: the children", bounded() == "fine", bounded());
		fail.value = true;
		check("ErrorBoundary: a later error shows the fallback", bounded() == "error: boom", bounded());
		fail.value = false;
		var fb = ui.root.find("fallback");
		ui.update();
		ui.pointerDown(fb.absX + 1, fb.absY + 1, 1);
		ui.pointerUp(fb.absX + 1, fb.absY + 1, 1);
		check("ErrorBoundary: reset renders the children again", bounded() == "fine", bounded());
		var fail2 = signal(true);
		Render.render(<view tag="boundary2"><ErrorBoundary fallback={(e:Dynamic, reset:Void->Void) -> "caught " + e}>
			<text>before</text>
			<Thrower when={fail2}/>
		</ErrorBoundary></view>, ui.root);
		var bd2 = ui.root.find("boundary2");
		var bounded2 = [for (c in bd2.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("ErrorBoundary: an error while rendering, what was made before removed", bounded2 == "caught boom", bounded2);
	}

	static function rendering() {
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.fontSize = 10; // 5 per character, 12.5 a line
		var name = signal("Ann");
		var wide = signal(false);
		var items = signal(["a", "b", "c"]);
		var shown = signal(true);
		var made = 0;
		var dispose = Render.render(<view padding="4 8" background="#eeeeee">
			<view tag="row" direction="row" justify="space-between" width={() -> wide.value ? 200 : 100}>
				Hello {name}!
			</view>
			<Counter start={1}/>
			<view tag="list"><For each={items} render={(i:String) -> {
				made++;
				<text>{i}</text>;
			}}/></view>
			<Show when={shown} fallback="hidden">
				<text tag="shown">visible</text>
			</Show>
		</view>, ui.root);
		ui.update();
		var top = ui.root.children[0];
		check("render: a view with its style", top.style.background == Color.rgb(0xEEEEEE) && top.style.padding.left == 8);
		var row = top.find("row");
		check("render: style attributes", row.style.direction == Row && row.style.justify == SpaceBetween && row.width == 100, '$row');
		var hello:TextNode = cast row.children[0];
		check("render: a text run is one TextNode", row.children.length == 1 && hello.text == "Hello Ann!", [for (c in row.children) c.tag].join(","));
		name.value = "Bo";
		check("render: reactive text", hello.text == "Hello Bo!");
		wide.value = true;
		ui.update();
		check("render: a reactive attribute", row.width == 200);
		// the counter
		var counter = top.children[1];
		var label:TextNode = cast counter.children[0];
		check("render: a component", label.text == "count: 1", label.text);
		var inc = counter.find("inc");
		check("render: a flag attribute", inc.focusable);
		ui.update();
		ui.pointerDown(inc.absX + 2, inc.absY + 2, 1);
		ui.pointerUp(inc.absX + 2, inc.absY + 2, 1);
		check("render: an event updates its signal", label.text == "count: 2", label.text);
		// For
		var list = top.find("list");
		function texts()
			return [for (c in list.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("for: items", texts() == "a,b,c" && made == 3, texts());
		var firstB = list.children.filter(c -> Std.isOfType(c, TextNode))[1];
		items.value = ["c", "b", "d"];
		check("for: reordered, one made", texts() == "c,b,d" && made == 4, texts() + " " + made);
		check("for: kept nodes", list.children.filter(c -> Std.isOfType(c, TextNode))[1] == firstB);
		// Show
		check("show: when true", top.find("shown") != null);
		shown.value = false;
		var fallback = [for (c in top.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text];
		check("show: the fallback", top.find("shown") == null && fallback.contains("hidden"), fallback.join(","));
		shown.value = true;
		check("show: back", top.find("shown") != null);
		dispose();
		check("render: dispose removes the content", ui.root.children.length == 0);
		name.value = "gone";
		check("render: and stops its effects", hello.text == "Hello Bo!");
	}
}
