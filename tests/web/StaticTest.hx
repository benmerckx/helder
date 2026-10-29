import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;
import helder.web.*;

// The static renderer (npm test -- web), on Eval and natively:
//
//   <tool> -cp src -cp tests/web --run StaticTest
//
// escaping (text, attributes, script and style), void elements, boolean
// attributes, properties as the parser makes them, styles, SVG, the
// markers hydration reads (pairs around regions and lists, separators
// between texts, empty texts), islands and their props.
class StaticTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	static function main() {
		escaping();
		attributes();
		markers();
		islands();
		Sys.println('StaticTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function check(what:String, got:String, want:String) {
		checks++;
		if (got != want) {
			failed++;
			Sys.println('StaticTest: FAIL: $what\n  got:  $got\n  want: $want');
		}
	}

	static function escaping() {
		var evil = '<script>alert("&")</script>';
		check("text", Static.render(<p>{evil}</p>), '<p>&lt;script&gt;alert("&amp;")&lt;/script&gt;</p>');
		check("an attribute", Static.render(<a title={evil} href="?a=1&b=2"/>), '<a title="<script>alert(&quot;&amp;&quot;)</script>" href="?a=1&amp;b=2"></a>');
		check("static text with entities", Static.render(<p>&lt;b&gt; &amp; "q"</p>), '<p>&lt;b&gt; &amp; "q"</p>');
		var code = 'if (a < b && c) x = "</script>";';
		check("a script, raw", Static.render(<script>{code}</script>), '<script>if (a < b && c) x = "<\\/script>";</script>');
		check("a style, raw", Static.render(<style>{"a > b { color: red }"}</style>), "<style>a > b { color: red }</style>");
		check("a textarea, escaped, one text", Static.render(<textarea>{"a<b"}{""}{"c"}</textarea>), "<textarea>a&lt;bc</textarea>");
		check("a title", Static.render(<title>{"A & B"}</title>), "<title>A &amp; B</title>");
		check("a pre's first newline kept", Static.render(<pre>{"\nx"}</pre>), "<pre>\n\nx</pre>");
		check("a document", Static.document(<html lang="en"><head><meta charset="utf-8"/></head><body/></html>),
			'<!doctype html>\n<html lang="en"><head><meta charset="utf-8"></head><body></body></html>');
	}

	static function attributes() {
		check("void elements", Static.render(<div><br/><img src="a.png" alt=""/><input type="text"/><hr/></div>),
			'<div><br><img src="a.png" alt=""><input type="text"><hr></div>');
		check("boolean attributes", Static.render(<input disabled checked={true} required={false} readonly={null}/>), "<input disabled checked>");
		check("class and for", Static.render(<label className="x" htmlFor="i">L</label>), '<label class="x" for="i">L</label>');
		check("false removes, data and aria keep it", Static.render(<div title={false} data-x={false} aria-hidden={true} tabindex={0}/>),
			'<div data-x="false" aria-hidden="true" tabindex="0"></div>');
		check("value: an attribute, a textarea's content", Static.render(<form><input value={"a\"b"}/><textarea value="x<y"/></form>),
			'<form><input value="a&quot;b"><textarea>x&lt;y</textarea></form>');
		check("innerHTML raw, textContent escaped", Static.render(<div><p innerHTML="<b>raw</b>"/><p textContent="<b>"/></div>),
			"<div><p><b>raw</b></p><p>&lt;b&gt;</p></div>");
		check("a style string", Static.render(<p style="color: red"/>), '<p style="color: red"></p>');
		// (one property each: an object's order is the target's)
		check("a style object: px", Static.render(<p style={{fontSize: 12}}/>), '<p style="font-size:12px"></p>');
		check("a style object: unitless", Static.render(<p style={{opacity: 0.5}}/>), '<p style="opacity:0.5"></p>');
		check("a style object: 0, a string", Static.render(<p style={{marginTop: 0}}/>) + Static.render(<p style={{color: "red"}}/>),
			'<p style="margin-top:0"></p><p style="color:red"></p>');
		check("a style object: null left out", Static.render(<p style={{display: null}}/>), "<p></p>");
		check("a style object: prefixes, custom properties", Static.render(<p style={{WebkitUserSelect: "none"}}/>)
			+ Static.render(<p style={{"--gap": 4}}/>), '<p style="-webkit-user-select:none"></p><p style="--gap:4"></p>');
		check("listeners dropped", Static.render(<button onClick={() -> trace("x")}>B</button>), "<button>B</button>");
		check("SVG", Static.render(<svg viewBox="0 0 10 10"><svg:a href="#"><path d="M0 0"/></svg:a></svg>),
			'<svg viewBox="0 0 10 10"><a href="#"><path d="M0 0"></path></a></svg>');
		var on = signal(true);
		check("a reactive attribute, once", Static.render(<details open={on}/>), "<details open></details>");
	}

	static function markers() {
		var name = signal("Ann");
		check("adjacent texts separated", Static.render(<p>Hi {name}{"!"}<b/>{"x"}</p>), "<p>Hi Ann!<b></b>x</p>");
		check("reactive text joins a run", Static.render(<p>{"a"}{() -> "b"}</p>), "<p>ab</p>");
		check("a text then a region", Static.render(<p>{"a"}{() -> <i/>}</p>), "<p>a<!--[--><i></i><!--]--></p>");
		var parts:Array<Any> = ["a", <i/>, "b"];
		check("texts of an array", Static.render(<p>{"x"}{parts}</p>), "<p>x<!---->a<i></i>b</p>");
		var empty = signal("");
		check("an empty text", Static.render(<p>{empty}<b/></p>), "<p><!--#--><b></b></p>");
		check("a region", Static.render(<div>{() -> <b>{name}</b>}</div>), "<div><!--[--><b>Ann</b><!--]--></div>");
		var items = signal(["a", "b"]);
		check("For", Static.render(<ul><For each={items}>{i -> <li>{i}</li>}</For></ul>), "<ul><!--[--><li>a</li><li>b</li><!--]--></ul>");
		check("For by index", Static.render(<ul><For each={items} keyed={false}>{i -> <li>{i}</li>}</For></ul>),
			"<ul><!--[--><li>a</li><li>b</li><!--]--></ul>");
		check("Show", Static.render(<div><Show when={true} fallback="no">{() -> "yes"}</Show></div>), "<div><!--[-->yes<!--]--></div>");
		check("regions nested", Static.render(<div>{() -> [() -> <i/>, () -> <b/>]}</div>),
			"<div><!--[--><!--[--><i></i><!--]--><!--[--><b></b><!--]--><!--]--></div>");
		check("Show's fallback", Static.render(<div><Show when={false} fallback="no">yes</Show></div>), "<div><!--[-->no<!--]--></div>");
		var s = signal(1), runs = 0;
		Static.render(<p>{() -> {
			runs++;
			s();
		}}</p>);
		var before = runs;
		s(2);
		flush();
		check("effects stop with the page", "" + runs, "" + before);
		check("Errored", Static.render(<div><Errored fallback={(e, _) -> "failed: " + e}>{() -> throw "oops"}</Errored></div>),
			"<div><!--[-->failed: oops<!--]--></div>");
	}

	static function counter(props:{label:String}):View
		return <button>{props.label}</button>;

	static final Counter = Island.define("test-counter", counter, {script: "islands.js", load: Idle});

	static function islands() {
		check("an island: its name, props, bundle, load", Static.render(<main><Counter label={'a "b" & <c>'}/></main>),
			'<main><hxmc-island data-island="test-counter" data-props="{&quot;label&quot;:&quot;a \\&quot;b\\&quot; &amp; <c>&quot;}" data-load="idle" data-src="islands.js">'
			+ '<button>a "b" &amp; &lt;c&gt;</button></hxmc-island></main>');
		check("a WebAssembly island", Static.render(<Island.Wasm src="cube.wasm" id="cube" imports={["os/imports.mjs"]} width={256} height={192}>A cube</Island.Wasm>),
			'<hxmc-island id="cube" data-wasm="cube.wasm" data-runner="os/browser.mjs" data-imports="[&quot;os/imports.mjs&quot;]" data-load="visible">'
			+ '<canvas width="256" height="192"></canvas>A cube</hxmc-island>');
		var surface = Static.render(<WebTags.Surface src="todo.wasm" fonts={["f.ttf"]} className="app">Todo</WebTags.Surface>);
		check("a <Surface>: a ui program's island, its canvas the page's styles' size", surface, '<hxmc-island class="app" data-wasm="todo.wasm" data-runner="os/browser.mjs" '
			+ 'data-imports="[&quot;os/imports.mjs&quot;,&quot;gfx/imports.mjs&quot;,&quot;text/imports.mjs&quot;,&quot;ui/imports.mjs&quot;]" '
			+ 'data-fonts="[&quot;f.ttf&quot;]" data-load="load"><canvas style="display:block;width:100%;height:100%"></canvas>Todo</hxmc-island>');
	}
}
