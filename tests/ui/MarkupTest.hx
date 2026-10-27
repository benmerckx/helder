import helder.ui.*;
import helder.view.*;
import helder.ui.view.*;
import helder.view.Flow.*;
import helder.ui.view.UiFlow.*;
import helder.view.Reactive.*;
import helder.ui.access.*;
import helder.ui.widgets.TextField;
import Plain.*;
import helder.image.Image;

// Markup rendered into helder.ui's nodes (helder.view on NodeRenderer), on Eval
// (bun run test ui runs it after UiTest; helder.view's own tests are
// tests/view): elements and
// style attributes, text runs, reactive text and attributes, regions,
// For and Show, components, events through a Ui; then context, onMount,
// Index, Switch and Match, Show's branches kept, ErrorBoundary; Motion's
// transitions, springs and colours on a Clock ticked by hand; the
// accessibility tree of plain controls in markup (Plain), its actions and
// changes; a Popover and a Hotkey; the neutral elements; a field's
// password, right to left; a part's states as signals; a VirtualList of
// 100000 rows scrolled
class MarkupTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	public static function main() {
		neutral();
		rendering();
		flow();
		motion();
		access();
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

	static function liveRegions() {
		var ui = new Ui(new MonoText(), 400, 300);
		var msg = signal("");
		Render.render(<view padding={10}><view tag="status" live="polite"><text>{msg}</text></view></view>, ui.root);
		ui.update();
		var t0 = ui.accessTree();
		msg.value = "Saved";
		ui.update();
		var t1 = ui.accessTree();
		var said = t1.announcements(t0);
		var region = [for (id in t1.order) if (t1.nodes.get(id).live == Polite) t1.nodes.get(id)];
		check("live: a region's new text announced, politely", said.length == 1 && said[0].text == "Saved" && said[0].live == Polite
			&& region.length == 1 && region[0].toJson().live == "polite" && region[0].role == Group, [for (s in said) s.text].join("|"));
		msg.value = "Saved and synced";
		ui.update();
		var t2 = ui.accessTree();
		check("live: what was added at its end; nothing when nothing changed", [for (s in t2.announcements(t1)) s.text].join("|") == "and synced"
			&& ui.accessTree().announcements(t2).length == 0, [for (s in t2.announcements(t1)) s.text].join("|"));
	}

	static function password() {
		var ui = new Ui(new MonoText(), 400, 300);
		var pw = signal("hunter2");
		Render.render(<view padding={10}><field tag="pw" value={pw} type="password" label="Password" onInput={e -> pw.value = e.text}/></view>, ui.root);
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
			&& clip.text == "before" && pw.value == "hunter2" && node.secret && node.value == "•••••••" && node.toJson().secret == true, node.value);
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
	}

	// UiFlow's Popover (its children in a popup while open: under the node
	// the markup puts it in, or at a point; Escape or a press outside asks
	// it to close) and Hotkey (a shortcut while it is mounted)
	static function popovers() {
		var ui = new Ui(new MonoText(), 400, 300);
		var open = signal(false), at = signal(false), dismissed = 0;
		Render.render(<view padding={10} row-gap={10} align-items="start">
			<view tag="anchor" width={60} height={20}>
				<Popover open={open} placement="below" onDismiss={() -> {
					dismissed++;
					open.value = false;
				}}><view tag="pop" width={80} height={30}/></Popover>
			</view>
			<Popover open={at} at={() -> {x: 200.0, y: 100.0}} onDismiss={() -> at.value = false}><view tag="at" width={20} height={20}/></Popover>
		</view>, ui.root);
		ui.update();
		check("popover: closed, nothing over the tree", ui.overlay.children.length == 0 && ui.overlay.find("pop") == null);
		open.value = true;
		ui.update();
		var anchor = ui.root.find("anchor"), pop = ui.overlay.find("pop");
		check("popover: open, under the node it is in", pop != null && pop.absY >= anchor.absY + anchor.height, pop == null ? "none" : '${pop.absX},${pop.absY}');
		ui.keyDown(Key.ESCAPE, 0);
		ui.update();
		check("popover: Escape asks it to close", dismissed == 1 && ui.overlay.find("pop") == null, '$dismissed');
		open.value = true;
		ui.update();
		ui.pointerDown(390, 290, 1);
		ui.pointerUp(390, 290, 1);
		ui.update();
		check("popover: a press outside too", dismissed == 2 && ui.overlay.find("pop") == null, '$dismissed');
		at.value = true;
		ui.update();
		var a = ui.overlay.find("at");
		check("popover: at a point", a != null && a.absX == 200 && a.absY == 100, a == null ? "none" : '${a.absX},${a.absY}');
		at.value = false;
		ui.update();
		check("popover: closed again", ui.overlay.find("at") == null);
		var on = signal(true), saved = 0;
		var dispose = Render.render(<view><Show when={on}><Hotkey keys="Mod+S" action={() -> saved++}/></Show></view>, ui.root);
		ui.keyDown("s".code, Key.MOD_CONTROL);
		on.value = false;
		ui.keyDown("s".code, Key.MOD_CONTROL);
		dispose();
		check("hotkey: while mounted", saved == 1, '$saved');
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
		first.value = false;
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
			<view:button tag="b" slot="button" focusable states={(s:States) -> (s.hovered.value ? {background: Color.rgb(0xFF0000)} : {} : StyleProps)}>Go</view:button>
			<view tag="c" data-state={() -> ticked.value ? "checked" : "unchecked"} states={(s:States) -> (s.attr("data-state").value == "checked" ? {opacity: 0.5} : {} : StyleProps)}/>
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
			&& hovered == Color.rgb(0xFF0000) && b.style.background == Color.rgb(0x111111) && !states.hovered.value, hovered.toHex() + " " + b.style.background.toHex());
		ticked.value = true;
		ui.update();
		check("states: an attribute as a signal (data-state)", c.style.opacity == 0.5 && States.of(c).attr("data-state").value == "checked");
		ui.setFocus(b);
		ui.keyDown(Key.TAB, 0);
		ui.keyDown(Key.TAB, 0);
		ui.setFocus(b, true);
		check("states: focused, focus-visible", States.of(b).focused.value);
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
			<field tag="name" value={name} placeholder="Name" label="Name" onInput={e -> name.value = e.text}/>
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
		Render.render(<view ref={n -> slotted = n} slot="button" variant="outline" size="sm" data-state={() -> checkedNow.value} data-disabled={true} aria-invalid="true"/>, ui.root);
		var firstState = slotted.attr("data-state");
		checkedNow.value = "unchecked";
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
