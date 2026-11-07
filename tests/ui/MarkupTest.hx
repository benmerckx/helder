import helder.ui.*;
import helder.view.*;
import helder.ui.view.*;
import helder.view.Flow.*;
import helder.ui.view.UiFlow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;
import helder.ui.access.*;
import helder.ui.widgets.TextField;
import Plain.*;
import helder.image.Image;

// Markup rendered into helder.ui's nodes (helder.view on NodeRenderer), on Eval
// (bun run test ui runs it after UiTest; helder.view's own tests are
// tests/view): elements and
// style attributes, text runs, reactive text and attributes, regions,
// For and Show, components, events through a Ui; then context, onMount,
// Index, Switch and Match, Show's branches kept, Errored; Motion's
// transitions, springs and colours on a Clock ticked by hand; the
// accessibility tree of plain controls in markup (Plain), its actions and
// changes; a Popover; the neutral elements; a field's
// password, right to left; a part's states as signals; a VirtualList of
// 100000 rows scrolled, one of a million rows of their own heights
// (anchored, jumped, put in and taken out, the keyboard, the selection,
// the accessibility tree), one keyed by id
class MarkupTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	public static function main() {
		neutral();
		rendering();
		flow();
		motion();
		propertyTracks();
		access();
		accessFixture();
		popovers();
		documentNames();
		rightToLeft();
		wordBreaks();
		autoMargins();
		baselines();
		shorthands();
		password();
		statesStyle();
		fieldsetLegend();
		balancedText();
		liveRegions();
		focusEvents();
		virtual();
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
			<view tag="inc" focusable onClick={_ -> count(c -> c + 1)} padding={2}>+</view>
		</view>;
	}

	static final theme = context("light");

	// a component reading the theme where it is rendered
	static function Themed(props:{tag:String}):View
		return <text tag={props.tag}>{"theme " + use(theme)}</text>;

	static function Thrower(props:{when:Signal<Bool>}):View {
		return <text>{() -> {
			if (props.when()) throw "boom";
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

	static function rightToLeft() {
		var ui = new Ui(new MonoText(), 300, 200);
		var dir = signal("rtl"), name = signal("Ada");
		Render.render(<view dir={dir} padding={10} row-gap={6}>
			<view tag="row" direction="row" column-gap={4}><view tag="a" width={40} height={20}/><view tag="b" width={30} height={20}/></view>
			<text tag="words">Hello</text>
			<field tag="name" value={name}/>
		</view>, ui.root);
		ui.update();
		var a = ui.root.find("a"), b = ui.root.find("b"), words = ui.root.find("words");
		check("rtl: a row from the right, in markup (dir=\"rtl\")", a.absX == 300 - 10 - 40 && b.absX == a.absX - 4 - 30, a.absX + " " + b.absX);
		check("rtl: text aligned to the right by default", words.textAlign() == Right);
		// (a field's text at its right, short of the caret's pixel: a click in its middle between its letters)
		var field:TextField = cast ui.root.find("name");
		var p = field.laidOut(), right = field.absX + field.width - field.style.borderEdges.right - field.style.padding.right - 1;
		ui.pointerDown(right - p.width / 2, field.absY + field.height / 2, 1);
		ui.pointerUp(right - p.width / 2, field.absY + field.height / 2, 1);
		check("rtl: a field's text at the right, clicked there", field.caret == 1 || field.caret == 2, "" + field.caret);
		dir("ltr");
		flush();
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
		wb("keep-all");
		flush();
		ui.update();
		check("breaks: changed, the font follows", ui.root.find("u").font().wordBreak == KeepAll);
	}

	static function liveRegions() {
		var ui = new Ui(new MonoText(), 400, 300);
		var msg = signal("");
		Render.render(<view padding={10}><view tag="status" live="polite"><text>{msg}</text></view></view>, ui.root);
		ui.update();
		var t0 = ui.accessTree();
		msg("Saved");
		flush();
		ui.update();
		var t1 = ui.accessTree();
		var said = t1.announcements(t0);
		var region = [for (id in t1.order) if (t1.nodes.get(id).live == Polite) t1.nodes.get(id)];
		check("live: a region's new text announced, politely", said.length == 1 && said[0].text == "Saved" && said[0].live == Polite
			&& region.length == 1 && region[0].toJson().live == "polite" && region[0].role == Group, [for (s in said) s.text].join("|"));
		msg("Saved and synced");
		flush();
		ui.update();
		var t2 = ui.accessTree();
		check("live: what was added at its end; nothing when nothing changed", [for (s in t2.announcements(t1)) s.text].join("|") == "and synced"
			&& ui.accessTree().announcements(t2).length == 0, [for (s in t2.announcements(t1)) s.text].join("|"));
	}

	static function password() {
		var ui = new Ui(new MonoText(), 400, 300);
		var pw = signal("hunter2");
		Render.render(<view padding={10}><field tag="pw" value={pw} type="password" label="Password" onInput={e -> pw(e.text)}/></view>, ui.root);
		ui.update();
		var f:TextField = cast ui.root.find("pw");
		var clip:helder.ui.ClipboardHost.MemoryClipboard = cast ui.clipboard;
		clip.text = "before";
		ui.setFocus(f);
		f.selectAll();
		ui.keyDown("c".code, Key.MOD_CONTROL);
		ui.keyDown("x".code, Key.MOD_CONTROL);
		var t = ui.accessTree(), node = [for (id in t.order) if (t.nodes.get(id).role == TextInput) t.nodes.get(id)][0];
		check("password: shown and given as dots, not copied or cut", (cast f.layoutText(ui.text, Math.NaN) : MonoText.MonoParagraph).width == 7 * 7
			&& clip.text == "before" && pw() == "hunter2" && node.secret && node.value == "•••••••" && node.toJson().secret == true, node.value);
		f.select(3, 3);
		ui.keyDown(Key.LEFT, Key.MOD_CONTROL);
		check("password: a word is all of it", f.caret == 0, "" + f.caret);
	}

	static function focusEvents() {
		var ui = new Ui(new MonoText(), 400, 300);
		var log = [];
		Render.render(<view padding={20} row-gap={10} onFocusIn={e -> log.push("in " + e.target.tag)} onFocusOut={e -> log.push("out " + e.target.tag)}>
			<Button tag="first" label="First"/>
			<view><Button tag="save" label="Save"/></view>
		</view>, ui.root);
		ui.update();
		ui.keyDown(Key.TAB, 0);
		ui.keyDown(Key.TAB, 0);
		ui.update();
		check("focus in, focus out: bubbling", log.join(",") == "in first,out first,in save", log.join(","));
		// (a gesture's handler typed as its recogniser, NodeEvents: a Pan's axis, a Tap's taps)
		var axis = null, taps = 0;
		Render.render(<view tag="g" onPan={g -> axis = g.axis} onTap={t -> taps = t.taps}/>, ui.root);
		var g = ui.root.find("g");
		check("gestures' handlers typed by their recognisers", g != null && g.gestures.length == 2 && axis == null && taps == 0);
	}

	// UiFlow's Popover (its children in a popup while open: under the node
	// the markup puts it in, or at a point; Escape or a press outside asks
	// it to close)
	static function popovers() {
		var ui = new Ui(new MonoText(), 400, 300);
		var open = signal(false), at = signal(false), dismissed = 0;
		Render.render(<view padding={10} row-gap={10} align-items="start">
			<view tag="anchor" width={60} height={20}>
				<Popover open={open} placement="below" onDismiss={() -> {
					dismissed++;
					open(false);
				}}><view tag="pop" width={80} height={30}/></Popover>
			</view>
			<Popover open={at} at={() -> {x: 200.0, y: 100.0}} onDismiss={() -> at(false)}><view tag="at" width={20} height={20}/></Popover>
		</view>, ui.root);
		ui.update();
		check("popover: closed, nothing over the tree", ui.overlay.children.length == 0 && ui.overlay.find("pop") == null);
		open(true);
		flush();
		ui.update();
		var anchor = ui.root.find("anchor"), pop = ui.overlay.find("pop");
		check("popover: open, under the node it is in", pop != null && pop.absY >= anchor.absY + anchor.height, pop == null ? "none" : '${pop.absX},${pop.absY}');
		ui.keyDown(Key.ESCAPE, 0);
		ui.update();
		check("popover: Escape asks it to close", dismissed == 1 && ui.overlay.find("pop") == null, '$dismissed');
		open(true);
		flush();
		ui.update();
		ui.pointerDown(390, 290, 1);
		ui.pointerUp(390, 290, 1);
		ui.update();
		check("popover: a press outside too", dismissed == 2 && ui.overlay.find("pop") == null, '$dismissed');
		at(true);
		flush();
		ui.update();
		var a = ui.overlay.find("at");
		check("popover: at a point", a != null && a.absX == 200 && a.absY == 100, a == null ? "none" : '${a.absX},${a.absY}');
		at(false);
		flush();
		ui.update();
		check("popover: closed again", ui.overlay.find("at") == null);
	}

	static function neutral() {
		var ui = new Ui(new MonoText(), 400, 300);
		// (the neutral elements, as a page's renderer would realise them: view:button a view, text:p a text,
		// onPress a click or Enter or Space unless onKeyDown took it; a ref a Part: the node)
		var presses = 0, part:Null<Part> = null, keys = 0;
		var host = new Node("host");
		ui.root.append(host);
		Render.render(<view:button tag="nb" slot="neutral" id="page-only" focusable onPress={_ -> presses++} ref={p -> part = p}
			onKeyDown={e -> if (e.key == Key.SPACE) {
				keys++;
				e.preventDefault();
			}}>
			<text:p tag="np">Go</text:p>
		</view:button>, host);
		ui.update();
		var nb = ui.root.find("nb"), np = ui.root.find("np");
		ui.pointerDown(nb.absX + 2, nb.absY + 2, 1);
		ui.pointerUp(nb.absX + 2, nb.absY + 2, 1);
		part.focus();
		ui.keyDown(Key.ENTER, 0);
		ui.keyDown(Key.SPACE, 0);
		check("neutral elements: view:button a view, text:p a text, onPress by a click and Enter, not a Space onKeyDown took",
			nb != null && !Std.isOfType(nb, TextNode) && Std.isOfType(np, TextNode) && (cast np : TextNode).text == "Go" && nb.slot == "neutral" && presses == 2
			&& keys == 1 && part == nb && ui.focus == nb, presses + " " + keys + " " + (part == nb));
		// (an icon: lucide's of that name, an Svg drawn in the node's colour; mirrored right to left)
		Render.render(<icon tag="ic" name="chevron-right" mirrored width={16} height={16}/>, host);
		var ic:ImageNode = cast ui.root.find("ic");
		check("icon: lucide's by name, parsed once", ic.svg != null && ic.svg == helder.ui.widgets.Icons.svg("chevron-right") && ic.mirrored);
	}

	// wrapping makes, at the narrowest width keeping that many
	static function balancedText() {
		var ui = new Ui(new MonoText(), 400, 300);
		var t = new TextNode("aa bb cc dd ee ff"), g = new TextNode("aa bb cc dd ee ff");
		var w = 14 * ui.text.layout("a", g.font(), Math.NaN).width;
		for (n in [t, g]) {
			n.style.width = w;
			ui.root.append(n);
		}
		t.style.textWrap = Balance;
		ui.update();
		var p = t.laidOut(), q = g.laidOut();
		check("balanced text: two lines of three words, greedy five and one", p.lineCount == 2 && q.lineCount == 2 && p.width == 8 * w / 14
			&& q.width == w, p.lineCount + " " + p.width + " " + q.width);
	}

	// a fieldset's legend (CSS's rendered legend): no gap after it, its
	// margin kept; a rule of the sibling before ([[data-variant=legend]+&]:
	// "prev:variant=legend"), the description right after it only, again as
	// one is put before
	static function fieldsetLegend() {
		var ui = new Ui(new MonoText(), 400, 300), first = signal(true);
		ui.theme = {
			rules: [
				{slot: "field-set", style: {rowGap: 24}}, {slot: "field-legend", style: {marginBottom: 12}},
				{slot: "field-description", when: ["prev:variant=legend"], style: {marginTop: -6}}
			]
		};
		Render.render(<view padding={10}>
			<view:fieldset tag="set" slot="field-set">
				<text:legend tag="legend" slot="field-legend" variant="legend">Profile</text:legend>
				<Show when={first}><text:p tag="d0" slot="field-description">Before</text:p></Show>
				<text:p tag="d1" slot="field-description">About</text:p>
			</view:fieldset>
		</view>, ui.root);
		ui.update();
		var legend = ui.root.find("legend"), d0 = ui.root.find("d0"), d1 = ui.root.find("d1");
		check("fieldset: the legend's margin, no gap; the description after it pulled up, the next a gap under",
			d0.y == legend.y + legend.height + 12 - 6 && d1.y == d0.y + d0.height + 24, '${legend.y} ${legend.height} ${d0.y} ${d0.height} ${d1.y}');
		first(false);
		flush();
		ui.update();
		check("fieldset: the sibling before gone, the next description's rule follows", d1.y == legend.y + legend.height + 12 - 6, '${legend.y} ${legend.height} ${d1.y} ' + [for (c in d1.parent.children) c.tag].join(","));
	}

	// a part's states as signals (React Aria's render props): a node's
	// style a function of them (states), over the theme's rules, taken
	// back when it no longer gives a property
	static function statesStyle() {
		var ui = new Ui(new MonoText(), 400, 300), ticked = signal(false);
		ui.theme = {rules: [{slot: "button", style: {background: Color.rgb(0x111111), padding: 4}}]};
		Render.render(<view align-items="start" padding={10}>
			<view:button tag="b" slot="button" focusable states={(s:States) -> (s.hovered() ? {background: Color.rgb(0xFF0000)} : {} : StyleProps)}>Go</view:button>
			<view tag="c" data-state={() -> ticked() ? "checked" : "unchecked"} states={(s:States) -> (s.attr("data-state")() == "checked" ? {opacity: 0.5} : {} : StyleProps)}/>
		</view>, ui.root);
		ui.update();
		var b = ui.root.find("b"), c = ui.root.find("c");
		var before = b.style.background;
		ui.pointerMove(b.absX + 2, b.absY + 2);
		ui.update();
		var hovered = b.style.background, states = States.of(b);
		ui.pointerMove(390, 290);
		ui.update();
		check("states: an instance's style a function of its states, over the theme's, the theme's again after", before == Color.rgb(0x111111)
			&& hovered == Color.rgb(0xFF0000) && b.style.background == Color.rgb(0x111111) && !states.hovered(), hovered.toHex() + " " + b.style.background.toHex());
		ticked(true);
		flush();
		ui.update();
		check("states: an attribute as a signal (data-state)", c.style.opacity == 0.5 && States.of(c).attr("data-state")() == "checked");
		ui.setFocus(b);
		ui.keyDown(Key.TAB, 0);
		ui.keyDown(Key.TAB, 0);
		ui.setFocus(b, true);
		check("states: focused, focus-visible", States.of(b).focused());
	}

	// a link's href (a Link to assistive technology, a document's annotation); paged layout's names in a window: kept, nothing more
	static function documentNames() {
		var ui = new Ui(new MonoText(), 400, 300);
		Render.render(<view padding={10}>
			<text tag="docs" href="https://hxmc.dev/docs" focusable>Docs</text>
			<view tag="chapter" break-before="page" break-inside="avoid" page="wide" height={20}/>
		</view>, ui.root);
		ui.update();
		var link = ui.root.find("docs"), t = ui.accessTree();
		var an = [for (id in t.order) t.nodes.get(id)].filter(a -> a.href != null)[0];
		var ch = ui.root.find("chapter");
		check("document: a link's href, a Link", link.semantics.role == helder.ui.access.Role.Link && an != null && an.href == "https://hxmc.dev/docs"
			&& an.toJson().href == "https://hxmc.dev/docs");
		check("document: break-before, break-inside and page kept in a window", ch.style.breakBefore == Page && ch.style.breakInside == Avoid
			&& ch.style.page == "wide" && ch.height == 20);
	}

	static function virtual() {
		var ui = new Ui(new MonoText(), 300, 300);
		var items = signal([for (i in 0...100000) "item " + i]);
		var made = 0;
		var dispose = Render.render(<view><VirtualList tag="list" each={items} itemHeight={20} height={200}>{(item:Read<String>, i:Int) -> {
				made++;
				<text>{item()}</text>;
			}}</VirtualList></view>, ui.root);
		ui.update();
		var list = ui.root.find("list");
		// (the rows shown: made and in the window; those that left it hidden and kept)
		function rows():Array<String>
			return [for (c in list.children) if (c.tag == "row" && c.style.display != None) (cast c.children[0] : TextNode).text];
		check("virtual: only the rows in view (and 3 more)", rows().length == 14 && rows()[0] == "item 0" && made == 14, rows().join(","));
		check("virtual: scrolls the whole list", list.contentHeight == 2000000, '${list.contentHeight}');
		ui.wheel(list.absX + 5, list.absY + 5, 0, 1000);
		ui.update();
		var r = rows();
		check("virtual: rows made as it scrolls", r.length == 17 && r.indexOf("item 47") >= 0 && r.indexOf("item 63") >= 0 && r.indexOf("item 0") < 0, r.join(","));
		var at = [for (c in list.children) if (c.tag == "row") c].filter(c -> (cast c.children[0] : TextNode).text == "item 50")[0];
		check("virtual: a row at its index's height", at != null && at.y == 1000, at == null ? "none" : '${at.y}');
		ui.wheel(list.absX + 5, list.absY + 5, 0, -1000);
		ui.update();
		check("virtual: rows made before shown again, not made anew", rows()[0] == "item 0" && made == 31, '$made');
		items([for (i in 0...60) "new " + i]);
		flush();
		ui.update();
		ui.wheel(list.absX + 5, list.absY + 5, 0, 2000);
		ui.update();
		r = rows();
		check("virtual: a shorter list: its rows, the scroll clamped", r.length > 0 && r.indexOf("new 59") >= 0 && list.scrollY == 60 * 20 - 200, r.join(",") + " " + list.scrollY);
		dispose();
		check("virtual: disposed", ui.root.find("list") == null);
		virtualRows();
		virtualItems();
	}

	// (a row's height in the million: 20 to 60 pixels)
	static function rowHeight(id:Int):Int
		return 20 + ((id * 7) % 5) * 10;

	// a million rows of their own heights: measured as they are shown, the
	// scroll anchored through the measures, a jump to the end, rows put in
	// and taken out above the view, the keyboard onto rows not made,
	// the selection kept, the accessibility tree's places
	static function virtualRows() {
		var ui = new Ui(new MonoText(), 300, 340);
		var items = signal([for (i in 0...1000000) i]);
		var sel:Signal<Dynamic> = signal((null : Dynamic));
		var list:Null<VirtualScroll> = null;
		var dispose = Render.render(<view><VirtualList tag="rows" each={items} estimate={30} height={300} selected={sel} label="Rows"
			ref={l -> list = l}>{(id:Read<Int>, i:Int) -> <view tag="cell" height={rowHeight(id())}><text>{"row " + id()}</text></view>}</VirtualList></view>, ui.root);
		ui.update();
		var l = list;
		// (the rows shown, in order; each drawn where: its top in the view)
		function shown():Array<Node>
			return [for (c in l.children) if (c.tag == "row" && c.style.display != None) c];
		function idOf(n:Node):Int
			return Std.parseInt((cast n.children[0].children[0] : TextNode).text.substr(4));
		function drawnY(n:Node):Float
			return n.absY - l.scrollY - l.absY;
		// (no gap: the rows shown in order, each after the last, covering the view)
		function covers():Bool {
			var s = shown();
			if (s.length == 0) return false;
			for (k in 1...s.length)
				if (s[k].y != s[k - 1].y + s[k - 1].height || l.rowOf(s[k]).index != l.rowOf(s[k - 1]).index + 1) return false;
			return drawnY(s[0]) <= 0 && drawnY(s[s.length - 1]) + s[s.length - 1].height >= 300;
		}
		var s = shown();
		check("virtual rows: few made of a million", s.length > 8 && s.length < 30 && l.rows().length <= s.length + 8 && idOf(s[0]) == 0, '${s.length} ${l.rows().length}');
		check("virtual rows: measured at their heights", [for (n in s) n.height == rowHeight(idOf(n))].indexOf(false) < 0 && l.heights.isMeasured(0)
			&& l.heights.heightOf(1) == rowHeight(1));
		check("virtual rows: the view covered", covers());
		check("virtual rows: the extent all rows' (the estimate's for those not measured)", Math.abs(l.contentHeight - l.heights.total()) < 1,
			'${l.contentHeight} ${l.heights.total()}');
		var t = ui.accessTree(), box = null;
		for (id in t.order)
			if (t.nodes.get(id).role == ListBox) box = t.nodes.get(id);
		var opts = box == null ? [] : [for (k in box.children) t.nodes.get(k)];
		check("virtual rows: a listbox of the rows shown, each its place among a million", box != null && box.name == "Rows" && opts.length == s.length
			&& opts[0].role == ListBoxOption && opts[0].setSize == 1000000 && opts[3].posInSet == 4 && opts[3].name == "row 3",
			box == null ? "none" : [for (o in opts) '${o.role.aria()}:${o.posInSet}/${o.setSize}:${o.name}'].join(","));
		// (the wheel: rows measured as they come, the view covered)
		for (_ in 0...20) {
			ui.wheel(l.absX + 5, l.absY + 5, 0, 97);
			ui.update();
		}
		check("virtual rows: scrolled, the view covered", covers() && l.scrollY == 1940, '${l.scrollY}');
		var top = shown().filter(n -> drawnY(n) <= 0 && drawnY(n) + n.height > 0)[0];
		check("virtual rows: the row at the top the index's", top != null && idOf(top) == l.heights.rowAt(l.scrollY));
		// (rows put in above the view: nothing moves)
		var topId = idOf(top), topY = drawnY(top), before = l.scrollY;
		var next = items().copy();
		for (k in 0...5)
			next.insert(3, 2000000 + k);
		items(next);
		flush();
		ui.update();
		var again = shown().filter(n -> idOf(n) == topId)[0];
		check("virtual rows: rows put in above the view: nothing moves", again != null && drawnY(again) == topY && covers() && l.count == 1000005,
			again == null ? "gone" : '${drawnY(again)} $topY ${l.scrollY} $before');
		next = items().copy();
		next.splice(1, 4);
		items(next);
		flush();
		ui.update();
		again = shown().filter(n -> idOf(n) == topId)[0];
		check("virtual rows: rows taken out above the view: nothing moves", again != null && drawnY(again) == topY && l.count == 1000001,
			again == null ? "gone" : '${drawnY(again)} $topY');
		// (a jump to the last row: made, measured, its end at the view's)
		l.scrollToIndex(l.count - 1, "end");
		ui.update();
		s = shown();
		var last = s[s.length - 1];
		check("virtual rows: a jump to the last row, at the view's end", idOf(last) == 999999 && drawnY(last) + last.height == 300 && covers()
			&& l.rows().length < 90, '${idOf(last)} ${drawnY(last) + last.height} ${l.rows().length}');
		// (one far in: the estimate made real, the row still at the top)
		l.scrollToIndex(500000, "start");
		ui.update();
		var mid = shown().filter(n -> idOf(n) == 499999)[0];
		check("virtual rows: a jump to a row: at the view's top once measured", mid != null && drawnY(mid) == 0 && covers(),
			mid == null ? "none" : '${drawnY(mid)}');
		// (the keyboard: onto rows not made, the selection following)
		l.focusIndex(500000);
		check("virtual rows: focusIndex: the row made and focused", ui.focus != null && l.rowOf(ui.focus).index == 500000);
		for (_ in 0...12)
			ui.keyDown(Key.DOWN, 0);
		ui.update();
		var f = l.rowOf(ui.focus);
		check("virtual rows: Down twelve times: the focus there, in view, selected", f != null && f.index == 500012 && sel() == idOf(f.node)
			&& drawnY(f.node) + f.node.height <= 300 && drawnY(f.node) >= 0 && f.node.semantics.selected == true,
			f == null ? "none" : '${f.index} ${sel()} ${drawnY(f.node)}');
		ui.keyDown(Key.PAGE_DOWN, 0);
		ui.update();
		f = l.rowOf(ui.focus);
		check("virtual rows: Page Down: a view further", f != null && f.index > 500017 && f.index < 500030 && covers(), f == null ? "none" : '${f.index}');
		var chosen:Dynamic = sel();
		ui.keyDown(Key.END, 0);
		ui.update();
		f = l.rowOf(ui.focus);
		check("virtual rows: End: the last row, made, focused", f != null && f.index == l.count - 1 && sel() == 999999 && covers());
		ui.keyDown(Key.HOME, 0);
		ui.update();
		f = l.rowOf(ui.focus);
		check("virtual rows: Home: the first", f != null && f.index == 0 && l.scrollY == 0 && covers());
		// (the selection kept through the rows' recycling)
		sel(chosen);
		flush();
		l.scrollToIndex(l.heights.length - 1);
		ui.update();
		l.scrollToIndex(chosen + 1, "center");
		ui.update();
		var r = shown().filter(n -> idOf(n) == chosen)[0];
		check("virtual rows: the selection kept as its row comes back", r != null && r.semantics.selected == true
			&& shown().filter(n -> n.semantics.selected == true).length == 1);
		t = ui.accessTree();
		var o = t.nodes.get(@:privateAccess r.accessId);
		check("virtual rows: its place and selection to assistive technology", o != null && o.selected == true && o.posInSet == l.rowOf(r).index + 1
			&& o.setSize == l.count);
		var kept = l.rows().length;
		check("virtual rows: the rows made stay few", kept <= l.keep + 40, '$kept');
		dispose();
		check("virtual rows: disposed", ui.root.find("rows") == null);
	}

	// rows keyed by an id: an item changed changes its row alone, rows moved
	// keep their rows and heights
	static function virtualItems() {
		var ui = new Ui(new MonoText(), 300, 300);
		var items = signal([for (i in 0...1000) {id: i, label: "item " + i}]);
		var renders = 0;
		var list:Null<VirtualScroll> = null;
		function label(r:Read<{id:Int, label:String}>):String {
			renders++;
			return r().label;
		}
		var dispose = Render.render(<view><VirtualList tag="items" each={items} by={r -> r.id} estimate={20} height={200} ref={l -> list = l}>{(r:Read<{id:Int, label:String}>, i:Int) -> <text>{label(r)}</text>}</VirtualList></view>, ui.root);
		ui.update();
		var l = list, made = l.made, before = renders;
		var next = items().copy();
		next[2] = {id: 2, label: "changed"};
		items(next);
		flush();
		ui.update();
		var row = l.rowAt(2);
		check("virtual items: an item changed: its row alone", l.made == made && renders == before + 1 && row != null
			&& (cast row.node.children[0] : TextNode).text == "changed", '${l.made} $made $renders $before');
		var node4 = l.rowAt(4).node;
		next = items().copy();
		var moved = next.splice(4, 1)[0];
		next.insert(1, moved);
		items(next);
		flush();
		ui.update();
		check("virtual items: a row moved keeps its node", l.rowAt(1) != null && l.rowAt(1).node == node4 && l.made == made);
		dispose();
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
			<field tag="name" value={name} placeholder="Name" label="Name" onInput={e -> name(e.text)}/>
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
		check("access: SetValue types into a field", ui.accessAction(field.id, SetValue, "Ada") && name() == "Ada");
		ui.update();
		var t4 = ui.accessTree();
		check("access: the field's value", t4.nodes.get(field.id).value == "Ada");
		check("access: Focus", ui.accessAction(field.id, Focus) && ui.focus == ui.root.find("name"));
		check("access: no change, no update", t4.changesJson(t4) == null && t4.changesJson(null) != null);
		check("access: an action on a node gone", !ui.accessAction(9999999, Click));
	}

	// the fixture every adapter's test reads: sets, a table, text, the newer actions
	static function accessFixture() {
		var ui = new Ui(new MonoText(), 400, 600);
		var f = new AccessFixture();
		Render.render(f.view(), ui.root);
		ui.update();
		var t = ui.accessTree();
		function byName(role:Role, name:String):Null<AccessNode> {
			for (id in t.order) {
				var n = t.nodes.get(id);
				if (n.role == role && n.name == name) return n;
			}
			return null;
		}
		var pear = byName(ListItem, "Pear");
		check("fixture: a list item's place in its set", pear != null && pear.posInSet == 2 && pear.setSize == 3);
		var grid = byName(Table, "Mail"), bob = byName(Cell, "Lunch"), row1 = byName(Row, "Bob Lunch");
		check("fixture: a table's rows and columns", grid != null && grid.rowCount == 3 && grid.colCount == 2, grid == null ? "none" : '${grid.rowCount}x${grid.colCount}');
		check("fixture: a cell's place", bob != null && bob.rowIndex == 2 && bob.colIndex == 1 && row1 != null && row1.rowIndex == 2);
		check("fixture: a table's ancestor", bob != null && t.ancestor(bob.id, Table) == grid.id);
		var tab = byName(Tab, "Advanced");
		check("fixture: a tab's place", tab != null && tab.posInSet == 2 && tab.setSize == 2 && tab.selected == false);
		var name = byName(TextInput, "Name"), code = byName(TextInput, "Code"), notes = byName(MultilineTextInput, "Notes");
		check("fixture: a field's text and caret", name != null && name.value == "Ada" && name.textStart >= 0 && !name.readOnly);
		check("fixture: a read-only field", code != null && code.readOnly && code.value == "X1");
		check("fixture: a text area", notes != null && notes.value == "one\ntwo");
		check("fixture: SetSelection", ui.accessAction(name.id, SetSelection, "1,3"));
		ui.update();
		var t2 = ui.accessTree(), n2 = t2.nodes.get(name.id);
		check("fixture: the selection after it, the field focused", n2.textStart == 1 && n2.textEnd == 3 && n2.caret == 3 && t2.focus == name.id, '${n2.textStart},${n2.textEnd},${n2.caret}');
		var more = byName(Button, "More");
		check("fixture: a disclosure collapsed", more != null && more.expanded == false);
		check("fixture: Collapse when collapsed: nothing", ui.accessAction(more.id, Collapse) && !f.open.peek());
		check("fixture: Expand", ui.accessAction(more.id, Expand) && f.open.peek());
		check("fixture: Expand again: nothing", ui.accessAction(more.id, Expand) && f.open.peek());
		ui.update();
		check("fixture: Select a row", ui.accessAction(row1.id, Select) && f.row.peek() == 1);
		ui.update();
		check("fixture: its state after", ui.accessTree().nodes.get(row1.id).selected == true);
		var scroller = ui.root.find("scroller"), last = byName(Label, "Last");
		check("fixture: ScrollIntoView", ui.accessAction(last.id, ScrollIntoView) && scroller.scrollY > 0, '${scroller.scrollY}');
		var vol = byName(Slider, "Volume");
		check("fixture: SetValue on a range: stepped there", ui.accessAction(vol.id, SetValue, "0.8") && Math.abs(f.volume.peek() - 0.8) < 1e-9, '${f.volume.peek()}');
		check("fixture: SetValue down", ui.accessAction(vol.id, SetValue, "0.2") && Math.abs(f.volume.peek() - 0.2) < 1e-9, '${f.volume.peek()}');
		// the units assistive technology reads text by (UTF-16)
		var w = TextUnits.pieces("one two\nthree", Word), l = TextUnits.pieces("one two\nthree", Line);
		check("text units: words, lines", haxe.Json.stringify(w) == "[[0,4],[4,8],[8,13]]" && haxe.Json.stringify(l) == "[[0,8],[8,13]]", haxe.Json.stringify(w));
		var m = TextUnits.move("one two three", 5, 5, Word, 1), back = TextUnits.move("one two three", 5, 5, Word, -1);
		check("text units: moved a word on, back to its start", m.start == 8 && m.moved == 1 && back.start == 4 && back.moved == -1, '${m.start} ${back.start} ${back.moved}');
		var e = TextUnits.moveBoundary("one two", 0, Word, 5);
		check("text units: an endpoint moved to the end, as far as it goes", e.at == 7 && e.moved == 2, '${e.at} ${e.moved}');
		check("text units: a surrogate pair one character", TextUnits.pieces("a\u{1F600}b", Character).length == 3);
		check("fixture: JSON's new fields", t.nodes.get(grid.id).toJson().rowCount == 3 && pear.toJson().posInSet == 2 && code.toJson().readOnly == true);
	}

	// motion declared in markup (helder.ui.motion): motion, its per-property
	// curves, lead and trail, matched, instant, ride; a keyed For's rows
	// entering and leaving by their transition, one taken back mid-exit (the
	// same row, its node revived), one gone for good (its owner disposed once
	// its exit settled)
	static function propertyTracks() {
		var ui = new Ui(null, 300, 400), canvas = new UiTest.Recording();
		var items = signal(["a", "b", "c"]);
		made = disposed = 0;
		Render.render(<view tag="list" motion="snappy" motion-opacity="calm" lead="lead" trail="0.5 0.1">
			<For each={items}>{(s:Read<String>) -> <TrackRow name={s}/>}</For>
			<view tag="pinned" ride="trailing" matched="m" instant/>
		</view>, ui.root);
		var list = ui.root.find("list"), pinned = ui.root.find("pinned");
		var spec = list.motion;
		check("tracks: motion's token", spec != null && spec.curve.token == "snappy", '$spec');
		check("tracks: per property", spec.opacity.token == "calm" && spec.lead.token == "lead" && spec.trail.duration == 0.5 && spec.trail.bounce == 0.1);
		check("tracks: ride, matched, instant", pinned.ride == 3 && pinned.matched == "m" && pinned.instant);
		var row = list.find("row-a");
		check("tracks: a transition's presence", row.style.transition.presence != null && row.style.transition.presence.dy == 16);
		var t = 1000.0;
		function frame() {
			Clock.tick(t += 1 / 60);
			ui.update();
			canvas.calls.resize(0);
			ui.paint(canvas);
		}
		frame();
		check("tracks: nothing on the first frame", list.find("row-a").present == null);
		var b = list.find("row-b");
		items(["a", "c"]);
		flush();
		frame();
		frame();
		check("tracks: a row leaving, kept drawn", b.parent == null && b.leftFrom == list && list.exits.indexOf(b) >= 0);
		check("tracks: drawn fading", canvas.calls.filter(c -> StringTools.startsWith(c, "opacity 0.")).length > 0, canvas.calls.join("; "));
		items(["a", "b", "c"]);
		flush();
		frame();
		check("tracks: taken back mid-exit, the same row", made == 3 && disposed == 0 && list.find("row-b") == b && b.leftFrom == null, '$made made, $disposed disposed');
		var c = list.find("row-c");
		items(["a", "b"]);
		flush();
		for (_ in 0...60)
			frame();

		check("tracks: gone once its exit settled, its owner disposed", disposed == 1 && list.find("row-c") == null && list.exits.length == 0, '$disposed disposed');
		items(["a", "b", "d"]);
		flush();
		frame();
		frame();
		var d = list.find("row-d");
		check("tracks: a new row entering", made == 4 && d.present != null && d.present.presence != null && d.present.presence.value < 1);
		ui.update();
		Clock.finish();
	}

	static var made = 0;
	static var disposed = 0;

	// (a row of propertyTracks' list: its making and its owner's disposal counted)
	static function TrackRow(props:{name:Read<String>}) {
		made++;
		onCleanup(() -> disposed++);
		return <view tag={"row-" + props.name()} height={20} transition="fade slide-up" background="#808080"/>;
	}

	static function motion() {
		var target = signal(0.0);
		var t = Motion.transition(() -> target(), 1.0, Motion.linear);
		check("motion: a transition starts at its target", t() == 0 && !Clock.active);
		target(10);
		flush();
		check("motion: it moves on ticks", t() == 0 && Clock.active);
		Clock.tick(100);
		check("motion: from the first tick", t() == 0, '${t()}');
		Clock.tick(100.5);
		check("motion: half way", t() == 5, '${t()}');
		target(20);
		flush();
		Clock.tick(101);
		check("motion: a new target, from where it is", t() == 5, '${t()}');
		Clock.tick(101.25);
		check("motion: a quarter to the new target", Math.abs(t() - 8.75) < 1e-9, '${t()}');
		Clock.tick(102);
		check("motion: there, and done", t() == 20 && !Clock.active, '${t()}');
		// a spring settles on its target (an underdamped one, overshooting)
		var s = Motion.spring(() -> target(), 170, 12);
		target(0);
		flush();
		var time = 200.0, peak = 20.0, steps = 0;
		while (Clock.active && steps < 1000) {
			Clock.tick(time);
			time += 1 / 60;
			steps++;
			if (s() < peak) peak = s();
		}
		check("motion: a spring settles", s() == 0 && !Clock.active && steps < 400, '${s()} after $steps steps');
		check("motion: overshooting", peak < -1 && peak > -10, '$peak');
		// a colour
		var c = signal("#000000");
		var col = Motion.color(() -> c(), 1.0, Motion.linear);
		c("#ffffff");
		flush();
		Clock.tick(300);
		Clock.tick(300.5);
		check("motion: a colour half way", col() == "#808080FF", col());
		Clock.tick(301);
		check("motion: the colour reached", col() == "#FFFFFFFF" && !Clock.active, col());
		// stopped with its owner
		var other = signal(0.0);
		var stop = root(dispose -> {
			Motion.transition(() -> other(), 1.0);
			dispose;
		});
		other(5);
		flush();
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
		check("context: provide()", root(_ -> provide(theme, "blue", () -> use(theme))) == "blue" && root(_ -> use(theme)) == "light");
		// onSettled: after the nodes are in the tree
		var parentAtMount:Null<Node> = null, mounted = 0;
		var probe:Null<Node> = null;
		Render.render(<view tag="probe" ref={n -> {
			probe = n;
			onSettled(() -> {
				mounted++;
				parentAtMount = n.parent;
			});
		}}/>, ui.root);
		check("onSettled: after the insertion", mounted == 1 && parentAtMount == ui.root);
		// For by index: rows by index, an item's Read what is there
		var names = signal(["a", "b", "c"]);
		var rowsMade = 0;
		Render.render(<view tag="index"><For each={names} keyed={false}>{n -> {
			rowsMade++;
			<text>{"-" + n()}</text>;
		}}</For></view>, ui.root);
		var idx = ui.root.find("index");
		var shownRows = () -> [for (c in idx.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("For by index: rows", shownRows() == "-a,-b,-c" && rowsMade == 3, shownRows());
		names(["x", "b"]);
		flush();
		check("For by index: items set in place, extra rows removed", shownRows() == "-x,-b" && rowsMade == 3, shownRows());
		names(["x", "b", "y", "z"]);
		flush();
		check("For by index: rows added", shownRows() == "-x,-b,-y,-z" && rowsMade == 5, shownRows());
		// For: a row kept when the list changes stays bound (its computations
		// belong to the list's owner, not to the effect that runs again)
		var first = signal("one"), second = signal("two");
		var list = signal([first]);
		Render.render(<view tag="kept"><For each={list}>{sg -> <text>{sg()}</text>}</For></view>, ui.root);
		list([first, second]);
		flush();
		first("ONE");
		flush();
		var kept = ui.root.find("kept");
		var keptText = [for (c in kept.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("For: a kept row stays bound", keptText == "ONE,two", keptText);
		list([second]);
		flush();
		first("gone");
		flush();
		second("TWO");
		flush();
		keptText = [for (c in kept.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("For: a removed row's computations disposed, the rest bound", keptText == "TWO", keptText);
		// Switch and Match
		var n = signal(1);
		Render.render(<view tag="switch"><Switch fallback="many">
			<Match when={() -> n() == 0}><text>none</text></Match>
			<Match when={() -> n() == 1}><text>one</text></Match>
		</Switch></view>, ui.root);
		var sw = ui.root.find("switch");
		var switched = () -> [for (c in sw.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("Switch: the first case true", switched() == "one", switched());
		n(0);
		flush();
		check("Switch: another case", switched() == "none", switched());
		n(5);
		flush();
		check("Switch: the fallback", switched() == "many", switched());
		// Show renders its children again only when the branch changes
		var count = signal(1), made = 0;
		Render.render(<view tag="show"><Show when={() -> count() > 0}><view ref={_ -> made++}/></Show></view>, ui.root);
		count(2);
		flush();
		count(3);
		flush();
		check("Show: the branch kept while it stays chosen", made == 1, '$made');
		count(0);
		flush();
		count(4);
		flush();
		check("Show: made again when chosen again", made == 2, '$made');
		// Errored: an error while rendering, one later, reset
		var fail = signal(false);
		Render.render(<view tag="boundary"><Errored fallback={(e:Dynamic, reset:Void->Void) -> <text tag="fallback" onClick={_ -> reset()}>{"error: " + e}</text>}>
			<Thrower when={fail}/>
		</Errored></view>, ui.root);
		var bd = ui.root.find("boundary");
		var bounded = () -> [for (c in bd.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("Errored: the children", bounded() == "fine", bounded());
		fail(true);
		flush();
		check("Errored: a later error shows the fallback", bounded() == "error: boom", bounded());
		fail(false);
		flush();
		var fb = ui.root.find("fallback");
		ui.update();
		ui.pointerDown(fb.absX + 1, fb.absY + 1, 1);
		ui.pointerUp(fb.absX + 1, fb.absY + 1, 1);
		check("Errored: reset renders the children again", bounded() == "fine", bounded());
		var fail2 = signal(true);
		Render.render(<view tag="boundary2"><Errored fallback={(e:Dynamic, reset:Void->Void) -> "caught " + e}>
			<text>before</text>
			<Thrower when={fail2}/>
		</Errored></view>, ui.root);
		var bd2 = ui.root.find("boundary2");
		var bounded2 = [for (c in bd2.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("Errored: an error while rendering, what was made before removed", bounded2 == "caught boom", bounded2);
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
			<view tag="row" direction="row" justify="space-between" width={() -> wide() ? 200 : 100}>
				Hello {name}!
			</view>
			<Counter start={1}/>
			<view tag="list"><For each={items}>{i -> {
				made++;
				<text>{i}</text>;
			}}</For></view>
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
		name("Bo");
		flush();
		check("render: reactive text", hello.text == "Hello Bo!");
		wide(true);
		flush();
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
		items(["c", "b", "d"]);
		flush();
		check("for: reordered, one made", texts() == "c,b,d" && made == 4, texts() + " " + made);
		check("for: kept nodes", list.children.filter(c -> Std.isOfType(c, TextNode))[1] == firstB);
		// Show
		check("show: when true", top.find("shown") != null);
		shown(false);
		flush();
		var fallback = [for (c in top.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text];
		check("show: the fallback", top.find("shown") == null && fallback.contains("hidden"), fallback.join(","));
		shown(true);
		flush();
		check("show: back", top.find("shown") != null);
		dispose();
		check("render: dispose removes the content", ui.root.children.length == 0);
		name("gone");
		flush();
		check("render: and stops its effects", hello.text == "Hello Bo!");
		// attributes generated from Style's properties (StyleAttrs)
		var styled:Null<Node> = null;
		Render.render(<view ref={n -> styled = n} position="sticky" justify="flex-start" align-content="space-between" cursor="ew-resize" grid-auto-flow="column"
			font-weight="700" italic aspect-ratio={2} text-align="center" padding="8 12" min-width="50%" border-color="red" shadow="0 2 8 #00000040"
			text-shadow="1px 1px 2px red" outline="2px solid red" outline-offset={3}/>, ui.root);
		var st = styled.style;
		check("render: Style's properties as attributes", st.position == Position.Sticky && st.justify == Justify.Start && st.alignContent == AlignContent.SpaceBetween && st.cursor == Cursor.ResizeEW
			&& st.gridAutoFlow == Grid.GridFlow.Column && st.fontWeight == 700 && st.italic == true && st.aspectRatio == 2 && st.textAlign == TextAlign.Center
			&& st.padding.left == 12 && st.borderColor == Color.parse("red") && st.shadow != null
			&& st.textShadow != null && st.textShadow.blur == 2 && st.textShadow.color == Color.parse("red") && !st.textShadow.currentColor
			&& st.outlineWidth == 2 && st.outlineColor == Color.parse("red") && st.outlineOffset == 3);
		helder.ui.view.StyleAttrs.apply(st, "outline", "none");
		var badOutline = try {
			helder.ui.view.StyleAttrs.apply(st, "outline", "2px dashed red");
			false;
		} catch (e:Dynamic) true;
		check("render: outline=\"none\", a style it lacks thrown", st.outlineWidth == 0 && badOutline);
		// font-feature-settings: inherited into the font, "normal" the default ones, a mistake thrown
		var featured:Null<Node> = null, inner:Null<Node> = null, plain:Null<Node> = null;
		Render.render(<view ref={n -> featured = n} font-feature-settings="'tnum', 'liga' 0"><text ref={n -> inner = n}>12</text><view font-feature-settings="normal"><text ref={n -> plain = n}>34</text></view></view>, ui.root);
		var badFeature = try {
			featured.style.fontFeatureSettings = "tnum";
			false;
		} catch (e:Dynamic) true;
		var numeric:Null<Node> = null;
		Render.render(<view font-variant-numeric="tabular-nums slashed-zero" font-feature-settings="'zero' 0"><text ref={n -> numeric = n}>10</text></view>, ui.root);
		var badNumeric = try {
			numeric.style.fontVariantNumeric = "tabular";
			false;
		} catch (e:Dynamic) true;
		var slotted:Null<Node> = null, checkedNow = signal("checked");
		Render.render(<view ref={n -> slotted = n} slot="button" variant="outline" size="sm" data-state={() -> checkedNow()} data-disabled={true} aria-invalid="true"/>, ui.root);
		var firstState = slotted.attr("data-state");
		checkedNow("unchecked");
		flush();
		check("render: slot, variant, size and data-/aria- attributes (reactive)", slotted.slot == "button" && slotted.variant == "outline" && slotted.size == "sm"
			&& firstState == "checked" && slotted.attr("data-state") == "unchecked" && slotted.attr("data-disabled") == "" && slotted.attr("aria-invalid") == "true");
		var pic:Null<Node> = null;
		Render.render(<image ref={n -> pic = n} src={new Image(4, 4)} width={10} height={10} fit="contain" object-position="right 2px top"/>, ui.root);
		var pn:ImageNode = cast pic;
		check("render: an image's object-position", pn.positionX == 1 && pn.offsetX == -2 && pn.positionY == 0 && pn.offsetY == 0);
		check("render: font-variant-numeric as features, font-feature-settings after them", numeric.font().features == "'tnum', 'zero', 'zero' 0" && badNumeric
			&& helder.text.FontFeature.key(helder.text.FontFeature.parse(numeric.font().features)) == "tnum=1,zero=0", numeric.font().features);
		check("render: font-feature-settings, inherited", inner.font().features == "'tnum', 'liga' 0" && plain.font().features == "" && badFeature
			&& !inner.font().equals(plain.font()));
		var bad = try {
			Render.render(<view justify="sideways"/>, ui.root);
			"";
		} catch (e:Dynamic) Std.string(e);
		check("render: a value not of the property's enum", bad == "helder.ui: sideways is not a Justify", bad);
	}
}
