import hxmc.ui.*;
import hxmc.view.*;
import hxmc.ui.view.*;
import hxmc.view.Flow.*;
import hxmc.ui.view.UiFlow.*;
import hxmc.view.Reactive.*;
import hxmc.ui.access.*;
import hxmc.ui.widgets.Widgets.Button;
import hxmc.ui.widgets.Widgets.Checkbox;
import hxmc.ui.widgets.Widgets.Slider;
import hxmc.ui.widgets.Widgets.Field;
import hxmc.ui.widgets.Widgets.Select;
import hxmc.ui.widgets.Widgets.Combobox;
import hxmc.ui.widgets.Widgets.NumberField;
import hxmc.ui.widgets.Widgets.Toaster;
import hxmc.ui.widgets.Widgets.Disclosure;
import hxmc.ui.widgets.Widgets.Accordion;
import hxmc.ui.widgets.Toasts;
import hxmc.ui.widgets.TextField;
import hxmc.ui.widgets.Widgets.Menu;
import hxmc.ui.widgets.Widgets.SegmentedControl;
import hxmc.ui.widgets.Widgets.Breadcrumbs;
import hxmc.ui.widgets.Widgets.Pagination;
import hxmc.ui.widgets.Widgets.ContextMenu;
import hxmc.ui.widgets.Widgets.Menubar;
import hxmc.ui.widgets.Widgets.Listbox;
import hxmc.ui.widgets.Widgets.Toolbar;
import hxmc.ui.widgets.Widgets.ColorPicker;
import hxmc.ui.widgets.Widgets.Sortable;
import hxmc.ui.widgets.Widgets.RangeSlider;
import hxmc.ui.widgets.Widgets.Tabs;
import hxmc.ui.widgets.Widgets.Radio;
import hxmc.ui.widgets.Widgets.Progress;
import hxmc.ui.widgets.Widgets.Table;
import hxmc.ui.widgets.Widgets.Tree;
import hxmc.ui.widgets.Widgets.Split;
import hxmc.ui.widgets.Widgets.Calendar;
import hxmc.ui.widgets.Widgets.DatePicker;
import hxmc.ui.widgets.Days;
import hxmc.ui.widgets.Widgets.Tooltip;
import hxmc.ui.widgets.Widgets.Dialog;

// Markup rendered into hxmc.ui's nodes (hxmc.view on NodeRenderer), on Eval
// (make ui-check runs it after UiTest; hxmc.view's own tests are
// packages/view/test): elements and
// style attributes, text runs, reactive text and attributes, regions,
// For and Show, components, events through a Ui; then context, onMount,
// Index, Switch and Match, Show's branches kept, ErrorBoundary; Motion's
// transitions, springs and colours on a Clock ticked by hand; the
// accessibility tree of widgets in markup, its actions and changes; the
// popover widgets (Select, Menu, ContextMenu, Tooltip, Dialog, Combobox) driven by pointer and keys;
// Disclosure, Accordion, toasts and NumberField;
// a VirtualList of 100000 rows scrolled
class MarkupTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	public static function main() {
		rendering();
		flow();
		motion();
		access();
		popovers();
		combobox();
		toasts();
		numbers();
		rightToLeft();
		wordBreaks();
		autoMargins();
		baselines();
		shorthands();
		editMenus();
		menubar();
		tabs();
		mixedCheckbox();
		indeterminate();
		typeAhead();
		password();
		listbox();
		toolbar();
		navigation();
		colorPicker();
		sortable();
		rangeSlider();
		liveRegions();
		focusTips();
		virtual();
		table();
		tree();
		split();
		calendar();
		Sys.println('MarkupTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('MarkupTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function Counter(props:{start:Int, ?label:String}):View {
		var count = signal(props.start);
		return <view direction="row" column-gap={4}>
			<text>{props.label ?? "count"}: {count}</text>
			<view tag="inc" focusable onClick={_ -> count.value++} padding={2}>+</view>
		</view>;
	}

	static final theme = context("light");

	// a component reading the theme where it is rendered
	static function Themed(props:{tag:String}):View
		return <text tag={props.tag}>{"theme " + use(theme)}</text>;

	static function Thrower(props:{when:Signal<Bool>}):View {
		return <text>{() -> {
			if (props.when.value) throw "boom";
			"fine";
		}}</text>;
	}

	// (every node under n tagged tag, in order)
	static function tagged(n:Node, tag:String):Array<Node> {
		var out = [];
		function walk(n:Node) {
			if (n.tag == tag) out.push(n);
			for (c in n.children)
				walk(c);
		}
		walk(n);
		return out;
	}

	static function combobox() {
		var ui = new Ui(new MonoText(), 400, 300);
		var city = signal(""), chosen = [];
		Render.render(<view padding={10} align-items="start">
			<Combobox tag="city" value={city} options={["Amsterdam", "Antwerp", "Berlin", "Bern", "Brussels"]} label="City" onChoose={c -> chosen.push(c)}/>
		</view>, ui.root);
		ui.update();
		var field = ui.root.find("city");
		ui.setFocus(field);
		ui.textInput("ber");
		ui.update();
		var list = ui.overlay.find("city-list");
		function shown()
			return list == null ? "" : [for (o in tagged(list, "city-option")) (cast o.children[0] : TextNode).text].join(",");
		check("combobox: typing filters the options under it (either case)", list != null && shown() == "Berlin,Bern" && list.absY >= field.absY + field.height
			&& ui.focus == field && field.semantics.expanded == true, shown());
		var t = ui.accessTree(), an = t.nodes.get(t.focus);
		check("combobox: an editable combobox to assistive technology", an.role == ComboBox && an.value == "ber" && an.expanded == true && an.editable()
			&& [for (id in t.order) t.nodes.get(id).role].filter(r -> r == ListBoxOption).length == 2, an == null ? "none" : an.role + " " + an.value);
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.DOWN, 0);
		ui.update();
		check("combobox: Down highlights, the focus stays in the field", tagged(list, "city-option")[1].semantics.selected == true && ui.focus == field);
		ui.keyDown(Key.UP, 0);
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		check("combobox: Enter chooses the highlighted option", city.value == "Berlin" && chosen.join(",") == "Berlin" && ui.overlay.children.length == 0
			&& (cast field : TextField).text == "Berlin", '${city.value} ${chosen}');
		city.value = "";
		ui.update();
		ui.keyDown(Key.DOWN, 0);
		ui.update();
		list = ui.overlay.find("city-list");
		check("combobox: Down on the empty field lists every option", list != null && tagged(list, "city-option").length == 5);
		ui.keyDown(Key.ESCAPE, 0);
		ui.update();
		check("combobox: Escape closes", ui.overlay.children.length == 0 && ui.focus == field);
		ui.textInput("Br");
		ui.update();
		var opt = tagged(ui.overlay.find("city-list"), "city-option")[0];
		var x = opt.absX + opt.width / 2, y = opt.absY + opt.height / 2;
		ui.pointerDown(x, y, 1);
		ui.pointerUp(x, y, 1);
		ui.update();
		check("combobox: a click chooses", city.value == "Brussels" && ui.focus == field && ui.overlay.children.length == 0, city.value);
		ui.textInput("x");
		ui.update();
		check("combobox: no match, no list", ui.overlay.children.length == 0 && field.semantics.expanded == false);
		ui.keyDown(Key.ENTER, 0);
		check("combobox: Enter with none highlighted submits the text", chosen[chosen.length - 1] == "Brusselsx", chosen.join(","));
	}

	static function toasts() {
		var ui = new Ui(new MonoText(), 400, 300);
		var undone = 0, more = signal(false), section = signal(-1);
		Render.render(<view padding={10} row-gap={10} align-items="start">
			<view tag="focus-here" focusable width={20} height={20}/>
			<Disclosure tag="more" label="More" open={more}><text tag="more-text">Details</text></Disclosure>
			<Accordion tag="faq" open={section} sections={[{label: "One", render: () -> <text>First</text>}, {label: "Two", render: () -> <text>Second</text>}]}/>
			<Toaster/>
		</view>, ui.root);
		ui.update();
		function click(n:Node) {
			ui.update();
			var x = n.absX + n.width / 2, y = n.absY + n.height / 2;
			ui.pointerDown(x, y, 1);
			ui.pointerUp(x, y, 1);
			ui.update();
		}
		var summary = ui.root.find("more-summary");
		check("disclosure: closed at first", ui.root.find("more-text") == null && summary.semantics.expanded == false);
		click(summary);
		check("disclosure: a click opens it", more.value && ui.root.find("more-text") != null && summary.semantics.expanded == true);
		ui.setFocus(summary);
		ui.keyDown(Key.SPACE, 0);
		ui.update();
		check("disclosure: Space closes it", !more.value && ui.root.find("more-text") == null);
		click(ui.root.find("faq-1-summary"));
		check("accordion: a click opens a section", section.value == 1 && ui.root.find("faq-1-content") != null && ui.root.find("faq-0-content") == null);
		click(ui.root.find("faq-0-summary"));
		check("accordion: opening one closes the other", section.value == 0 && ui.root.find("faq-0-content") != null && ui.root.find("faq-1-content") == null);
		click(ui.root.find("faq-0-summary"));
		check("accordion: a click on the open one closes it", section.value == -1 && ui.root.find("faq-0-content") == null);

		var focus = ui.root.find("focus-here");
		ui.setFocus(focus);
		Clock.tick(500);
		Toasts.show("Saved", {kind: "success"});
		Toasts.show("Deleted 3 items", {action: "Undo", onAction: () -> undone++, duration: 10});
		ui.update();
		var list = ui.overlay.find("toaster-list");
		var toasts = list == null ? [] : tagged(list, "toast");
		check("toasts: shown in the bottom right corner, the newest last, the focus kept", toasts.length == 2 && list.absX + list.width == 400 - 16
			&& list.absY + list.height == 300 - 16 && toasts[0].absY < toasts[1].absY && ui.focus == focus, list == null ? "none" : '${list.absX} ${list.absY} ${list.width} ${list.height}');
		Clock.tick(500.1);
		var l = ui.overlay.find("toaster-list");
		ui.pointerMove(l.absX + 10, l.absY + 10);
		Clock.tick(504.2);
		ui.update();
		check("toasts: the pointer over them holds their time", Toasts.shown.value.length == 2 && Toasts.paused);
		ui.pointerMove(5, 5);
		Clock.tick(504.3);
		Clock.tick(508.3);
		ui.update();
		check("toasts: one goes after its time", Toasts.shown.value.length == 1 && tagged(ui.overlay, "toast").length == 1);
		click(tagged(ui.overlay, "toast-action")[0]);
		check("toasts: its action runs and closes it", undone == 1 && Toasts.shown.value.length == 0 && ui.overlay.children.length == 0 && ui.focus == focus,
			'$undone ${Toasts.shown.value.length} ${ui.focus}');
		var t = Toasts.show("Stays", {duration: 0});
		ui.update();
		Clock.finish();
		ui.update();
		check("toasts: duration 0 stays until closed", Toasts.shown.value.length == 1 && !Clock.active);
		click(tagged(ui.overlay, "toast-close")[0]);
		check("toasts: the close button", t.closed && ui.overlay.children.length == 0);
	}

	static function rightToLeft() {
		var ui = new Ui(new MonoText(), 300, 200);
		var dir = signal("rtl"), vol = signal(0.0), name = signal("Ada");
		Render.render(<view dir={dir} padding={10} row-gap={6}>
			<Slider tag="vol" value={vol} width={100} step={0.1}/>
			<view tag="row" direction="row" column-gap={4}><view tag="a" width={40} height={20}/><view tag="b" width={30} height={20}/></view>
			<text tag="words">Hello</text>
			<Field tag="name" value={name}/>
		</view>, ui.root);
		ui.update();
		var a = ui.root.find("a"), b = ui.root.find("b"), words = ui.root.find("words");
		check("rtl: a row from the right, in markup (dir=\"rtl\")", a.absX == 300 - 10 - 40 && b.absX == a.absX - 4 - 30, a.absX + " " + b.absX);
		check("rtl: text aligned to the right by default", words.textAlign() == Right);
		var slider = ui.root.find("vol"), knob = slider.children[1].children[1];
		check("rtl: a slider's minimum at the right", knob.absX == slider.absX + 100 - 16, knob.absX + " " + slider.absX);
		ui.setFocus(slider);
		ui.keyDown(Key.LEFT, 0);
		ui.update();
		check("rtl: Left raises a slider, its knob moves left", vol.value == 0.1 && knob.absX < slider.absX + 100 - 16, vol.value + " " + knob.absX);
		// (a field's text at its right, short of the caret's pixel: a click in its middle between its letters)
		var field:TextField = cast ui.root.find("name");
		var p = field.laidOut(), right = field.absX + field.width - field.style.borderEdges.right - field.style.padding.right - 1;
		ui.pointerDown(right - p.width / 2, field.absY + field.height / 2, 1);
		ui.pointerUp(right - p.width / 2, field.absY + field.height / 2, 1);
		check("rtl: a field's text at the right, clicked there", field.caret == 1 || field.caret == 2, "" + field.caret);
		dir.value = "ltr";
		ui.update();
		check("rtl: changed back, laid out again", ui.root.find("a").absX == 10 && words.textAlign() == Left, "" + ui.root.find("a").absX);
	}

	// auto margins from markup ("auto") and code (Edges.AUTO)
	static function autoMargins() {
		var ui = new Ui(new MonoText(), 300, 200);
		Render.render(<view>
			<view direction="row" height={30}><view tag="a" width={40} height={20}/><view tag="b" width={40} height={20} margin="0 0 0 auto"/></view>
			<view tag="c" width={100} height={20} margin={[0, Edges.AUTO]}/>
		</view>, ui.root);
		ui.update();
		var b = ui.root.find("b"), c = ui.root.find("c");
		check("auto margins: a row's item pushed to the end (markup)", b.absX == 260, "" + b.absX);
		check("auto margins: centred across a column (Edges.AUTO)", c.absX == 100, "" + c.absX);
	}

	// the shorthands' markup forms
	static function shorthands() {
		var ui = new Ui(new MonoText(), 300, 200);
		Render.render(<view tag="holder" gap="4 8" height={200}>
			<view tag="none" flex="none" width={20}/>
			<view tag="fill" flex="2 0 40px"/>
			<view tag="abs" position="absolute" inset="5 10"/>
		</view>, ui.root);
		ui.update();
		var holder = ui.root.find("holder"), none = ui.root.find("none"), fill = ui.root.find("fill"), abs = ui.root.find("abs");
		check("shorthands: gap \"4 8\"", holder.style.rowGap == 4 && holder.style.columnGap == 8);
		check("shorthands: flex none and three values", none.style.grow == 0 && none.style.shrink == 0 && fill.style.grow == 2 && fill.style.shrink == 0
			&& fill.style.basis.resolve(0) == 40);
		check("shorthands: inset \"5 10\"", abs.absX == 10 && abs.absY == 5 && abs.width == 280 && abs.height == 190, abs.absX + " " + abs.absY + " " + abs.width + " " + abs.height);
	}

	// align-items: baseline: texts of two sizes on one baseline (MonoText's: four fifths down a line)
	static function baselines() {
		var ui = new Ui(new MonoText(), 300, 200);
		Render.render(<view direction="row" align-items="baseline" line-height={1}>
			<text tag="small" font-size={10}>small</text>
			<text tag="big" font-size={20}>big</text>
			<view tag="box" width={10} height={5}/>
		</view>, ui.root);
		ui.update();
		var small = ui.root.find("small"), big = ui.root.find("big"), box = ui.root.find("box");
		check("baselines: the texts' baselines level", big.absY == 0 && small.absY == 8, small.absY + " " + big.absY);
		check("baselines: a box without text on its bottom edge", box.absY + 5 == 16, "" + box.absY);
	}

	// overflow-wrap and word-break: inherited into the text's font (what the engine breaks lines by)
	static function wordBreaks() {
		var ui = new Ui(new MonoText(), 300, 200);
		var wb = signal("break-all");
		Render.render(<view overflow-wrap="anywhere" word-break={wb}>
			<text tag="t">abc</text>
			<view overflow-wrap="normal"><text tag="u">def</text></view>
		</view>, ui.root);
		ui.update();
		var t = ui.root.find("t").font(), u = ui.root.find("u").font();
		check("breaks: overflow-wrap and word-break inherited into the font", t.overflowWrap == Anywhere && t.wordBreak == BreakAll && u.overflowWrap == Normal
			&& u.wordBreak == BreakAll);
		check("breaks: break-word and normal at the root", new Ui(new MonoText(), 10, 10).root.font().overflowWrap == BreakWord);
		wb.value = "keep-all";
		ui.update();
		check("breaks: changed, the font follows", ui.root.find("u").font().wordBreak == KeepAll);
	}

	static function numbers() {
		var ui = new Ui(new MonoText(), 400, 300);
		var qty = signal(2.0), price = signal(1.5);
		Render.render(<view padding={10} row-gap={10} align-items="start">
			<NumberField tag="qty" value={qty} min={0} max={10} label="Quantity"/>
			<NumberField tag="price" value={price} step={0.25} min={0} label="Price"/>
		</view>, ui.root);
		ui.update();
		var field:TextField = cast ui.root.find("qty");
		function click(n:Node) {
			ui.update();
			var x = n.absX + n.width / 2, y = n.absY + n.height / 2;
			ui.pointerDown(x, y, 1);
			ui.pointerUp(x, y, 1);
			ui.update();
		}
		check("number field: its value as text", field.text == "2" && (cast ui.root.find("price") : TextField).text == "1.5");
		ui.setFocus(field);
		ui.keyDown(Key.UP, 0);
		ui.keyDown(Key.UP, 0);
		ui.update();
		check("number field: Up steps", qty.value == 4 && field.text == "4", field.text);
		ui.keyDown(Key.PAGE_UP, 0);
		ui.update();
		check("number field: Page Up by ten steps, within max", qty.value == 10 && field.text == "10", field.text);
		field.select(0, field.text.length);
		ui.textInput("7");
		ui.update();
		check("number field: typed, the value follows", qty.value == 7 && field.text == "7");
		ui.textInput("5");
		ui.update();
		check("number field: typed past max, kept while typing", qty.value == 75 && field.text == "75");
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		check("number field: Enter puts it within max", qty.value == 10 && field.text == "10", field.text);
		click(ui.root.find("qty-down"));
		check("number field: the buttons step", qty.value == 9 && field.text == "9", field.text);
		var p:TextField = cast ui.root.find("price");
		ui.setFocus(p);
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.DOWN, 0);
		ui.update();
		check("number field: a fractional step", price.value == 0.75 && p.text == "0.75", p.text);
		p.select(0, p.text.length);
		ui.textInput("-3");
		ui.setFocus(field);
		ui.update();
		check("number field: the focus leaving puts it within min", price.value == 0 && p.text == "0", p.text);
		var t = ui.accessTree(), an = t.nodes.get(t.focus);
		check("number field: a spin button to assistive technology", an.role == SpinButton && an.valueNow == 9 && an.valueMin == 0 && an.valueMax == 10
			&& an.value == "9" && an.editable() && an.name == "Quantity", an.role + " " + an.valueNow + " " + an.value);
		ui.setFocus(field);
		field.select(0, field.text.length);
		ui.textInput("2.5");
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		check("number field: a value off the steps shown as it is", qty.value == 2.5 && field.text == "2.5", field.text);
		ui.keyDown(Key.UP, 0);
		ui.update();
		check("number field: stepped from there", qty.value == 3.5 && field.text == "3.5", field.text);
	}

	static function listbox() {
		var ui = new Ui(new MonoText(), 400, 400);
		var picked = signal(["b"]), many = signal(new Array<String>()), activated = [];
		Render.render(<view padding={10} row-gap={10}>
			<Listbox tag="one" options={["apple", "b", "cherry", "date"]} selected={picked} label="Fruit" onActivate={o -> activated.push(o)}/>
			<Listbox tag="many" options={["red", "green", "blue", "gold"]} selected={many} multiple label="Colours"/>
		</view>, ui.root);
		ui.update();
		function key(k:Int, mods = 0) {
			ui.keyDown(k, mods);
			ui.update();
		}
		// (a modifier held down for the click)
		function click(n:Node, mods = 0) {
			var held = mods == Key.MOD_SHIFT ? Key.SHIFT : mods == Key.MOD_CONTROL ? Key.CONTROL : 0;
			if (held != 0) ui.keyDown(held, 0);
			ui.pointerDown(n.absX + 4, n.absY + 4, 1);
			ui.pointerUp(n.absX + 4, n.absY + 4, 1);
			if (held != 0) ui.keyUp(held, mods);
			ui.update();
		}
		var b = ui.root.find("one-b");
		check("listbox: one Tab stop, the selected option", b.focusable && !ui.root.find("one-apple").focusable && !ui.root.find("many-green").focusable
			&& ui.root.find("many-red").focusable);
		ui.setFocus(b);
		key(Key.DOWN);
		check("listbox: Down selects the next", picked.value.join(",") == "cherry" && ui.focus == ui.root.find("one-cherry") && !b.focusable, picked.value.join(","));
		key("d".code);
		key(Key.HOME);
		check("listbox: a letter typed, Home", picked.value.join(",") == "apple" && ui.focus == ui.root.find("one-apple"), picked.value.join(","));
		key(Key.ENTER);
		click(ui.root.find("one-date"));
		click(ui.root.find("one-date"));
		check("listbox: Enter and a double click activate", activated.join(",") == "apple,date" && picked.value.join(",") == "date", activated.join(","));
		var red = ui.root.find("many-red");
		click(red);
		key(Key.DOWN, Key.MOD_SHIFT);
		key(Key.DOWN, Key.MOD_SHIFT);
		check("listbox: multiple, Shift extends from the anchor", many.value.join(",") == "red,green,blue", many.value.join(","));
		key(Key.UP, Key.MOD_CONTROL);
		key(Key.SPACE);
		check("listbox: Control moves without selecting, Space takes one away", many.value.join(",") == "red,blue" && ui.focus == ui.root.find("many-green"),
			many.value.join(","));
		click(ui.root.find("many-gold"), Key.MOD_CONTROL);
		click(red, Key.MOD_CONTROL);
		check("listbox: Control clicks add and take away", many.value.join(",") == "blue,gold", many.value.join(","));
		click(ui.root.find("many-green"), Key.MOD_SHIFT);
		check("listbox: a Shift click extends from the last one clicked", many.value.join(",") == "red,green", many.value.join(","));
		key("a".code, Key.MOD_CONTROL);
		var t = ui.accessTree(), boxes = [for (id in t.order) if (t.nodes.get(id).role == ListBox) t.nodes.get(id)];
		var options = [for (id in t.order) if (t.nodes.get(id).role == ListBoxOption && t.nodes.get(id).selected == true) t.nodes.get(id).name];
		check("listbox: Control+A, the roles, multiselectable", many.value.length == 4 && boxes.length == 2 && !boxes[0].multiselectable
			&& boxes[1].multiselectable && boxes[1].toJson().multiselectable == true && options.join(",") == "date,red,green,blue,gold", options.join(","));
	}

	static function toolbar() {
		var ui = new Ui(new MonoText(), 400, 300);
		var pressed = [];
		Render.render(<view padding={10} row-gap={10}>
			<Toolbar tag="tools" label="Format">
				<Button tag="bold" label="B" onClick={() -> pressed.push("bold")}/>
				<Button tag="italic" label="I" onClick={() -> pressed.push("italic")}/>
				<view><Button tag="under" label="U" onClick={() -> pressed.push("under")}/></view>
			</Toolbar>
			<Button tag="after" label="After"/>
		</view>, ui.root);
		ui.update();
		var bold = ui.root.find("bold"), italic = ui.root.find("italic"), under = ui.root.find("under");
		function key(k:Int, mods = 0) {
			ui.keyDown(k, mods);
			ui.update();
		}
		check("toolbar: one Tab stop, the first, a toolbar role", bold.focusable && !italic.focusable && !under.focusable
			&& ui.root.find("tools").semantics.role == Toolbar);
		ui.setFocus(bold);
		key(Key.RIGHT);
		key(Key.RIGHT);
		check("toolbar: Right moves through them (into a child)", ui.focus == under && under.focusable && !bold.focusable);
		key(Key.RIGHT);
		check("toolbar: wrapping", ui.focus == bold);
		key(Key.END);
		key(Key.LEFT);
		key(Key.TAB);
		check("toolbar: End, Left, then Tab out", ui.focus == ui.root.find("after") && italic.focusable && !bold.focusable && !under.focusable);
		key(Key.TAB, Key.MOD_SHIFT);
		check("toolbar: back in, on the last focused", ui.focus == italic);
		ui.pointerDown(under.absX + 2, under.absY + 2, 1);
		ui.pointerUp(under.absX + 2, under.absY + 2, 1);
		ui.update();
		check("toolbar: a click focuses and presses it", ui.focus == under && pressed.join(",") == "under", pressed.join(","));
	}

	// a segmented control, breadcrumbs and pagination: roles, keys, clicks, the current one
	static function navigation() {
		var ui = new Ui(new MonoText(), 500, 300);
		var view = signal("Day"), page = signal(1), chosen = [];
		Render.render(<view padding={10} row-gap={10}>
			<SegmentedControl tag="seg" label="View" value={view} options={["Day", "Week", "Month"]}/>
			<Breadcrumbs tag="crumbs" items={["Home", "Docs", "Layout"]} onSelect={i -> chosen.push(i)}/>
			<Pagination tag="pages" page={page} count={10}/>
		</view>, ui.root);
		ui.update();
		function key(k:Int) {
			ui.keyDown(k, 0);
			ui.update();
		}
		function click(n:Node) {
			ui.pointerDown(n.absX + 2, n.absY + 2, 1);
			ui.pointerUp(n.absX + 2, n.absY + 2, 1);
			ui.update();
		}
		var seg0 = ui.root.find("seg-0"), seg2 = ui.root.find("seg-2");
		check("segments: a radio group, one Tab stop", ui.root.find("seg").semantics.role == RadioGroup && seg0.focusable && !seg2.focusable);
		ui.setFocus(seg0);
		key(Key.LEFT);
		check("segments: Left wraps to the last, chosen", view.value == "Month" && ui.focus == seg2 && seg2.focusable && !seg0.focusable);
		click(ui.root.find("seg-1"));
		check("segments: a click chooses", view.value == "Week");
		var t = ui.accessTree(), navs = [for (id in t.order) if (t.nodes.get(id).role == Navigation) t.nodes.get(id)];
		var current = [for (id in t.order) if (t.nodes.get(id).current) t.nodes.get(id).name];
		check("navigation: two landmarks, the last crumb and page 1 current", navs.length == 2 && navs[0].name == "Breadcrumb" && navs[0].toJson().role == "navigation"
			&& current.join(",") == "Layout,1", current.join(","));
		click(ui.root.find("crumbs-1"));
		ui.setFocus(ui.root.find("crumbs-0"));
		key(Key.ENTER);
		check("breadcrumbs: a click and Enter choose a step", chosen.join(",") == "1,0", chosen.join(","));
		var prev = ui.root.find("pages-prev"), next = ui.root.find("pages-next");
		function labels():String
			return [for (n in tagged(ui.root.find("pages"), "pages-page")) (cast n.children[0] : TextNode).text].join(" ");
		check("pagination: Previous disabled at the first, the pages shown", !prev.focusable && labels() == "1 2 10", labels());
		click(next);
		click(next);
		click(next);
		check("pagination: Next to page 4, a gap filled by its page", page.value == 4 && labels() == "1 2 3 4 5 10" && prev.focusable, labels());
		page.value = 7;
		ui.update();
		check("pagination: page 7, a gap before, a lone page after shown", labels() == "1 6 7 8 9 10" && tagged(ui.root.find("pages"), "pages-page").length == 6, labels());
		page.value = 10;
		ui.update();
		check("pagination: Next disabled at the last", !next.focusable && labels() == "1 9 10", labels());
	}

	static function colorPicker() {
		var ui = new Ui(new MonoText(), 400, 400);
		var color = signal(Color.rgb(0x3366CC));
		Render.render(<view padding={10}><ColorPicker tag="cp" value={color} size={100}/></view>, ui.root);
		ui.update();
		var area = ui.root.find("cp-area"), strip = ui.root.find("cp-hue"), field:TextField = cast ui.root.find("cp-hex");
		var hue = strip.semantics.valueNow;
		check("color picker: the value's hue, saturation and brightness, its hex", hue == 220 && area.semantics.valueNow == 75 && field.text == "#3366CC"
			&& area.semantics.valueText == "saturation 75%, brightness 80%", hue + " " + area.semantics.valueText + " " + field.text);
		ui.setFocus(area);
		ui.keyDown(Key.DOWN, Key.MOD_SHIFT);
		ui.update();
		check("color picker: Shift+Down, ten points darker", area.semantics.valueText == "saturation 75%, brightness 70%" && color.value == Color.rgb(0x2D59B3)
			&& field.text == "#2D59B3", area.semantics.valueText + " " + color.value.toHex());
		// a drag past the area's top right: full saturation and brightness
		ui.pointerDown(area.absX + 50, area.absY + 50, 1);
		ui.pointerMove(area.absX + 150, area.absY - 50);
		ui.pointerUp(area.absX + 150, area.absY - 50, 1);
		ui.update();
		check("color picker: a drag in the area, held to it", color.value == Color.rgb(0x0055FF) && strip.semantics.valueNow == 220, color.value.toHex());
		ui.pointerDown(area.absX + 50, area.absY + 50, 1);
		ui.pointerMove(area.absX + 50, area.absY + 150);
		ui.pointerUp(area.absX + 50, area.absY + 150, 1);
		ui.setFocus(strip);
		ui.keyDown(Key.HOME, 0);
		ui.update();
		check("color picker: black keeps the hue, Home on the strip sets it", color.value == Color.rgb(0) && strip.semantics.valueNow == 0, color.value.toHex());
		ui.keyDown(Key.UP, 0);
		ui.setFocus(field);
		field.selectAll();
		ui.textInput("#0f0");
		ui.update();
		check("color picker: a colour typed in the field", color.value == Color.rgb(0x00FF00) && strip.semantics.valueNow == 120 && field.text == "#0f0",
			color.value.toHex() + " " + field.text);
		color.value = Color.rgb(0x808080);
		ui.update();
		check("color picker: set from outside, a grey: its hue kept", strip.semantics.valueNow == 120 && area.semantics.valueNow == 0 && field.text == "#808080",
			strip.semantics.valueNow + " " + field.text);
	}

	static function sortable() {
		var ui = new Ui(new MonoText(), 400, 400);
		var items = signal(["a", "b", "c", "d"]), moves = [];
		Render.render(<view padding={10}><Sortable tag="s" items={items} render={(s:String) -> <text tag={"s-" + s}>{s}</text>}
			onMove={(s, i) -> moves.push(s + i)} label="Order"/></view>, ui.root);
		ui.update();
		function item(s:String):Node
			return ui.root.find("s-" + s).parent;
		function key(k:Int, mods = 0) {
			ui.keyDown(k, mods);
			ui.update();
		}
		check("sortable: a list, one Tab stop", ui.root.find("s").semantics.role == List && item("a").focusable && !item("b").focusable);
		ui.setFocus(item("a"));
		key(Key.DOWN, Key.MOD_ALT);
		var live:TextNode = cast ui.root.find("s-live").children[0];
		check("sortable: Alt+Down moves the item, the focus with it, a live region says it", items.value.join("") == "bacd" && ui.focus == item("a")
			&& item("a").focusable && !item("b").focusable && item("a").absY > item("b").absY && live.text == "Moved a to position 2 of 4",
			items.value.join("") + " " + live.text);
		key(Key.DOWN);
		key(Key.UP, Key.MOD_ALT);
		key(Key.UP, Key.MOD_ALT);
		key(Key.UP, Key.MOD_ALT);
		check("sortable: Down to the next, Alt+Up, not past the top", items.value.join("") == "cbad" && ui.focus == item("c") && moves.join(",") == "a1,c1,c0",
			items.value.join("") + " " + moves.join(","));
		// d dragged over the top half of b, then dropped
		var d = item("d"), b = item("b");
		ui.pointerDown(d.absX + 20, d.absY + d.height / 2, 1);
		ui.pointerMove(d.absX + 20, d.absY + d.height / 2 - 10);
		ui.pointerMove(b.absX + 20, b.absY + 2);
		ui.update();
		var line = [for (c in b.children) if (c.style.position == Absolute && c.style.display != None) c];
		check("sortable: a line where it will go, above it, the hand closed", line.length == 1 && line[0].absY < b.absY && ui.cursor() == Grabbing, "" + line.length);
		ui.pointerUp(b.absX + 20, b.absY + 2, 1);
		ui.update();
		check("sortable: dropped before it", items.value.join("") == "cdba" && moves[moves.length - 1] == "d1", items.value.join(""));
		var c = item("c"), a = item("a");
		ui.pointerDown(c.absX + 20, c.absY + c.height / 2, 1);
		ui.pointerMove(c.absX + 20, c.absY + c.height / 2 + 10);
		ui.pointerMove(a.absX + 20, a.absY + a.height - 2);
		ui.pointerUp(a.absX + 20, a.absY + a.height - 2, 1);
		ui.update();
		check("sortable: dropped after the last", items.value.join("") == "dbac", items.value.join(""));
	}

	static function rangeSlider() {
		var ui = new Ui(new MonoText(), 400, 300);
		var low = signal(0.2), high = signal(0.8), rtl = signal(false);
		Render.render(<view padding={10} dir={() -> rtl.value ? "rtl" : "ltr"}><RangeSlider tag="r" low={low} high={high} step={0.1} width={116}
			label="Price"/></view>, ui.root);
		ui.update();
		var r = ui.root.find("r"), a = ui.root.find("r-low"), b = ui.root.find("r-high");
		check("range slider: the knobs at their values", a.absX == r.absX + 20 && b.absX == r.absX + 80, a.absX - r.absX + " " + (b.absX - r.absX));
		var y = r.absY + r.height / 2;
		ui.pointerDown(r.absX + 8 + 30, y, 1);
		ui.update();
		check("range slider: a press moves the nearer knob and focuses it", low.value == 0.3 && high.value == 0.8 && ui.focus == a, low.value + " " + ui.focus);
		ui.pointerMove(r.absX + 8 + 95, y);
		ui.pointerUp(r.absX + 8 + 95, y, 1);
		ui.update();
		check("range slider: dragged past the other, held at it", low.value == 0.8 && high.value == 0.8, low.value + " " + high.value);
		ui.setFocus(b);
		ui.keyDown(Key.RIGHT, 0);
		ui.keyDown(Key.HOME, 0);
		ui.update();
		check("range slider: the keys, Home only as far as the other knob", high.value == 0.8 && low.value == 0.8, high.value + "");
		ui.keyDown(Key.END, 0);
		ui.setFocus(a);
		ui.keyDown(Key.HOME, 0);
		rtl.value = true;
		ui.update();
		var t = ui.accessTree(), sliders = [for (id in t.order) if (t.nodes.get(id).role == Slider) t.nodes.get(id)];
		check("range slider: right to left, the minimum at the right; two sliders, each bounded by the other",
			a.absX == r.absX + 116 - 16 && b.absX == r.absX && sliders.length == 2 && sliders[0].valueMax == 1 && sliders[1].valueMin == 0
			&& sliders[0].name == "Price: minimum", a.absX - r.absX + " " + (b.absX - r.absX) + " " + sliders.length);
	}

	static function liveRegions() {
		var ui = new Ui(new MonoText(), 400, 300);
		var msg = signal("");
		Render.render(<view padding={10}><view tag="status" live="polite"><text>{msg}</text></view><Toaster/></view>, ui.root);
		ui.update();
		var t0 = ui.accessTree();
		msg.value = "Saved";
		ui.update();
		var t1 = ui.accessTree();
		var said = t1.announcements(t0);
		var region = [for (id in t1.order) if (t1.nodes.get(id).live == Polite) t1.nodes.get(id)];
		check("live: a region's new text announced, politely", said.length == 1 && said[0].text == "Saved" && said[0].live == Polite
			&& region.length == 2 && region[0].toJson().live == "polite" && region[0].role == Group, [for (s in said) s.text].join("|"));
		msg.value = "Saved and synced";
		ui.update();
		var t2 = ui.accessTree();
		check("live: what was added at its end; nothing when nothing changed", [for (s in t2.announcements(t1)) s.text].join("|") == "and synced"
			&& ui.accessTree().announcements(t2).length == 0, [for (s in t2.announcements(t1)) s.text].join("|"));
		hxmc.ui.widgets.Toasts.show("Deleted 3 files");
		ui.update();
		var t3 = ui.accessTree();
		check("live: a toast announced (the toaster's region, there before it)", [for (s in t3.announcements(t2)) s.text].join("|") == "Deleted 3 files",
			[for (s in t3.announcements(t2)) s.text].join("|"));
		for (t in hxmc.ui.widgets.Toasts.shown.peek().copy())
			hxmc.ui.widgets.Toasts.close(t);
	}

	static function password() {
		var ui = new Ui(new MonoText(), 400, 300);
		var pw = signal("hunter2");
		Render.render(<view padding={10}><Field tag="pw" value={pw} password label="Password"/></view>, ui.root);
		ui.update();
		var f:TextField = cast ui.root.find("pw");
		var clip:hxmc.ui.ClipboardHost.MemoryClipboard = cast ui.clipboard;
		clip.text = "before";
		ui.setFocus(f);
		f.selectAll();
		ui.keyDown("c".code, Key.MOD_CONTROL);
		ui.keyDown("x".code, Key.MOD_CONTROL);
		var t = ui.accessTree(), node = [for (id in t.order) if (t.nodes.get(id).role == TextInput) t.nodes.get(id)][0];
		check("password: shown and given as dots, not copied or cut", (cast f.layoutText(ui.text, Math.NaN) : MonoText.MonoParagraph).width == 7 * 7
			&& clip.text == "before" && pw.value == "hunter2" && node.secret && node.value == "•••••••" && node.toJson().secret == true, node.value);
		f.select(3, 3);
		ui.keyDown(Key.LEFT, Key.MOD_CONTROL);
		check("password: a word is all of it", f.caret == 0, "" + f.caret);
	}

	static function typeAhead() {
		var ui = new Ui(new MonoText(), 400, 300);
		var fruit = signal("Apple"), chosen = [];
		var t = 50.0;
		Ui.now = () -> t;
		Render.render(<view padding={10} row-gap={10} align-items="start"><Select tag="f" value={fruit} options={["Apple", "Banana", "Blueberry", "Cherry"]}/>
			<Menu tag="m" label="Edit" items={[{label: "Copy", onSelect: () -> chosen.push("copy")}, {label: "Cut", onSelect: () -> chosen.push("cut")},
				{label: "Paste", onSelect: () -> chosen.push("paste")}]}/></view>, ui.root);
		ui.update();
		function type(c:String) {
			ui.keyDown(c.charCodeAt(0), 0);
			ui.update();
		}
		ui.setFocus(ui.root.find("f"));
		type("c");
		check("type-ahead: a select's option chosen by its first letter", fruit.value == "Cherry", fruit.value);
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		t = 52;
		type("b");
		t = 52.3;
		type("l");
		check("type-ahead: letters typed together, the option they start", ui.focus == ui.overlay.find("f-Blueberry"), "" + ui.focus);
		t = 54;
		type("b");
		check("type-ahead: the same letter again, the next with it", ui.focus == ui.overlay.find("f-Banana"), "" + ui.focus);
		ui.keyDown(Key.ESCAPE, 0);
		ui.setFocus(ui.root.find("m"));
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		t = 56;
		type("p");
		ui.keyDown(Key.ENTER, 0);
		check("type-ahead: in a menu", chosen.join(",") == "paste", chosen.join(","));
		Ui.now = haxe.Timer.stamp;
	}

	static function indeterminate() {
		var ui = new Ui(new MonoText(), 400, 300);
		var v:Signal<Null<Float>> = signal(null);
		Render.render(<view padding={10}><Progress tag="p" value={v} width={100}/></view>, ui.root);
		ui.update();
		Clock.tick(100);
		Clock.tick(100.75);
		ui.update();
		var slide = ui.root.find("progress-slide"), bar = ui.root.find("p");
		var t = ui.accessTree(), node = [for (id in t.order) if (t.nodes.get(id).role == ProgressIndicator) t.nodes.get(id)][0];
		check("progress: not known, a bar sliding across, no value", slide != null && slide.absX == bar.absX + 30 && slide.width == 40 && node.valueNow == null,
			slide == null ? "none" : slide.absX + " " + slide.width);
		v.value = 0.5;
		ui.update();
		check("progress: known again, the bar its value, the clock left", ui.root.find("progress-slide") == null && !Clock.tick(101) && node != null);
	}

	static function mixedCheckbox() {
		var ui = new Ui(new MonoText(), 400, 300);
		var on = signal(false), some = signal(true);
		Render.render(<view padding={10}><Checkbox tag="all" checked={on} mixed={some} label="All"/></view>, ui.root);
		ui.update();
		function json():Dynamic {
			var t = ui.accessTree();
			for (id in t.order)
				if (t.nodes.get(id).role == CheckBox) return t.nodes.get(id).toJson();
			return null;
		}
		var before:Dynamic = json().checked;
		var box = ui.root.find("all");
		ui.pointerDown(box.absX + 4, box.absY + 4, 1);
		ui.pointerUp(box.absX + 4, box.absY + 4, 1);
		ui.update();
		check("checkbox: mixed (ARIA's), checked once clicked", before == "mixed" && on.value && !some.value && json().checked == true, Std.string(before));
	}

	static function tabs() {
		var ui = new Ui(new MonoText(), 400, 300);
		var selected = signal(1);
		Render.render(<view padding={10}><Button tag="before" label="Before"/><Tabs tag="t" labels={["One", "Two", "Three"]} selected={selected}
			render={i -> <text tag="panel">{"panel " + i}</text>}/><Button tag="after" label="After"/></view>, ui.root);
		ui.update();
		var before = ui.root.find("before");
		ui.setFocus(before);
		ui.keyDown(Key.TAB, 0);
		check("tabs: one stop for Tab, the selected tab", ui.focus == ui.root.find("t-1"));
		ui.keyDown(Key.RIGHT, 0);
		ui.update();
		check("tabs: Right selects the next, the focus with it", selected.value == 2 && ui.focus == ui.root.find("t-2")
			&& (cast ui.root.find("panel") : TextNode).text == "panel 2");
		ui.keyDown(Key.RIGHT, 0);
		ui.keyDown(Key.END, 0);
		ui.keyDown(Key.LEFT, 0);
		check("tabs: wrapping, End, Left", selected.value == 1, "" + selected.value);
		ui.keyDown(Key.TAB, 0);
		check("tabs: Tab out of them", ui.focus == ui.root.find("after"));
		ui.root.style.dir = Rtl;
		ui.update();
		ui.setFocus(ui.root.find("t-1"));
		ui.keyDown(Key.LEFT, 0);
		check("tabs: right to left, Left to the next", selected.value == 2, "" + selected.value);
		// a radio group: one stop, the arrows check the next
		var ui2 = new Ui(new MonoText(), 400, 300), size = signal("");
		Render.render(<view padding={10}><Button tag="b" label="B"/><Radio tag="r" value={size} options={["S", "M", "L"]}/><Button tag="c" label="C"/></view>, ui2.root);
		ui2.update();
		ui2.setFocus(ui2.root.find("b"));
		ui2.keyDown(Key.TAB, 0);
		var first = ui2.focus == ui2.root.find("r-S");
		ui2.keyDown(Key.DOWN, 0);
		ui2.keyDown(Key.DOWN, 0);
		ui2.keyDown(Key.DOWN, 0);
		check("radio: one stop (the first, none checked), Down checks the next, wrapping", first && size.value == "S" && ui2.focus == ui2.root.find("r-S"),
			size.value);
		ui2.keyDown(Key.UP, 0);
		ui2.keyDown(Key.TAB, 0);
		check("radio: Up, then Tab out", size.value == "L" && ui2.focus == ui2.root.find("c"), size.value);
	}

	static function menubar() {
		var ui = new Ui(new MonoText(), 400, 300);
		var chosen = [];
		Render.render(<view padding={10} align-items="start"><Menubar tag="bar" label="Main" menus={[
			{label: "File", items: [{label: "New", onSelect: () -> chosen.push("new")}, {label: "Open", onSelect: () -> chosen.push("open")}]},
			{label: "Edit", items: [{label: "Undo", onSelect: () -> chosen.push("undo"), shortcut: "Mod+Z"}]},
			{label: "Help", items: [{label: "About", onSelect: () -> chosen.push("about")}]}
		]}/></view>, ui.root);
		ui.update();
		var file = ui.root.find("bar-0"), edit = ui.root.find("bar-1");
		function key(k:Int) {
			ui.keyDown(k, 0);
			ui.update();
		}
		function click(n:Node) {
			ui.pointerDown(n.absX + 4, n.absY + 4, 1);
			ui.pointerUp(n.absX + 4, n.absY + 4, 1);
			ui.update();
		}
		check("menubar: titles in a row, a menubar role", edit.absX > file.absX && ui.root.find("bar").semantics.role == MenuBar);
		click(file);
		check("menubar: a click opens its menu, the first item focused", ui.overlay.find("bar-0-items") != null && ui.focus == ui.overlay.find("bar-0-0"));
		ui.pointerMove(edit.absX + 4, edit.absY + 4);
		ui.update();
		check("menubar: the pointer over another title opens that one instead",
			ui.overlay.find("bar-0-items") == null && ui.overlay.find("bar-1-items") != null && ui.focus == ui.overlay.find("bar-1-0"));
		key(Key.RIGHT);
		check("menubar: Right from a menu opens the next", ui.overlay.find("bar-2-items") != null && ui.overlay.children.length == 1);
		key(Key.RIGHT);
		check("menubar: wrapping to the first", ui.overlay.find("bar-0-items") != null && ui.focus == ui.overlay.find("bar-0-0"));
		key(Key.DOWN);
		key(Key.ENTER);
		check("menubar: an item chosen, the menu closed, the focus back on its title", chosen.join(",") == "open" && ui.overlay.children.length == 0
			&& ui.focus == file, chosen.join(",") + " " + ui.focus);
		key(Key.RIGHT);
		check("menubar: Right on a title moves to the next, closed", ui.focus == edit && ui.overlay.children.length == 0);
		key(Key.DOWN);
		key(Key.ESCAPE);
		check("menubar: Escape closes it, the focus on its title", ui.overlay.children.length == 0 && ui.focus == edit);
		ui.setFocus(null);
		ui.keyDown("Z".code, Key.MOD_CONTROL);
		check("menubar: an item's shortcut from anywhere", chosen.join(",") == "open,undo", chosen.join(","));
		// right to left: Right to the title on the right, the one before
		ui.root.style.dir = Rtl;
		ui.update();
		ui.setFocus(edit);
		key(Key.RIGHT);
		check("menubar: right to left, Right to the title on its right", ui.focus == file && file.absX > edit.absX);
	}

	static function editMenus() {
		var ui = new Ui(new MonoText(), 400, 300);
		var text = signal("hello world");
		Render.render(<view padding={10}><Field tag="note" value={text}/></view>, ui.root);
		ui.update();
		var f:TextField = cast ui.root.find("note");
		ui.setFocus(f);
		f.select(6, 11);
		var r = f.layoutText(ui.text, Math.NaN).caret(8);
		var clip:hxmc.ui.ClipboardHost.MemoryClipboard = cast ui.clipboard;
		function press(button:Int, x:Float, y:Float) {
			ui.pointerDown(x, y, button);
			ui.pointerUp(x, y, button);
			ui.update();
		}
		press(3, f.absX + 9 + r.x, f.absY + 7 + r.y + 2);
		var menu = ui.overlay.find("note-menu-items");
		check("edit menu: a right click in the selection opens it, the selection kept", menu != null && f.selectionStart == 6 && f.selectionEnd == 11,
			'${menu} ${f.selectionStart}-${f.selectionEnd}');
		var copy = ui.overlay.find("note-menu-1");
		press(1, copy.absX + 4, copy.absY + 4);
		check("edit menu: Copy", clip.text == "world" && ui.overlay.children.length == 0 && ui.focus == f, clip.text);
		ui.keyDown(Key.END, 0);
		ui.keyDown(Key.MENU, 0);
		ui.update();
		var paste = ui.overlay.find("note-menu-2");
		press(1, paste.absX + 4, paste.absY + 4);
		check("edit menu: the menu key, Paste", text.value == "hello worldworld", text.value);
		ui.keyDown(Key.MENU, 0);
		ui.update();
		var all = ui.overlay.find("note-menu-3");
		press(1, all.absX + 4, all.absY + 4);
		ui.keyDown(Key.MENU, 0);
		ui.update();
		var cut = ui.overlay.find("note-menu-0");
		press(1, cut.absX + 4, cut.absY + 4);
		check("edit menu: Select All, Cut", text.value == "" && clip.text == "hello worldworld", text.value);
	}

	static function focusTips() {
		var ui = new Ui(new MonoText(), 400, 300);
		var log = [];
		Render.render(<view padding={20} row-gap={10} onFocusIn={e -> log.push("in " + e.target.tag)} onFocusOut={e -> log.push("out " + e.target.tag)}>
			<Button tag="first" label="First"/>
			<Tooltip tag="tip" text="Saves it" delay={0.5}><Button tag="save" label="Save"/></Tooltip>
		</view>, ui.root);
		ui.update();
		Clock.tick(1000);
		ui.keyDown(Key.TAB, 0);
		ui.keyDown(Key.TAB, 0);
		ui.update();
		check("focus in, focus out: bubbling", log.join(",") == "in first,out first,in save", log.join(","));
		Clock.tick(1000.1);
		Clock.tick(1000.7);
		ui.update();
		check("tooltip: shown for the keyboard's focus", ui.overlay.find("tooltip") != null);
		ui.keyDown(Key.ESCAPE, 0);
		ui.update();
		check("tooltip: Escape hides it, the focus kept", ui.overlay.find("tooltip") == null && ui.focus == ui.root.find("save"));
		ui.keyDown(Key.TAB, 0);
		ui.keyDown(Key.TAB, Key.MOD_SHIFT);
		Clock.tick(1001);
		Clock.tick(1001.7);
		ui.update();
		ui.keyDown(Key.TAB, 0);
		ui.update();
		check("tooltip: hidden when the focus leaves", ui.overlay.find("tooltip") == null);
		var save = ui.root.find("save");
		ui.pointerDown(save.absX + 4, save.absY + 4, 1);
		ui.pointerUp(save.absX + 4, save.absY + 4, 1);
		ui.pointerMove(390, 290);
		Clock.tick(1001);
		Clock.tick(1002);
		ui.update();
		check("tooltip: not for a click's focus", ui.focus == save && ui.overlay.find("tooltip") == null);
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
		// a column's edge dragged: its width, the rows' cells with it; not sorted by it; a double click its own again
		var head = ui.root.find("t-head-1"), grip = ui.root.find("t-resize-1"), sorted = names().join(",");
		var was = head.width, x = grip.absX + 4, y = grip.absY + 4;
		ui.pointerDown(x, y, 1);
		ui.pointerMove(x + 30, y);
		ui.pointerUp(x + 30, y, 1);
		ui.update();
		var cell = rowNodes()[0].children[1];
		check("table: a column dragged wider, its cells too, the order kept", head.width == was + 30 && cell.width == was + 30 && names().join(",") == sorted,
			head.width + " " + cell.width);
		t = 20;
		ui.pointerDown(grip.absX + 4, y, 1);
		ui.pointerUp(grip.absX + 4, y, 1);
		t = 20.2;
		ui.pointerDown(grip.absX + 4, y, 1);
		ui.pointerUp(grip.absX + 4, y, 1);
		ui.update();
		check("table: a double click on its edge, its own width again", head.width == was, "" + head.width);
		Ui.now = haxe.Timer.stamp;
	}

	static function tree() {
		var ui = new Ui(new MonoText(), 300, 300);
		ui.root.style.fontSize = 10;
		var kids = ["src" => ["main", "ui"], "ui" => ["Node", "Style"], "docs" => ["guide"]];
		var picked:Signal<Null<String>> = signal(null), open:Signal<Array<String>> = signal([]), opened = [];
		Render.render(<view padding={10}><Tree tag="tr" roots={["src", "docs", "README"]} children={(s:String) -> kids.get(s)} render={(s:String) -> s}
			text={(s:String) -> s} expanded={open} selected={picked} height={200} rowHeight={20} label="Files" onActivate={s -> opened.push(s)}/></view>, ui.root);
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
		// right to left: Right closes, Left opens (the way they point)
		ui.root.style.dir = Rtl;
		ui.update();
		ui.keyDown(Key.RIGHT, 0);
		ui.update();
		var closed = shown();
		ui.keyDown(Key.LEFT, 0);
		ui.update();
		check("tree: right to left, Right closes, Left opens", closed == "-src,  main,  +ui,+docs,README" && shown() == "-src,  main,  +ui,-docs,  guide,README",
			closed + " / " + shown());
		t = 30;
		ui.keyDown("g".code, 0);
		check("tree: type-ahead to the row its text starts", picked.value == "guide", "" + picked.value);
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
		// right to left: the first pane on the right; Left widens it, a drag moves the divider with the pointer
		ui.root.style.dir = Rtl;
		ui.update();
		ui.keyDown(Key.LEFT, 0);
		ui.update();
		check("split: right to left, the first pane on the right, Left widens it", size.value == 70 && side.absX == 400 - 70 && div.absX == 400 - 70 - 6,
			size.value + " " + side.absX);
		var x = div.absX + 3;
		ui.pointerDown(x, 100, 1);
		ui.pointerMove(x - 30, 100);
		ui.pointerUp(x - 30, 100, 1);
		check("split: right to left, dragged left, wider", size.value == 100, "" + size.value);
	}

	static function calendar() {
		check("days: the epoch, a leap day, a weekday", Days.of({year: 1970, month: 1, day: 1}) == 0
			&& Days.day(Days.of({year: 2000, month: 2, day: 29})).day == 29 && Days.weekday(Days.of({year: 2026, month: 10, day: 17})) == 6
			&& Days.day(Days.of({year: 1969, month: 12, day: 31})).year == 1969 && Days.length(2100, 2) == 28);
		var ui = new Ui(new MonoText(), 400, 400);
		ui.root.style.alignItems = Start;
		var picked:Signal<Null<Day>> = signal(null), chosen = [];
		var today:Day = {year: 2026, month: 10, day: 17};
		Render.render(<view><Calendar tag="cal" value={picked} today={today} onChoose={d -> chosen.push(d.day)}/></view>, ui.root);
		ui.update();
		function text(n:Node):String
			return n == null ? "" : Std.isOfType(n, TextNode) ? (cast n : TextNode).text : n.children.length > 0 ? text(n.children[0]) : "";
		var days = [];
		function collect(n:Node) {
			if (n.tag == "cal-day") days.push(n);
			for (c in n.children)
				collect(c);
		}
		collect(ui.root);
		check("calendar: six weeks from the Monday before the 1st", days.length == 42 && text(days[0]) == "28" && text(days[3]) == "1"
			&& text(ui.root.find("cal-month")) == "October 2026", days.length + " " + text(days[0]) + " " + text(ui.root.find("cal-month")));
		ui.setFocus(ui.root.find("cal-grid"));
		for (k in [Key.RIGHT, Key.DOWN, Key.PAGE_DOWN])
			ui.keyDown(k, 0);
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		check("calendar: the keys move the marked day, the month follows; Enter chooses", picked.value != null && picked.value.month == 11
			&& picked.value.day == 25 && chosen.join(",") == "25" && text(ui.root.find("cal-month")) == "November 2026",
			picked.value == null ? "none" : picked.value.month + "-" + picked.value.day + " " + text(ui.root.find("cal-month")));
		days = [];
		collect(ui.root);
		var third = days.filter(d -> text(d) == "3")[0];
		ui.pointerDown(third.absX + 4, third.absY + 4, 1);
		ui.pointerUp(third.absX + 4, third.absY + 4, 1);
		check("calendar: a click chooses", picked.value.day == 3 && picked.value.month == 11, "" + picked.value.day);
		var tree = ui.accessTree();
		var sel = [for (id in tree.order) if (tree.nodes.get(id).role == Cell && tree.nodes.get(id).selected == true) tree.nodes.get(id).name];
		check("calendar: a grid, the chosen day's cell selected and named", sel.join(",") == "3 November 2026", sel.join(","));

		// right to left: Left to the next day (the week from the right)
		ui.root.style.dir = Rtl;
		ui.update();
		ui.setFocus(ui.root.find("cal-grid"));
		ui.keyDown(Key.LEFT, 0);
		ui.keyDown(Key.ENTER, 0);
		check("calendar: right to left, Left to the next day", picked.value.day == 4, "" + picked.value.day);

		var ui2 = new Ui(new MonoText(), 400, 400);
		ui2.root.style.alignItems = Start;
		var when:Signal<Null<Day>> = signal(null);
		Render.render(<view><DatePicker tag="dp" value={when} today={today}/></view>, ui2.root);
		ui2.update();
		var button = ui2.root.find("dp");
		ui2.setFocus(button);
		ui2.keyDown(Key.ENTER, 0);
		ui2.update();
		var opened = ui2.overlay.find("dp-calendar-grid") != null && ui2.focus == ui2.overlay.find("dp-calendar-grid");
		ui2.keyDown(Key.LEFT, 0);
		ui2.keyDown(Key.ENTER, 0);
		ui2.update();
		check("date picker: opened by Enter, the calendar focused; a day chosen closes it", opened && when.value != null && when.value.day == 16
			&& ui2.overlay.children.length == 0 && ui2.focus == button && text(button) == "16 October 2026", opened + " " + text(button));
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
		check("For: a removed row's computations disposed, the rest bound", keptText == "TWO" && (first.observers == null || first.observers.length == 0), keptText);
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
		// attributes generated from Style's properties (StyleAttrs)
		var styled:Null<Node> = null;
		Render.render(<view ref={n -> styled = n} position="sticky" justify="flex-start" align-content="space-between" cursor="ew-resize" grid-auto-flow="column"
			font-weight="700" italic aspect-ratio={2} text-align="center" padding="8 12" min-width="50%" border-color="red" shadow="0 2 8 #00000040"/>, ui.root);
		var st = styled.style;
		check("render: Style's properties as attributes", st.position == Position.Sticky && st.justify == Justify.Start && st.alignContent == AlignContent.SpaceBetween && st.cursor == Cursor.ResizeEW
			&& st.gridAutoFlow == Grid.GridFlow.Column && st.fontWeight == 700 && st.italic == true && st.aspectRatio == 2 && st.textAlign == TextAlign.Center
			&& st.padding.left == 12 && st.borderColor == Color.parse("red") && st.shadow != null);
		var bad = try {
			Render.render(<view justify="sideways"/>, ui.root);
			"";
		} catch (e:Dynamic) Std.string(e);
		check("render: a value not of the property's enum", bad == "hxmc.ui: sideways is not a Justify", bad);
	}
}
