import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;
import helder.view.graph.Owner;
import helder.view.graph.Awaitable.Later;
import TestRenderer.TestNode;
import OtherRenderer.OtherNode;

// helder.view's tests, on Eval and natively (npm test -- view), on
// TestRenderer:
//
//   <tool> -cp src -cp tests/view --run ViewTest <tool>
//
// the graph as markup uses it (helder.view.graph: its own tests are
// tests/view/graph's; writes land at a flush); markup (elements, attributes, JSX's whitespace
// and entities, holes evaluated where the literal is, nesting, components
// and their props, text runs, reactive text, attributes and regions); the
// control flow components (For keyed by item and by index, Repeat, Show,
// Switch, Errored, Provider, onSettled; Loading over an async memo); two renderers (OtherRenderer: the same components
// rendered by each, boundaries between them, roots: Render.open's windows); and the programs the macro rejects (test/reject,
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
		loading();
		renderers();
		roots();
		#if sys
		var tool = Sys.args()[0];
		if (tool != null) rejects(tool, "tests/view/reject");
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
		if (!ok && detail == null) detail = "";
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
		var stop = root(d -> {
			effect(() -> a() + b(), v -> {
				runs++;
				seen = v;
			});
			d;
		});
		flush();
		check("an effect applies at the flush", runs == 1 && seen == 3);
		a(10);
		check("a write lands at the flush", runs == 1 && a() == 1);
		flush();
		check("then its effect runs", runs == 2 && seen == 12 && a() == 10);
		a(1);
		b(1);
		flush();
		check("two writes, one run", runs == 3 && seen == 2);
		a(c -> c + 1);
		a(c -> c + 1);
		flush();
		check("updates from the latest value written", a() == 3);
		stop();
		a(100);
		flush();
		check("a disposed root's effects stop", runs == 4, '$runs');
		// contexts
		var c = context("light");
		check("context: default and provided", root(_ -> use(c)) == "light" && root(_ -> provide(c, "dark", () -> use(c))) == "dark");
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
		// values of a type never reactive (a String, a number, a Bool, null of one) set as literals are; a function, a Signal or a Dynamic holding one bound
		var on = signal(true), k = 2, held:Dynamic = () -> on() ? "yes" : "no";
		var at = new TestNode(Element, "root");
		Render.render(<b title={k > 1 ? "big" : "small"} data-k={k * 2} data-f={on() ? "on" : "off"} data-s={on} data-d={held}/>, at);
		var first = at.toHtml();
		on(false);
		flush();
		check("plain values set once, holes that read, signals and a Dynamic holding a function bound",
			first == '<root><b data-d="yes" data-f="on" data-k="4" data-s="true" title="big"></b></root>'
			&& at.toHtml() == '<root><b data-d="no" data-f="off" data-k="4" data-s="false" title="big"></b></root>', first + " " + at.toHtml());
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
		check("a text holder holds text only, the error naming what it got", thrown == "helder.view: <p> holds text only, not Array", thrown);
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
		flush();
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
		return <b onClick={() -> count(c -> c + 1)}>{count}</b>;
	}

	// a prop that reads (Read): bound as Solid binds props, read where it is used
	static function Step(props:{step:Read<Int>, label:String}):View
		return <i title={props.label}>{props.step()}</i>;

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
		flush();
		check("a component's state", bs[0].children[0].text == "2" && bs[1].children[0].text == "5", root.children[0].toHtml());
		// props that read: a constant, a signal, a hole that reads given as a function of it
		var n = signal(2), made = 0;
		var root2 = new TestNode(Element, "root");
		Render.render(<div><Step step={1} label="c"/><Step step={n} label="s"/><Step step={n() * 10} label={"x" + n()}/></div>, root2);
		check("Read props", root2.toHtml() == '<root><div><i title="c">1</i><i title="s">2</i><i title="x2">20</i></div></root>', root2.toHtml());
		n(3);
		flush();
		check("Read props follow, plain ones are set once",
			root2.toHtml() == '<root><div><i title="c">1</i><i title="s">3</i><i title="x2">30</i></div></root>', root2.toHtml());
	}

	static function reactive() {
		var root = new TestNode(Element, "root");
		var name = signal("Ann"), wide = signal(false), show = signal(true);
		var dispose = Render.render(<div width={wide() ? 200 : 100} title={name}>
			Hello {name}!
			{show() ? <b>shown</b> : <>hidden</>}
		</div>, root);
		var div = root.children[0];
		check("reactive attributes", div.props.get("width") == 100 && div.props.get("title") == "Ann");
		check("reactive text", div.children[0].text == "Hello Ann!");
		name("Bo");
		wide(true);
		check("a write lands at the flush", div.children[0].text == "Hello Ann!");
		flush();
		check("updated", div.props.get("width") == 200 && div.props.get("title") == "Bo" && div.children[0].text == "Hello Bo!");
		check("a region", div.toHtml() == '<div title="Bo" width="200">Hello Bo!<b>shown</b></div>', div.toHtml());
		show(false);
		flush();
		check("a region drawn again", div.toHtml() == '<div title="Bo" width="200">Hello Bo!hidden</div>', div.toHtml());
		dispose();
		check("dispose removes the content", root.children.length == 0);
		name("gone");
		flush();
		check("and stops its effects", div.children[0].text == "Hello Bo!");
	}

	static final theme = context("light");

	// a value that comes later (as helder.asset's Asset): an async memo,
	// pending until set; fail: its error; refresh: a new one on its way
	static function later():Later<String>
		return new Later<String>();

	static function Themed(props:{}):View
		return <i>{"theme " + use(theme)}</i>;

	static function Thrower(props:{when:Signal<Bool>}):View
		return <i>{() -> {
			if (props.when()) throw "boom";
			"fine";
		}}</i>;

	// (a component reading a value not ready while it is made: made once it is)
	static function Shows(props:{value:Coming<String>}):View {
		var v = props.value.value();
		return <p>{"made with " + v}</p>;
	}

	// Loading: a fallback on the first load only; a value read in a hole,
	// in a memo, in a component's body; nested boundaries; a failure the
	// ErrorBoundary's; no boundary: nothing rendered; isPending
	static function loading() {
		var a = new Coming<String>();
		var root = new TestNode(Element, "root");
		Render.render(<div><Loading fallback="wait"><p>{a.value()}</p></Loading></div>, root);
		check("Loading: the fallback while what its children read is not ready", root.toHtml() == "<root><div>wait<!--loading--></div></root>", root.toHtml());
		a.set("one");
		flush();
		check("Loading: its children once it is", root.toHtml() == "<root><div><p>one</p><!--loading--></div></root>", root.toHtml());
		// (a reload: a new value on its way, then here; the fallback never again, the content held)
		var pending = [];
		var dispose = helder.view.graph.Graph.root(d -> {
			renderEffect(() -> isPending(() -> a.value()), v -> pending.push(v));
			d;
		});
		a.refresh();
		flush();
		check("Loading: a reload in flight: the content kept, isPending", root.toHtml() == "<root><div><p>one</p><!--loading--></div></root>" && pending.join(",") == "false,true",
			root.toHtml() + " " + pending.join(","));
		a.set("two");
		flush();
		check("Loading: the new value, no fallback", root.toHtml() == "<root><div><p>two</p><!--loading--></div></root>" && pending.join(",") == "false,true,false",
			root.toHtml() + " " + pending.join(","));
		dispose();
		// (isPending on a first load: false, the fallback says it)
		var b = new Coming<String>();
		check("isPending: false on a first load", !isPending(() -> b.value()));
		// (through a memo, and in a component's body: made once it is ready)
		var m = new Coming<String>(), c = new Coming<String>();
		var upper = memo(() -> m.value().toUpperCase());
		var root2 = new TestNode(Element, "root");
		Render.render(<div><Loading fallback="wait"><b>{upper}</b><Shows value={c}/></Loading></div>, root2);
		m.set("x");
		flush();
		check("Loading: one of two ready: the fallback", root2.toHtml() == "<root><div>wait<!--loading--></div></root>", root2.toHtml());
		c.set("y");
		flush();
		check("Loading: a memo's and a component's, both ready", root2.toHtml() == "<root><div><b>X</b><p>made with y</p><!--anchor--><!--loading--></div></root>", root2.toHtml());
		// (nested: the inner one's fallback alone)
		var outer = new Coming<String>(), inner = new Coming<String>();
		var root3 = new TestNode(Element, "root");
		Render.render(<div><Loading fallback="outer"><p>{outer.value()}</p><Loading fallback="inner"><b>{inner.value()}</b></Loading></Loading></div>, root3);
		outer.set("o");
		flush();
		check("Loading: nested, the inner one waits alone", root3.toHtml() == "<root><div><p>o</p>inner<!--loading--><!--loading--></div></root>", root3.toHtml());
		inner.set("i");
		flush();
		check("Loading: nested, both shown", root3.toHtml() == "<root><div><p>o</p><b>i</b><!--loading--><!--loading--></div></root>", root3.toHtml());
		// (a failure: the Errored above it)
		var f = new Coming<String>();
		var root4 = new TestNode(Element, "root");
		Render.render(<div><Errored fallback={(e:Dynamic, r:Void->Void) -> "failed: " + e}><Loading fallback="wait"><p>{f.value()}</p></Loading></Errored></div>, root4);
		f.fail("gone");
		flush();
		check("Loading: a failure is the Errored's", root4.toHtml() == "<root><div>failed: gone<!--boundary--></div></root>", root4.toHtml());
		// (no boundary: nothing for it, the rest rendered)
		var n = new Coming<String>();
		var root5 = new TestNode(Element, "root");
		Render.render(<div><i>here</i><p>{n.value()}</p></div>, root5);
		check("no Loading: nothing for what is not ready", root5.toHtml() == "<root><div><i>here</i><p></p></div></root>", root5.toHtml());
		n.set("late");
		flush();
		check("no Loading: it once it is", root5.toHtml() == "<root><div><i>here</i><p>late</p></div></root>", root5.toHtml());
	}

	static function flow() {
		// For: keyed rows kept and moved
		var items = signal(["a", "b", "c"]), made = 0;
		var root = new TestNode(Element, "root");
		Render.render(<ul><For each={items}>{i -> {
			made++;
			<li>{i}</li>;
		}}</For></ul>, root);
		var ul = root.children[0];
		function texts()
			return [for (c in ul.children) if (c.kind == Element) c.children[0].text].join(",");
		check("For: rows", texts() == "a,b,c" && made == 3, texts());
		var b = ul.children[1];
		TestRenderer.log.resize(0);
		items(["c", "b", "d"]);
		flush();
		check("For: reordered, one made, the rest kept", texts() == "c,b,d" && made == 4 && ul.children[1] == b, texts());
		TestRenderer.log.resize(0);
		items(["c", "b", "d", "e"]);
		flush();
		check("For: appended in place", texts() == "c,b,d,e" && TestRenderer.log.indexOf("arrange") < 0, TestRenderer.log.join(","));
		// For by index (keyed={false}): a row per index, its Read what is there
		var names = signal(["a", "b"]), rows = 0;
		var root2 = new TestNode(Element, "root");
		Render.render(<ul><For each={names} keyed={false}>{n -> {
			rows++;
			<li>{n() + "!"}</li>;
		}}</For></ul>, root2);
		names(["x", "b", "y"]);
		flush();
		var shown = [for (c in root2.children[0].children) if (c.kind == Element) c.children[0].text].join(",");
		check("For by index: items set in place, rows added", shown == "x!,b!,y!" && rows == 3, shown);
		// Repeat: a row per number
		var count = signal(2);
		var root6 = new TestNode(Element, "root");
		Render.render(<ul><Repeat count={count}>{i -> <li>{"" + i}</li>}</Repeat></ul>, root6);
		count(3);
		flush();
		check("Repeat", root6.toHtml() == "<root><ul><li>0</li><li>1</li><li>2</li><!--for--></ul></root>", root6.toHtml());
		// For and Index against random lists (keys once each): the rows as the
		// list has them, between the content around them, and For's row of a
		// key the same node while the key stays
		var seed = 5, bad = 0, lost = 0, first = "";
		function rnd(n:Int):Int {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return (seed >> 8) % n;
		}
		var keys = signal([0, 1, 2]), next = 3;
		var root3 = new TestNode(Element, "root");
		Render.render(<ul><b>head</b><For each={keys}>{k -> <li>{"" + k()}</li>}</For><i>mid</i><For each={keys} keyed={false}>{n -> <p>{"" + n()}</p>}</For><b>tail</b></ul>,
			root3);
		var list3 = root3.children[0];
		function rows():Map<Int, TestNode>
			return [for (c in list3.children) if (c.tag == "li") Std.parseInt(c.children[0].text) => c];
		for (step in 0...300) {
			var was = rows(), k = keys.peek().copy(), what;
			switch rnd(6) {
				case 0:
					k.insert(rnd(k.length + 1), next++);
					what = "insert";
				case 1 if (k.length > 0):
					k.splice(rnd(k.length), 1);
					what = "remove";
				case 2:
					for (i in 0...k.length) {
						var j = rnd(k.length), t = k[i];
						k[i] = k[j];
						k[j] = t;
					}
					what = "shuffle";
				case 3:
					k.reverse();
					what = "reverse";
				case 4:
					k = [for (x in k) if (rnd(2) == 0) x];
					for (i in 0...rnd(3))
						k.insert(rnd(k.length + 1), next++);
					what = "some kept, some new";
				case _:
					k = rnd(4) == 0 ? [] : [for (i in 0...rnd(6)) next++];
					what = "replaced";
			}
			keys(k);
			flush();
			var want = "<b>head</b>" + [for (x in k) '<li>$x</li>'].join("") + "<i>mid</i>" + [for (i in 0...k.length) '<p>${k[i]}</p>'].join("") + "<b>tail</b>";
			var got = [for (c in list3.children) if (c.kind != Marker) c.toHtml()].join("");
			if (got != want) {
				bad++;
				if (first == "") first = 'step $step ($what): $got';
			}
			var now = rows();
			for (x => n in now)
				if (was.exists(x) && was.get(x) != n) lost++;
		}
		check("For by item and by index: random lists, 300 changes", bad == 0 && lost == 0, bad + " differ, " + lost + " rows made again; the first: " + first);
		// Show: the branch kept while it stays chosen
		var count = signal(1), refs = 0;
		check("Show", html(<div><Show when={count() > 0} fallback="none"><i ref={_ -> refs++}/></Show></div>) == "<div><i></i><!--anchor--></div>");
		count(2);
		flush();
		check("Show: the branch kept", refs == 1);
		count(0);
		flush();
		count(3);
		flush();
		check("Show: made again when chosen again", refs == 2);
		// Switch and Match
		var k = signal(1);
		var root3 = new TestNode(Element, "root");
		Render.render(<div><Switch fallback="many">
			<Match when={k() == 0}>none</Match>
			<Match when={k() == 1}><b>one</b></Match>
		</Switch></div>, root3);
		check("Switch: a case", root3.toHtml() == "<root><div><b>one</b><!--anchor--></div></root>", root3.toHtml());
		k(0);
		flush();
		check("Switch: another", root3.toHtml() == "<root><div>none<!--anchor--></div></root>", root3.toHtml());
		k(7);
		flush();
		check("Switch: the fallback", root3.toHtml() == "<root><div>many<!--anchor--></div></root>", root3.toHtml());
		var thrown = try {
			html(<Switch><b/></Switch>);
			"";
		} catch (e:Dynamic) Std.string(e);
		check("Switch: Match cases only", thrown == "helder.view: a Switch holds Match cases only", thrown);
		// Provider and onSettled
		check("Provider", html(<div><Themed/><Provider context={theme} value={"dark"}><Themed/></Provider></div>) == "<div><i>theme light</i><i>theme dark</i></div>");
		var parentAtMount:Null<TestNode> = null;
		var root4 = new TestNode(Element, "root");
		Render.render(<b ref={n -> onSettled(() -> parentAtMount = n.parent)}/>, root4);
		check("onSettled: after the insertion", parentAtMount == root4);
		// Errored: an error later, reset; an error while rendering
		var fail = signal(false), reset:Null<Void->Void> = null;
		var root5 = new TestNode(Element, "root");
		Render.render(<div><Errored fallback={(e:Dynamic, r:Void->Void) -> {
			reset = r;
			"error: " + e;
		}}><Thrower when={fail}/></Errored></div>, root5);
		check("Errored: the children", root5.toHtml() == "<root><div><i>fine</i><!--boundary--></div></root>", root5.toHtml());
		fail(true);
		flush();
		check("Errored: a later error", root5.toHtml() == "<root><div>error: boom<!--boundary--></div></root>", root5.toHtml());
		fail(false);
		flush();
		reset();
		flush();
		check("Errored: reset", root5.toHtml() == "<root><div><i>fine</i><!--boundary--></div></root>", root5.toHtml());
		var fail2 = signal(true);
		check("Errored: what was made before the error removed",
			html(<div><Errored fallback={(e:Dynamic, r:Void->Void) -> "caught " + e}><b>before</b><Thrower when={fail2}/></Errored></div>)
			== "<div>caught boom<!--boundary--></div>");
	}

	// a boundary: a node of TestRenderer's tree whose content is rendered
	// by OtherRenderer into a root of its own (a canvas in a page): its
	// children OtherRenderer's markup (ViewOf), itself TestRenderer's (its node)
	static function Island(props:{?children:ViewOf<OtherRenderer>}):TestNode {
		var host = TestRenderer.createElement("island");
		var root = new OtherNode("root");
		host.props.set("root", root);
		Render.render(props.children, root);
		return host;
	}

	// the other way: TestRenderer's content in OtherRenderer's tree (a page's element over a canvas)
	static function Overlay(props:{?children:ViewOf<TestRenderer>}):OtherNode {
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
		var ab = signal(["a", "b"]);
		Render.render(<div><Counter start={3}/><For each={ab}>{s -> <i>{s}</i>}</For></div>, test);
		Render.render(<div><Counter start={3}/><For each={ab}>{s -> <i>{s}</i>}</For></div>, other);
		check("renderers: a component in each", test.toHtml() == "<root><div><b>3</b><i>a</i><i>b</i><!--for--></div></root>" && other.toString() == "[root[div[b3][ia][ib]]]",
			test.toHtml() + " " + other.toString());
		// boundaries, either way, content reactive across them
		var label = signal("x");
		var page = new TestNode(Element, "root");
		Render.render(<div>
			<Island><p>{label}</p><Overlay><span>{"in " + label()}</span></Overlay></Island>
		</div>, page);
		var island = page.find("island");
		var inner:OtherNode = island.props.get("root");
		check("renderers: an island", inner.toString() == "[root[px][overlay dom=root]]", inner.toString());
		check("renderers: and in it a TestRenderer tree again", overlays[0].toHtml() == "<root><span>in x</span></root>", overlays[0].toHtml());
		label("y");
		flush();
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
		check("renderers: a class's markup not for a renderer, an error when mounted", ~/^helder.view: View\(ViewTest.hx:[0-9]+\) is markup for another renderer than TestRenderer, whose node it is mounted into$/.match(own),
			own);
	}

	// a root (RootView): a window of TestRenderer's, its children that renderer's markup
	static function Window(props:{name:String, ?children:ViewOf<TestRenderer>}):RootView {
		var w = new TestNode(Element, props.name);
		windows.push(w);
		onCleanup(() -> windows.remove(w));
		Render.render(props.children, w);
		return null;
	}

	// one on OtherRenderer: a root's children may be any renderer's
	static function OtherWindow(props:{?children:ViewOf<OtherRenderer>}):RootView {
		var w = new OtherNode("other");
		otherWindows.push(w);
		Render.render(props.children, w);
		return null;
	}

	static final windows:Array<TestNode> = [];
	static final otherWindows:Array<OtherNode> = [];

	// roots (Render.open): components only, each its own root (several <Surface>s)
	static function roots() {
		var title = signal("a");
		var shown = signal(true);
		var dispose = Render.open(<>
			<Window name="one"><p>{title}</p></Window>
			<Show when={shown}><Window name="two"><Counter start={1}/></Window></Show>
			<OtherWindow><Counter start={2}/></OtherWindow>
		</>);
		check("roots: a window each", windows.length == 2 && windows[0].toHtml() == "<one><p>a</p></one>" && windows[1].toHtml() == "<two><b>1</b></two>",
			[for (w in windows) w.toHtml()].join(" "));
		check("roots: a component under two renderers", otherWindows.length == 1 && otherWindows[0].toString() == "[other[b2]]", otherWindows.toString());
		title("b");
		flush();
		check("roots: reactive", windows[0].toHtml() == "<one><p>b</p></one>", windows[0].toHtml());
		shown(false);
		flush();
		check("roots: a root's region (Show): its window closed", windows.length == 1, Std.string(windows.length));
		dispose();
		check("roots: disposed, closed", windows.length == 0, Std.string(windows.length));
		// (a root mounted into a renderer's node: an error; reject/RootInMarkup.hx when compiled)
		var e = try {
			var root:RootView = <Window name="x"/>;
			Render.render(root, new TestNode(Element, "root"));
			"mounted";
		} catch (e:Dynamic) Std.string(e);
		check("roots: a root's content mounted into a node, an error", StringTools.startsWith(e, "helder.view: View(ViewTest.hx:") && e.indexOf("another renderer than TestRenderer") > 0, e);
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
			var args = ["-cp", "src", "-cp", dir, "-main", f.substr(0, f.length - 3), "--interp", "--no-output"];
			args = args.concat(["-cp", "tests/view"]);
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

// a value that comes later (as helder.asset's Asset): value an async
// memo, pending until set (a Later answered at the next flush); fail: its
// error; refresh: a new one on its way, the last one kept meanwhile
class Coming<T> {
	public final value:helder.view.graph.Memo<T>;

	var next:Later<T>;
	final asked:Signal<Int>;

	public function new() {
		next = new Later<T>();
		asked = signal(0);
		value = root(_ -> memo(() -> {
			asked();
			next;
		}));
	}

	public function set(v:T)
		next.resolve(v);

	public function fail(e:String)
		next.reject(e);

	public function refresh() {
		next = new Later<T>();
		asked(c -> c + 1);
	}
}
