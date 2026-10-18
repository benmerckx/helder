import hxmc.view.*;
import hxmc.view.Flow.*;
import hxmc.view.Reactive.*;
import TestRenderer.TestNode;
import OtherRenderer.OtherNode;

// hxmc.view's tests, on Eval and natively (make view-check), on
// TestRenderer:
//
//   <tool> -cp packages/view/src -cp packages/view/test -D hxmc.view.renderer=TestRenderer \
//     -D hxmc.view.renderer.other=OtherRenderer --run ViewTest <tool>
//
// signals, memos and effects (tracking, batching, no glitches, ownership
// and cleanup, contexts); markup (elements, attributes, JSX's whitespace
// and entities, holes evaluated where the literal is, nesting, components
// and their props, text runs, reactive text, attributes and regions); the
// control flow components (For, Index, Show, Switch, ErrorBoundary,
// Provider, onMount); two renderers (OtherRenderer: the same components
// rendered by each, boundaries between them); and the programs the macro rejects (test/reject,
// "// expect:" lines; with the tool's path as the argument); on Eval,
// natively and in JavaScript (node)
class ViewTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	static function main() {
		signals();
		markup();
		components();
		reactive();
		flow();
		renderers();
		#if sys
		var tool = Sys.args()[0];
		if (tool != null) rejects(tool, "packages/view/test/reject");
		#end
		println('ViewTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		#if js
		js.Syntax.code("process.exit({0})", failed == 0 ? 0 : 1);
		#else
		Sys.exit(failed == 0 ? 0 : 1);
		#end
	}

	static function println(s:String) {
		#if js
		js.Syntax.code("console.log({0})", s);
		#else
		Sys.println(s);
		#end
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			println('ViewTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	// content rendered into a new root element, as HTML
	static function html(content:Any):String {
		var root = new TestNode(Element, "root");
		Render.render(content, root);
		return [for (c in root.children) c.toHtml()].join("");
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
		var bm = memo(() -> x.value * 2);
		var cm = memo(() -> x.value + 1);
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
		var lazy = 0, src = signal(1);
		var m = memo(() -> {
			lazy++;
			src.value;
		});
		src.value = 2;
		src.value = 3;
		check("a memo nobody reads waits", lazy == 1 && m.value == 3 && lazy == 2, '$lazy');
		// untrack, peek, update
		var u = signal(1), ur = 0;
		effect(() -> {
			untrack(() -> u.value);
			u.peek();
			ur++;
		});
		u.update(v -> v + 1);
		check("untrack and peek do not track", ur == 1 && u.value == 2);
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
		// runWithOwner: work placed in another owner, disposed with it
		var o:Null<Owner> = null, placed = 0, t = signal(0);
		var stop = root(d -> {
			o = getOwner();
			d;
		});
		runWithOwner(o, () -> effect(() -> {
			t.value;
			placed++;
		}));
		t.value = 1;
		stop();
		t.value = 2;
		check("runWithOwner", placed == 2, '$placed');
		// contexts
		var c = context("light");
		check("context: default and provided", use(c) == "light" && provide(c, "dark", () -> use(c)) == "dark");
	}

	static function item(label:String):View
		return <li class="item">{label}</li>;

	static function section(title:String, content:View):View
		return <section title={title}>{content}</section>;

	static function markup() {
		check("elements and attributes", html(<div id="main" class='a b' hidden data-x={1 + 1}><span>static</span>{"dynamic"}</div>)
			== '<div class="a b" data-x="2" hidden="true" id="main"><span>static</span>dynamic</div>');
		check("a fragment", html(<><b/><i/></>) == "<b></b><i></i>");
		var spread = {title: "t", tabindex: 2};
		check("a spread", html(<a {...spread} href="#"/>) == '<a href="#" tabindex="2" title="t"></a>');
		var v = <i/>;
		check("source", StringTools.startsWith(v.source, "ViewTest.hx:"), v.source);
		// holes: evaluated where the literal is, once; mounted any number of times
		var n = 0;
		var e = <p count={n++}>{n++}</p>;
		check("holes evaluated when the literal runs", n == 2);
		check("mounted twice", html(e) == '<p count="0">1</p>' && html(e) == '<p count="0">1</p>' && n == 2);
		// whitespace and entities as JSX has them
		check("JSX's whitespace", html(<p>
			Hello,
			world!   Two  spaces stay
		</p>) == "<p>Hello, world!   Two  spaces stay</p>");
		check("entities", html(<b title="a &amp; b">&lt;tag&gt; &#65;&#x42; &lbrace;x&rbrace;</b>) == '<b title="a &amp; b">&lt;tag&gt; AB {x}</b>');
		check("an empty expression is no child", html(<b>{/* a comment */}text</b>) == "<b>text</b>");
		// text runs: a run of text and text holes is one text node
		var name = "Ann";
		var root = new TestNode(Element, "root");
		Render.render(<div>Hi {name}, you have {3} new<br/>{"x"}{<i/>}</div>, root);
		var div = root.find("div");
		check("a run of text is one node", div.children.length == 4 && div.children[0].text == "Hi Ann, you have 3 new" && div.children[2].text == "x",
			div.toHtml());
		// an element that holds text: its own text, or spans beside its elements
		check("text held", html(<p>Hi {name}!</p>) == "<p>Hi Ann!</p>");
		var p = new TestNode(Element, "root");
		Render.render(<p>a <b>b</b> {"c"}</p>, p);
		var held = p.children[0];
		check("spans in a text holder", held.text == "" && held.children.length == 3 && held.children[0].tag == "span" && held.children[0].text == "a "
			&& held.children[2].tag == "span" && held.children[2].text == " c", held.toHtml());
		var thrown = try {
			html(<p>{[1, 2]}</p>);
			"";
		} catch (e:Dynamic) Std.string(e);
		check("a text holder holds text only, the error naming what it got", thrown == "hxmc.view: <p> holds text only, not Array", thrown);
		var none:Null<String> = null;
		check("a text holder's null hole: no text, as a run's", html(<p>a{none}b</p>) == "<p>ab</p>", html(<p>a{none}b</p>));
		// nesting through expressions
		var items = ["a", "b", "c"];
		check("markup inside an expression", html(<ul>{[for (i in items) item(i)]}</ul>) == '<ul><li class="item">a</li><li class="item">b</li><li class="item">c</li></ul>');
		check("a ternary of markup", html(<div>{items.length > 2 ? <b>{"many " + items.join("")}</b> : <i>few</i>}</div>) == "<div><b>many abc</b></div>");
		check("View.view", html(View.view(<b>{1}</b>)) == "<b>1</b>");
		// an expression's end found past the markup and strings in it
		check("an apostrophe in a nested attribute", html(<div>{section("X", <Button label="it's"/>)}</div>)
			== '<div><section title="X"><button class="plain">it\'s</button></section></div>');
		check("a quote in a nested single-quoted attribute", html(<div>{section("Y", <b title='say "hi"'/>)}</div>)
			== '<div><section title="Y"><b title="say &quot;hi&quot;"></b></section></div>');
		check("braces in nested attributes and text", html(<div>{section("{", <b title="}{" data-x='{'>a } b</b>)}</div>)
			== '<div><section title="{"><b data-x="{" title="}{">a } b</b></section></div>');
		check("comment starts in nested attributes and text", html(<div>{section("//", <a href="http://x/*y">http://x /* z</a>)}</div>)
			== '<div><section title="//"><a href="http://x/*y">http://x /* z</a></section></div>');
		check("an apostrophe and a quote in nested text", html(<div>{section("t", <i>it's "q"</i>)}</div>)
			== '<div><section title="t"><i>it\'s "q"</i></section></div>');
		check("markup in braces in markup in braces", html(<div>{section("o", <b>{section("i", <i title="it's">it's</i>)}</b>)}</div>)
			== '<div><section title="o"><b><section title="i"><i title="it&#039;s">it\'s</i></section></b></section></div>');
		check("interpolation in an expression", html(<b>{'it${"'"}s ${[for (i in items) '<$i>'].join("")} {x}'}</b>) == "<b>it's &lt;a&gt;&lt;b&gt;&lt;c&gt; {x}</b>");
		var one = 1, two = 2;
		check("less-than and type parameters in an expression", html(<b>{one<two ? "lt" : "ge"}{(one < two) ? (new Array<Int>()).length : -1}{(cast items : Array<String>).length}</b>) == "<b>lt03</b>");
		check("markup after a condition", html(<div>{if (one < two) <i>it's</i> else <b>{"no"}</b>}</div>) == "<div><i>it's</i></div>");
		// lambdas in attributes: markup after ->, return, =>, ?, :, =; a less-than after a name or a number
		check("markup returned by an attribute lambda", html(<div><Rows count={2} render={i -> <Card>{i}</Card>}/><Rows count={1} render={(i) -> <Card/>}/><Rows
			count={1} render={function(i) return <Card>f{i}</Card>}/></div>) == "<div><ul><li>0</li><li>1</li></ul><ul><li></li></ul><ul><li>f0</li></ul></div>");
		check("comparisons in an attribute lambda", html(<div><Rows count={3} render={(i) -> i < 1 ? <Card>lt</Card> : <Card>{i<2 ? "a" : "b"}</Card>}/><Rows
			count={3} render={i -> <li title={i <= 1 ? "le" : "gt"} x={1 << i}>{new Array<Int>().length + i}</li>}/></div>)
			== '<div><ul><li>lt</li><li>a</li><li>b</li></ul><ul><li title="le" x="1">0</li><li title="le" x="2">1</li><li title="gt" x="4">2</li></ul></div>');
		check("markup after => and = in an attribute lambda", html(<div><Rows count={2} render={i -> [0 => <Card>zero</Card>, 1 => <Card>one</Card>][i]}/><Rows
			count={1} render={i -> {
				var v = <Card>{i}</Card>;
				v;
			}}/></div>) == "<div><ul><li>zero</li><li>one</li></ul><ul><li>0</li></ul></div>");
		var count = 1;
		check("a root closed by its closing tag", html(<Rows count={2} render={i -> i < count ? <Card>{i}</Card> : <Card/>}></Rows>) == "<ul><li>0</li><li></li></ul>");
		// events and refs
		var clicked = 0, got:Null<TestNode> = null;
		var root2 = new TestNode(Element, "root");
		Render.render(<button onClick={() -> clicked++} ref={n -> got = n} key="k"/>, root2);
		var btn = root2.children[0];
		(btn.listeners.get("onClick") : Void->Void)();
		check("an event listened to, a ref, key ignored", clicked == 1 && got == btn && !btn.props.exists("key") && !btn.props.exists("onClick"));
	}

	static function Button(props:{label:String, ?primary:Bool, ?onClick:Void->Void, ?children:View}):View
		return <button class={props.primary == true ? "primary" : "plain"}>{props.label}{props.children}</button>;

	static function Rows(props:{count:Int, render:Int->View}):View
		return <ul>{[for (i in 0...props.count) props.render(i)]}</ul>;

	static function Card(props:{?children:View}):View
		return <li>{props.children}</li>;

	static function Counter(props:{start:Int}):View {
		var count = signal(props.start);
		return <b onClick={() -> count.value++}>{count}</b>;
	}

	static function components() {
		check("a component and its props", html(<div><Button label="OK" primary/></div>) == '<div><button class="primary">OK</button></div>');
		check("its children", html(<Button label="Go"><i>now</i></Button>) == '<button class="plain">Go<i>now</i></button>');
		check("a dotted path", html(<ViewTest.Button label="dot"/>) == '<button class="plain">dot</button>');
		// called when mounted, untracked, its state its own
		var calls = 0;
		function Probe(props:{}):View {
			calls++;
			return <i/>;
		}
		var e = <div><Probe/></div>;
		check("called when mounted", calls == 0 && html(e) == "<div><i></i></div>" && calls == 1);
		var root = new TestNode(Element, "root");
		Render.render(<div><Counter start={1}/><Counter start={5}/></div>, root);
		var bs = root.children[0].children;
		(bs[0].listeners.get("onClick") : Void->Void)();
		check("a component's state", bs[0].children[0].text == "2" && bs[1].children[0].text == "5", root.children[0].toHtml());
	}

	static function reactive() {
		var root = new TestNode(Element, "root");
		var name = signal("Ann"), wide = signal(false), show = signal(true);
		var dispose = Render.render(<div width={() -> wide.value ? 200 : 100} title={name}>
			Hello {name}!
			{() -> show.value ? <b>shown</b> : <>hidden</>}
		</div>, root);
		var div = root.children[0];
		check("reactive attributes", div.props.get("width") == 100 && div.props.get("title") == "Ann");
		check("reactive text", div.children[0].text == "Hello Ann!");
		name.value = "Bo";
		wide.value = true;
		check("updated", div.props.get("width") == 200 && div.props.get("title") == "Bo" && div.children[0].text == "Hello Bo!");
		check("a region", div.toHtml() == '<div title="Bo" width="200">Hello Bo!<b>shown</b><!--anchor--></div>', div.toHtml());
		show.value = false;
		check("a region drawn again", div.toHtml() == '<div title="Bo" width="200">Hello Bo!hidden<!--anchor--></div>', div.toHtml());
		dispose();
		check("dispose removes the content", root.children.length == 0);
		name.value = "gone";
		check("and stops its effects", div.children[0].text == "Hello Bo!");
	}

	static final theme = context("light");

	static function Themed(props:{}):View
		return <i>{"theme " + use(theme)}</i>;

	static function Thrower(props:{when:Signal<Bool>}):View
		return <i>{() -> {
			if (props.when.value) throw "boom";
			"fine";
		}}</i>;

	static function flow() {
		// For: keyed rows kept and moved
		var items = signal(["a", "b", "c"]), made = 0;
		var root = new TestNode(Element, "root");
		Render.render(<ul><For each={items} render={(i:String) -> {
			made++;
			<li>{i}</li>;
		}}/></ul>, root);
		var ul = root.children[0];
		function texts()
			return [for (c in ul.children) if (c.kind == Element) c.children[0].text].join(",");
		check("For: rows", texts() == "a,b,c" && made == 3, texts());
		var b = ul.children[1];
		TestRenderer.log.resize(0);
		items.value = ["c", "b", "d"];
		check("For: reordered, one made, the rest kept", texts() == "c,b,d" && made == 4 && ul.children[1] == b, texts());
		TestRenderer.log.resize(0);
		items.value = ["c", "b", "d", "e"];
		check("For: appended in place", texts() == "c,b,d,e" && TestRenderer.log.indexOf("arrange") < 0, TestRenderer.log.join(","));
		// Index
		var names = signal(["a", "b"]), rows = 0;
		var root2 = new TestNode(Element, "root");
		Render.render(<ul><Index each={names} render={(n:Signal<String>, i:Int) -> {
			rows++;
			<li>{() -> i + ":" + n.value}</li>;
		}}/></ul>, root2);
		names.value = ["x", "b", "y"];
		var shown = [for (c in root2.children[0].children) if (c.kind == Element) c.children[0].text].join(",");
		check("Index: items set in place, rows added", shown == "0:x,1:b,2:y" && rows == 3, shown);
		// Show: the branch kept while it stays chosen
		var count = signal(1), refs = 0;
		check("Show", html(<div><Show when={() -> count.value > 0} fallback="none"><i ref={_ -> refs++}/></Show></div>) == "<div><i></i><!--anchor--></div>");
		count.value = 2;
		check("Show: the branch kept", refs == 1);
		count.value = 0;
		count.value = 3;
		check("Show: made again when chosen again", refs == 2);
		// Switch and Match
		var k = signal(1);
		var root3 = new TestNode(Element, "root");
		Render.render(<div><Switch fallback="many">
			<Match when={() -> k.value == 0}>none</Match>
			<Match when={() -> k.value == 1}><b>one</b></Match>
		</Switch></div>, root3);
		check("Switch: a case", root3.toHtml() == "<root><div><b>one</b><!--anchor--></div></root>", root3.toHtml());
		k.value = 0;
		check("Switch: another", root3.toHtml() == "<root><div>none<!--anchor--></div></root>", root3.toHtml());
		k.value = 7;
		check("Switch: the fallback", root3.toHtml() == "<root><div>many<!--anchor--></div></root>", root3.toHtml());
		var thrown = try {
			html(<Switch><b/></Switch>);
			"";
		} catch (e:Dynamic) Std.string(e);
		check("Switch: Match cases only", thrown == "hxmc.view: a Switch holds Match cases only", thrown);
		// Provider and onMount
		check("Provider", html(<div><Themed/><Provider context={theme} value={"dark"}><Themed/></Provider></div>) == "<div><i>theme light</i><i>theme dark</i></div>");
		var parentAtMount:Null<TestNode> = null;
		var root4 = new TestNode(Element, "root");
		Render.render(<b ref={n -> onMount(() -> parentAtMount = n.parent)}/>, root4);
		check("onMount: after the insertion", parentAtMount == root4);
		// ErrorBoundary: an error later, reset; an error while rendering
		var fail = signal(false), reset:Null<Void->Void> = null;
		var root5 = new TestNode(Element, "root");
		Render.render(<div><ErrorBoundary fallback={(e:Dynamic, r:Void->Void) -> {
			reset = r;
			"error: " + e;
		}}><Thrower when={fail}/></ErrorBoundary></div>, root5);
		check("ErrorBoundary: the children", root5.toHtml() == "<root><div><i>fine</i><!--boundary--></div></root>", root5.toHtml());
		fail.value = true;
		check("ErrorBoundary: a later error", root5.toHtml() == "<root><div>error: boom<!--boundary--></div></root>", root5.toHtml());
		fail.value = false;
		reset();
		check("ErrorBoundary: reset", root5.toHtml() == "<root><div><i>fine</i><!--boundary--></div></root>", root5.toHtml());
		var fail2 = signal(true);
		check("ErrorBoundary: what was made before the error removed",
			html(<div><ErrorBoundary fallback={(e:Dynamic, r:Void->Void) -> "caught " + e}><b>before</b><Thrower when={fail2}/></ErrorBoundary></div>)
			== "<div>caught boom<!--boundary--></div>");
	}


	// a boundary: a node of TestRenderer's tree whose content is rendered
	// by OtherRenderer into a root of its own (a canvas in a page)
	static function Island(props:{?children:View}):Any {
		var host = TestRenderer.createElement("island");
		var root = new OtherNode("root");
		host.props.set("root", root);
		Render.render(props.children, root);
		return host;
	}

	// the other way: TestRenderer's content in OtherRenderer's tree (a page's element over a canvas)
	static function Overlay(props:{?children:View}):Any {
		var host = OtherRenderer.createElement("overlay");
		var root = new TestNode(Element, "root");
		host.attrs.push("dom=" + root.tag);
		Render.render(props.children, root);
		overlays.push(root);
		return host;
	}

	static final overlays:Array<TestNode> = [];

	static function renderers() {
		// one component, each renderer's nodes
		var count = signal(1);
		var test = new TestNode(Element, "root"), other = new OtherNode("root");
		Render.render(<div><Counter start={3}/><For each={signal(["a", "b"])} render={(s:String) -> <i>{s}</i>}/></div>, test);
		Render.render(<div><Counter start={3}/><For each={signal(["a", "b"])} render={(s:String) -> <i>{s}</i>}/></div>, other);
		check("renderers: a component in each", test.toHtml() == "<root><div><b>3</b><i>a</i><i>b</i><!--for--></div></root>" && other.toString() == "[root[div[b3][ia][ib]]]",
			test.toHtml() + " " + other.toString());
		// boundaries, either way, content reactive across them
		var label = signal("x");
		var page = new TestNode(Element, "root");
		Render.render(<div>
			<Island><p>{label}</p><Overlay><span>{() -> "in " + label.value}</span></Overlay></Island>
		</div>, page);
		var island = page.find("island");
		var inner:OtherNode = island.props.get("root");
		check("renderers: an island", inner.toString() == "[root[px][overlay dom=root]]", inner.toString());
		check("renderers: and in it a TestRenderer tree again", overlays[0].toHtml() == "<root><span>in x</span></root>", overlays[0].toHtml());
		label.value = "y";
		check("renderers: reactive across boundaries", inner.toString() == "[root[py][overlay dom=root]]" && overlays[0].toHtml() == "<root><span>in y</span></root>",
			inner.toString() + " " + overlays[0].toHtml());
		// a class's components for some renderers (@:renderer): another's markup calls its counterpart's, shared literals too
		var test = new TestNode(Element, "root"), other = new OtherNode("root");
		Render.render(<div><OtherWidgets.Badge label="hi"/></div>, test);
		Render.render(<div><OtherWidgets.Badge label="hi"/></div>, other);
		check("renderers: a component per renderer (@:renderer)", test.toHtml() == "<root><div><span class=\"badge\">hi</span></div></root>"
			&& other.toString() == "[root[div[badgehi]]]", test.toHtml() + " " + other.toString());
		var test = new TestNode(Element, "root"), other = new OtherNode("root");
		var shared = <OtherWidgets.Badge label="both"/>;
		Render.render(shared, test);
		Render.render(shared, other);
		check("renderers: a component per renderer in a literal both share", test.toHtml() == "<root><span class=\"badge\">both</span></root>"
			&& other.toString() == "[root[badgeboth]]", test.toHtml() + " " + other.toString());
		// (the class's own markup in another renderer: an error when mounted; a component with none for a renderer: reject/MarkupRenderer.hx)
		var own = try {
			Render.render(OtherWidgets.Badge({label: "x"}), new TestNode(Element, "root"));
			"mounted";
		} catch (e:Dynamic) Std.string(e);
		var pair = new OtherNode("root");
		Render.render(OtherWidgets.Pair({}), pair);
		check("renderers: a shared literal of a class for some renderers", pair.toString() == "[root[mark]]", pair.toString());
		check("renderers: a class's markup not for a renderer, an error when mounted", own == "hxmc.view: OtherWidgets markup is not for TestRenderer (@:renderer)",
			own);
	}

	#if sys
	static function rejects(tool:String, dir:String) {
		var files = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".hx")) f];
		files.sort(Reflect.compare);
		for (f in files) {
			var content = sys.io.File.getContent('$dir/$f');
			var expect = [
				for (l in content.split("\n"))
					if (StringTools.startsWith(l, "// expect: ")) StringTools.trim(l.substr(11))
			];
			var args = ["-cp", "packages/view/src", "-cp", dir, "-main", f.substr(0, f.length - 3), "--interp", "--no-output"];
			if (content.indexOf("// no renderer") < 0) args = args.concat(["-cp", "packages/view/test", "-D", "hxmc.view.renderer=TestRenderer"]);
			var p = new sys.io.Process(tool, args);
			var out = p.stdout.readAll().toString() + p.stderr.readAll().toString();
			var code = p.exitCode();
			p.close();
			var missing = [for (e in expect) if (out.indexOf(e) < 0) e];
			check('reject/$f', code != 0 && expect.length > 0 && missing.length == 0,
				code == 0 ? "compiled, but must be rejected" : "missing: " + missing.join("; ") + "\n" + out);
		}
	}
	#end
}

// (OtherRenderer's widgets: TestRenderer's markup calls TestWidgets' of the same name)
@:renderer(OtherRenderer, TestRenderer => TestWidgets)
class OtherWidgets implements Markup {
	public static function Badge(props:{label:String}):View
		return <badge>{props.label}</badge>;

	// (a literal of a component alone, shared by every renderer: one with none for TestRenderer compiles, the class not being for it)
	public static function Pair(props:{}):View
		return <OtherOnly.Mark/>;
}

// (OtherRenderer's only, with no counterparts)
@:renderer(OtherRenderer)
class OtherOnly implements Markup {
	public static function Mark(props:{}):View
		return <mark/>;
}

class TestWidgets implements Markup {
	public static function Badge(props:{label:String}):View
		return <span class="badge">{props.label}</span>;
}
