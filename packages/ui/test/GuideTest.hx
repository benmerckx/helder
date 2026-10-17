import hxmc.esx.Esx;
import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Flow.*;
import hxmc.ui.reactive.Reactive.*;
import hxmc.ui.widgets.Widgets.*;
import hxmc.ui.widgets.Theme;
import UiTest.Recording;

// The examples of packages/ui/GUIDE.md, compiled and run on Eval (make
// ui-check): what the guide shows works as it says. Keep the two in step.
class GuideTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('GuideTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	public static function main() {
		components();
		state();
		lists();
		contexts();
		popups();
		customNodes();
		snippets();
		grids();
		richText();
		themes();
		shortcuts();
		icons();
		dragAndDrop();
		Sys.println('GuideTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	// --- the guide's code ---

	// "Components"
	static function Stepper(props:{label:String, value:Signal<Int>, ?step:Int}):Esx {
		var step = props.step ?? 1;
		return <view direction="row" align-items="center" column-gap={8}>
			<text grow={1}>{props.label}</text>
			<Button tag="minus" label="-" onClick={() -> props.value.value -= step}/>
			<text min-width={32} text-align="center">{props.value}</text>
			<Button tag="plus" label="+" onClick={() -> props.value.value += step}/>
		</view>;
	}

	static function Card(props:{title:String, ?children:Any}):Esx
		return <view padding={16} row-gap={8} radius={8} background="#ffffff" shadow="0 1 4 #0000001a">
			<text font-weight={700}>{props.title}</text>
			{props.children}
		</view>;

	static function Order(props:{}):Esx {
		var adults = signal(2), children = signal(0);
		var total = memo(() -> adults.value * 30 + children.value * 12);
		return <Card title="Tickets">
			<Stepper label="Adults" value={adults}/>
			<Stepper label="Children" value={children} step={1}/>
			<text tag="total">{() -> 'Total: € ${total.value}'}</text>
		</Card>;
	}

	// "Lists and conditions"
	static function Names(props:{names:Signal<Array<String>>}):Esx
		return <view row-gap={4}>
			<For each={props.names} render={(name:String) -> <text>{name}</text>}/>
			<Show when={() -> props.names.value.length == 0} fallback={<text tag="count">{() -> props.names.value.length + " names"}</text>}>
				<text tag="empty">No names yet</text>
			</Show>
		</view>;

	static function Page(props:{tab:Signal<String>}):Esx
		return <Switch fallback={<text>Not found</text>}>
			<Match when={() -> props.tab.value == "home"}><text tag="home">Home</text></Match>
			<Match when={() -> props.tab.value == "settings"}><text tag="settings">Settings</text></Match>
		</Switch>;

	// "Context"
	static final Brand = context({accent: "#3b82f6"});

	static function Accent(props:{label:String}):Esx {
		var brand = use(Brand);
		return <text tag="accent" color={brand.accent}>{props.label}</text>;
	}

	// "Popups"
	static function Confirm(props:{onYes:Void->Void}):Esx {
		var open = signal(false);
		return <view>
			<Button tag="delete" label="Delete" onClick={() -> open.value = true}/>
			<Dialog open={open} title="Delete this file?">
				<view direction="row" column-gap={8} justify="end">
					<Button tag="no" label="Cancel" onClick={() -> open.value = false}/>
					<Button tag="yes" label="Delete" primary onClick={() -> {
						open.value = false;
						props.onYes();
					}}/>
				</view>
			</Dialog>
		</view>;
	}

	// "Your own nodes"
	static function Spark(props:{values:Signal<Array<Float>>}):Node {
		var n = new Sparkline();
		effect(() -> n.values = props.values.value);
		return n;
	}

	// --- checks: what the guide says happens ---

	static function window():Ui {
		var ui = new Ui(new MonoText(), 400, 300);
		ui.root.style.fontSize = 10;
		return ui;
	}

	static function click(ui:Ui, tag:String) {
		ui.update();
		var n = ui.root.find(tag);
		if (n == null) n = ui.overlay.find(tag);
		if (n == null) throw "no " + tag;
		ui.pointerDown(n.absX + 2, n.absY + 2, 1);
		ui.pointerUp(n.absX + 2, n.absY + 2, 1);
		ui.update();
	}

	static function text(ui:Ui, tag:String):String {
		var n:Null<Node> = ui.root.find(tag);
		if (n == null) n = ui.overlay.find(tag);
		return n == null ? "(none)" : (cast n : TextNode).text;
	}

	static function components() {
		var ui = window();
		Render.render(<Order/>, ui.root);
		check("components: the total from the memo", text(ui, "total") == "Total: € 60", text(ui, "total"));
		click(ui, "plus");
		check("components: a click updates the text that reads it", text(ui, "total") == "Total: € 90", text(ui, "total"));
	}

	static function state() {
		var price = signal(12.5), qty = signal(2);
		var total = memo(() -> price.value * qty.value);
		var seen = [];
		effect(() -> seen.push(total.value));
		batch(() -> {
			price.value = 10;
			qty.value = 3;
		});
		check("state: an effect once per batch", seen.join(",") == "25,30", seen.join(","));
	}

	static function lists() {
		var ui = window();
		var names = signal(new Array<String>());
		Render.render(<Names names={names}/>, ui.root);
		ui.update();
		check("lists: Show's children while the condition holds", text(ui, "empty") == "No names yet");
		names.value = ["Ann", "Bo"];
		ui.update();
		check("lists: its fallback otherwise, For's rows", text(ui, "count") == "2 names" && ui.root.find("empty") == null);
		var tab = signal("home");
		var ui2 = window();
		Render.render(<Page tab={tab}/>, ui2.root);
		tab.value = "settings";
		ui2.update();
		check("lists: Switch picks the first Match that holds", text(ui2, "settings") == "Settings" && ui2.root.find("home") == null);
	}

	static function contexts() {
		var ui = window();
		Render.render(<view>
			<Accent label="default"/>
			<Provider context={Brand} value={{accent: "#e11d48"}}><Accent label="rose"/></Provider>
		</view>, ui.root);
		ui.update();
		var colors = [for (n in ui.root.children[0].children) n.style.color];
		check("context: the nearest Provider's value, else the default", colors.length == 2 && colors[0] == Color.parse("#3b82f6") && colors[1] == Color.parse("#e11d48"),
			colors.join(","));
	}

	static function popups() {
		var ui = window();
		var deleted = 0;
		Render.render(<Confirm onYes={() -> deleted++}/>, ui.root);
		click(ui, "delete");
		check("popups: the dialog opens over the tree", ui.overlay.find("yes") != null);
		click(ui, "yes");
		check("popups: its button acts and closes it", deleted == 1 && ui.overlay.find("yes") == null);
		var ui = window(), log = [];
		var copy = () -> log.push("copy"), remove = () -> log.push("delete");
		Render.render(<ContextMenu items={[{label: "Copy", onSelect: copy}, {label: "Delete", onSelect: remove}]}>
			<text>Right-click me</text>
		</ContextMenu>, ui.root);
		ui.update();
		ui.pointerDown(15, 10, 3);
		ui.pointerUp(15, 10, 3);
		ui.update();
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.ENTER, 0);
		check("popups: a context menu where it was right-clicked", log.join(",") == "delete" && ui.overlay.children.length == 0, log.join(","));
	}

	// "State", "Layout and style", "Accessibility": the short snippets
	static function snippets() {
		var ui = window();
		var count = signal(1), on = signal(false), open = signal(false), closed = 0;
		var close = () -> closed++;
		var height = Motion.spring(() -> open.value ? 200 : 0);
		Render.render(<view>
			<text tag="a">{count}</text>
			<text tag="b">{() -> count.value * 2}</text>
			<text tag="c">{count.value}</text>
			<view tag="d" background={() -> on.value ? "#22c55e" : "#e4e4e7"}/>
			<view tag="e" height={height} overflow="hidden"><text>Hello</text></view>
			<view tag="banner" height={48} radius={8} background="linear-gradient(to right, #6366f1, rgb(236 72 153))"/>
			<view tag="f" role="button" label="Close" focusable onClick={_ -> close()}
				onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) close()}><text>×</text></view>
		</view>, ui.root);
		count.value = 5;
		ui.update();
		var banner = ui.root.find("banner");
		check("snippets: a gradient background", banner.style.backgroundImage != null && banner.style.background == Color.TRANSPARENT);
		check("snippets: bound and read-once holes", text(ui, "a") == "5" && text(ui, "b") == "10" && text(ui, "c") == "1", text(ui, "a") + text(ui, "b") + text(ui, "c"));
		open.value = true;
		Clock.finish();
		ui.update();
		check("snippets: a spring reaches its target", ui.root.find("e").height == 200, '${ui.root.find("e").height}');
		var f = ui.root.find("f");
		ui.setFocus(f);
		ui.keyDown(Key.ENTER, 0);
		check("snippets: a focusable node with a role", f.semantics != null && f.semantics.role == hxmc.ui.access.Role.Button && f.semantics.label == "Close" && closed == 1);
	}

	// "Layout and style": a grid
	static function Dashboard(props:{}):Esx
		return <view display="grid" grid-template-columns="200px 1fr 1fr" grid-auto-rows="80px" column-gap={12} row-gap={12} padding={12}>
			<view tag="nav" grid-row="span 2" background="#e4e4e7"/>
			<view tag="chart" grid-column="span 2" background="#dbeafe"/>
			<view tag="a" background="#fef3c7"/>
			<view tag="b" background="#dcfce7"/>
		</view>;

	static function Shell(props:{}):Esx
		return <view display="grid" grid-template-columns="160px 1fr" grid-template-rows="48px 1fr 32px" height="100%"
			grid-template-areas="'head head' 'side main' 'foot foot'">
			<view tag="head" grid-area="head" background="#e4e4e7"/>
			<view tag="side" grid-area="side" background="#f4f4f5"/>
			<view tag="main" grid-area="main"/>
			<view tag="foot" grid-area="foot" background="#e4e4e7"/>
		</view>;

	static function grids() {
		var ui = new Ui(new MonoText(), 600, 400);
		Render.render(<Dashboard/>, ui.root);
		ui.update();
		var box = (tag:String) -> {
			var n = ui.root.find(tag);
			[n.absX, n.absY, n.width, n.height].join(",");
		}
		check("grid: tracks, spans and gaps", box("nav") == "12,12,200,172" && box("chart") == "224,12,364,80" && box("a") == "224,104,176,80" && box("b") == "412,104,176,80",
			[for (t in ["nav", "chart", "a", "b"]) box(t)].join(" "));
		ui = new Ui(new MonoText(), 600, 400);
		Render.render(<Shell/>, ui.root);
		ui.update();
		check("grid: named areas", box("head") == "0,0,600,48" && box("side") == "0,48,160,320" && box("main") == "160,48,440,320" && box("foot") == "0,368,600,32",
			[for (t in ["head", "side", "main", "foot"]) box(t)].join(" "));
	}

	// "Rich text": spans in a paragraph
	static function Greeting(props:{name:Signal<String>, onLink:Void->Void}):Esx
		return <text tag="greeting">Hello <b>{props.name}</b>, read <span tag="link" color="#2563eb" text-decoration="underline" cursor="pointer" onClick={_ -> props.onLink()}>the guide</span>.</text>;

	static function richText() {
		var ui = window();
		var name = signal("Ann"), clicks = 0;
		Render.render(<view padding={10}><Greeting name={name} onLink={() -> clicks++}/></view>, ui.root);
		ui.update();
		var t:TextNode = cast ui.root.find("greeting");
		check("rich text: the spans make one paragraph", t.allText() == "Hello Ann, read the guide." && t.children.length == 5, t.allText());
		name.value = "Bo";
		ui.update();
		check("rich text: a span follows its signal", t.allText() == "Hello Bo, read the guide.", t.allText());
		// (MonoText: 5 pixels a character; "the guide" from character 16)
		var x = t.absX + 5 * 18 + 2, y = t.absY + 5;
		ui.pointerDown(x, y, 1);
		ui.pointerUp(x, y, 1);
		check("rich text: a click on a span is its", clicks == 1, '$clicks');
		ui.pointerDown(t.absX + 3, y, 1);
		ui.pointerUp(t.absX + 3, y, 1);
		check("rich text: elsewhere it is not", clicks == 1);
		var rec = new Recording();
		ui.paint(rec);
		var line = [for (c in rec.calls) if (StringTools.startsWith(c, "text")) c][0];
		// (the underline: under the link's characters (15 to 24, after "Bo"), in its colour, drawn before the text)
		var calls = [for (c in rec.calls) if (StringTools.startsWith(c, "text") || c.indexOf("ff2563eb") >= 0) c];
		var under = calls.length > 0 ? calls[0].split(" ") : [];
		check("rich text: the link underlined under its text", calls.length == 2 && under[0] == "rect" && Std.parseFloat(under[1]) == t.absX + 5 * 15
			&& Std.parseFloat(under[3]) == 5 * 9 && StringTools.startsWith(calls[1], "text"), calls.join("|"));
		var clamped = window();
		Render.render(<view width={100}><text tag="clamped" max-lines={2}>one two three four five six seven eight nine ten</text></view>, clamped.root);
		clamped.update();
		var ct = clamped.root.find("clamped");
		check("max-lines: two lines of a long text", ct.height == 25, '${ct.height}');
		check("rich text: the spans' colours drawn", line != null && StringTools.endsWith(line, "colors ff000000,ff000000,ff000000,ff2563eb,ff000000"), line);
	}

	// "Themes": the widgets follow Theme.current
	static function themes() {
		var ui = window();
		var dark = signal(false);
		Theme.follow(() -> dark.value);
		Render.render(<view><Button tag="themed" label="Themed"/></view>, ui.root);
		ui.update();
		var b = ui.root.find("themed");
		var light = b.style.background;
		dark.value = true;
		Clock.finish();
		check("themes: a widget follows the theme", Theme.current.value == Theme.DARK && light == Color.parse(Theme.LIGHT.control) && b.style.background == Color.parse(Theme.DARK.control),
			StringTools.hex(b.style.background, 8));
		dark.value = false;
		Clock.finish();
		check("themes: and back", b.style.background == light);
	}

	// "Images and icons"
	static final SEARCH = Svg.parse('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
		stroke-linecap="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>');

	static function SearchButton(props:{onClick:Void->Void}):Esx
		return <view tag="search" role="button" label="Search" focusable direction="row" column-gap={6} align-items="center"
			color="#2563eb" onClick={_ -> props.onClick()}>
			<image src={SEARCH} width={16} height={16}/>
			<text>Search</text>
		</view>;

	static function icons() {
		var ui = window(), clicks = 0;
		Render.render(<SearchButton onClick={() -> clicks++}/>, ui.root);
		ui.update();
		ui.paint(new Recording());
		var b = ui.root.find("search"), img:ImageNode = cast b.children[0];
		// (the circle's top: the stroke in the button's colour)
		var px = img.image.pixels, o = (1 * 16 + 7) * 4;
		check("icons: an svg drawn in the node's colour, at its size", img.image.width == 16 && px.get(o + 2) == 0xEB && px.get(o + 3) > 128,
			img.image.width + " " + px.get(o + 2) + " " + px.get(o + 3));
		click(ui, "search");
		check("icons: the button", clicks == 1);
	}

	// "Keyboard shortcuts"
	static function Editor(props:{text:Signal<String>, onSave:Void->Void}):Esx
		return <view row-gap={8}>
			<Hotkey keys="Mod+S" action={props.onSave}/>
			<Menu label="Edit" items={[{label: "Clear", shortcut: "Mod+Shift+K", onSelect: () -> props.text.value = ""}]}/>
			<Area value={props.text}/>
		</view>;

	static function shortcuts() {
		var ui = window(), text = signal("draft"), saved = 0;
		Render.render(<Editor text={text} onSave={() -> saved++}/>, ui.root);
		ui.update();
		var area:Node = null;
		function find(n:Node)
			if (Std.isOfType(n, hxmc.ui.widgets.TextArea)) area = n else for (c in n.children) find(c);
		find(ui.root);
		ui.setFocus(area);
		ui.keyDown("s".code, Key.MOD_CONTROL);
		ui.keyDown("k".code, Key.MOD_META | Key.MOD_SHIFT);
		check("shortcuts: a Hotkey and a menu item's, the focus in the text", saved == 1 && text.value == "", saved + " " + text.value);
	}

	// "Drag and drop": a list sorted by dragging
	static function Sortable(props:{items:Signal<Array<String>>}):Esx {
		var over = signal("");
		function move(what:String, before:String) {
			var list = props.items.value.filter(x -> x != what);
			list.insert(list.indexOf(before), what);
			props.items.value = list;
		}
		return <view row-gap={4}>
			<For each={props.items} render={(name:String) -> <view tag={"item-" + name} drag-data={name} padding={6}
				background={() -> over.value == name ? "#dbeafe" : "#ffffff"}
				onDragOver={e -> {
					e.preventDefault();
					over.value = name;
				}}
				onDragLeave={_ -> over.value = ""}
				onDrop={e -> {
					over.value = "";
					if (e.data != name) move(e.data, name);
				}}>{name}</view>}/>
		</view>;
	}

	static function dragAndDrop() {
		var ui = window();
		var items = signal(["a", "b", "c", "d"]), clicks = 0;
		Render.render(<view onClick={_ -> clicks++}><Sortable items={items}/></view>, ui.root);
		ui.update();
		function center(tag:String) {
			var n = ui.root.find(tag);
			return {x: n.absX + n.width / 2, y: n.absY + n.height / 2};
		}
		var a = center("item-a"), c = center("item-c");
		ui.pointerDown(a.x, a.y, 1);
		ui.pointerMove(a.x, a.y + 10);
		check("drag and drop: a drag starts past 4 pixels", ui.dragging != null && ui.dragging.data == "a");
		ui.pointerMove(c.x, c.y);
		ui.update();
		check("drag and drop: the target under it accepts", ui.root.find("item-c").style.background == Color.parse("#dbeafe"));
		ui.pointerUp(c.x, c.y, 1);
		ui.update();
		check("drag and drop: dropped, the list sorted", items.value.join("") == "bacd" && ui.dragging == null && clicks == 0, items.value.join("") + " " + clicks);
		var d = center("item-d"), b = center("item-b");
		ui.pointerDown(d.x, d.y, 1);
		ui.pointerMove(b.x, b.y);
		ui.keyDown(Key.ESCAPE, 0);
		ui.pointerUp(b.x, b.y, 1);
		check("drag and drop: Escape cancels", items.value.join("") == "bacd" && ui.root.find("item-b").style.background == Color.parse("#ffffff"), items.value.join(""));
	}

	static function customNodes() {
		var ui = window();
		var values = signal([1.0, 3.0, 2.0]);
		Render.render(<view padding={8}><Spark values={values}/></view>, ui.root);
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var bars = rec.calls.filter(c -> StringTools.startsWith(c, "rect"));
		check("own nodes: painted by their paintContent", bars.length == 3, rec.calls.join("|"));
		values.value = [1.0, 2.0];
		ui.update();
		var rec2 = new Recording();
		ui.paint(rec2);
		check("own nodes: an effect feeds them", rec2.calls.filter(c -> StringTools.startsWith(c, "rect")).length == 2);
	}
}

// "Your own nodes": a bar chart drawn with the Canvas
class Sparkline extends Node {
	public var values(default, set):Array<Float> = [];

	public function new() {
		super("sparkline");
		style.height = 40;
	}

	function set_values(v:Array<Float>):Array<Float> {
		values = v;
		if (ui != null) ui.requestFrame();
		return v;
	}

	// (it draws: paintContent is called)
	override public function hasContent():Bool
		return true;

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (values.length == 0) return;
		var max = Lambda.fold(values, Math.max, 0.0), w = width / values.length;
		for (i in 0...values.length) {
			var h = values[i] / max * height;
			canvas.rect(x + i * w + 1, y + height - h, w - 2, h, 2, Color.parse("#3b82f6"), 0, 0);
		}
	}
}
