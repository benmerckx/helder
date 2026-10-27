import helder.view.*;
import helder.view.Flow.*;
import helder.view.Reactive.*;
import helder.web.*;
import js.Browser.document;
import js.html.*;

// The DOM renderer in a browser (npm test -- web: tests/web/web.mjs
// runs it in Chromium): elements, texts and markers made, properties and
// attributes, the style, listeners, SVG's namespace, keyed lists moved
// rather than made, a region's content replaced, dispose; then hydration
// of markup written as the static renderer writes it (claimed, not made;
// empty texts; nested regions; the markup the static renderer writes, as
// a second renderer), a mismatch rendered again. Its result in
// window.domTest: {checks, failed: [what]}.
class DomTest implements Markup {
	static var checks = 0;
	static final failed:Array<String> = [];

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) failed.push(what + (detail == null ? "" : ": " + detail));
	}

	static function mount(content:Any):{el:Element, dispose:Void->Void} {
		var el = document.createDivElement();
		document.body.appendChild(el);
		var dispose = Render.render(content, el);
		return {el: el, dispose: dispose};
	}

	static function main() {
		rendering();
		hydration();
		js.Syntax.code("window.domTest = {0}", {checks: checks, failed: failed});
	}

	static function rendering() {
		var m = mount(<div id="a" className="x" data-n={1} hidden={false} title={null} aria-busy={true}>text</div>);
		check("attributes", m.el.innerHTML == '<div id="a" class="x" data-n="1" aria-busy="true">text</div>', m.el.innerHTML);
		var on = signal(false), v = signal("one");
		m = mount(<form><input class="c" type="checkbox" checked={on}/><input class="t" value={v}/><textarea value={v}/><button disabled={on}/></form>);
		var box:InputElement = cast m.el.querySelector(".c"), text:InputElement = cast m.el.querySelector(".t");
		var area:TextAreaElement = cast m.el.querySelector("textarea"), button:ButtonElement = cast m.el.querySelector("button");
		check("checked: a property", !box.checked && !box.hasAttribute("checked"));
		on.value = true;
		check("checked set", box.checked && button.disabled && button.getAttribute("disabled") == "");
		check("value: a property", text.value == "one" && area.value == "one" && !text.hasAttribute("value"));
		text.value = "typed";
		v.value = "two";
		check("value set again", text.value == "two" && area.value == "two");
		on.value = false;
		check("a boolean attribute removed", !button.hasAttribute("disabled"));
		var st = signal(true);
		m = mount(<p style={() -> st.value ? ({color: "red", fontSize: 12} : Dynamic) : "margin: 0px"}/>);
		var p:Element = cast m.el.firstChild;
		check("a style object", (cast p : DOMElement).style.color == "red" && (cast p : DOMElement).style.fontSize == "12px", p.getAttribute("style"));
		st.value = false;
		check("a style string, the object's properties gone", (cast p : DOMElement).style.color == "" && (cast p : DOMElement).style.margin == "0px",
			p.getAttribute("style"));
		var clicks = 0, custom = 0;
		m = mount(<button onClick={() -> clicks++} onDoubleClick={() -> clicks += 10} on:my-event={(e:Event) -> custom++}>b</button>);
		var b:Element = cast m.el.firstChild;
		b.click();
		b.dispatchEvent(new MouseEvent("dblclick"));
		b.dispatchEvent(new CustomEvent("my-event"));
		check("listeners", clicks == 11 && custom == 1, '$clicks $custom');
		m = mount(<svg viewBox="0 0 4 4"><g><circle r="1"/></g><foreignObject><div/></foreignObject><svg:a href="#"/></svg>);
		var svg = m.el.firstChild, circle:Element = cast m.el.querySelector("circle");
		check("SVG's namespace", (cast svg : Element).namespaceURI == Html.SVG_NS && circle.namespaceURI == Html.SVG_NS
			&& (cast m.el.querySelector("svg > a") : Element).namespaceURI == Html.SVG_NS && circle.getAttribute("r") == "1");
		check("HTML inside foreignObject", (cast m.el.querySelector("foreignObject div") : Element).namespaceURI == "http://www.w3.org/1999/xhtml");
		// keyed rows moved, not made
		var items = signal(["a", "b", "c"]);
		m = mount(<ul><For each={items} render={(i:String) -> <li>{i}</li>}/></ul>);
		var lis = [for (n in m.el.querySelectorAll("li")) n];
		items.value = ["c", "a", "b", "d"];
		var after = [for (n in m.el.querySelectorAll("li")) n];
		check("For: rows moved", after.length == 4 && after[0] == lis[2] && after[1] == lis[0] && after[2] == lis[1],
			m.el.innerHTML);
		check("For: markup", m.el.innerHTML == "<ul><li>c</li><li>a</li><li>b</li><li>d</li><!--for--></ul>", m.el.innerHTML);
		var show = signal(true);
		m = mount(<div><Show when={show} fallback={<i>no</i>}><b>yes</b></Show></div>);
		show.value = false;
		check("Show: a region replaced", m.el.innerHTML == "<div><i>no</i><!--anchor--></div>", m.el.innerHTML);
		m.dispose();
		check("dispose removes it", m.el.innerHTML == "", m.el.innerHTML);
	}

	// content written by the static renderer (or as html), hydrated; the
	// nodes before (but the starts of pairs, which hydration removes)
	static function hydrate(content:Any, ?html:String):{el:Element, before:Array<Node>, dispose:Void->Void} {
		var el = document.createDivElement();
		el.innerHTML = html == null ? Static.render(content) : html;
		document.body.appendChild(el);
		var before = nodes(el).filter(n -> n.nodeType != Node.COMMENT_NODE || n.nodeValue != "[");
		var dispose = DomRenderer.hydrate(content, el);
		return {el: el, before: before, dispose: dispose};
	}

	static function nodes(el:Node):Array<Node> {
		var out = [];
		function walk(n:Node) {
			for (c in n.childNodes) {
				out.push(c);
				walk(c);
			}
		}
		walk(el);
		return out;
	}

	static function same(a:Array<Node>, b:Array<Node>):Bool {
		if (a.length != b.length) return false;
		for (i in 0...a.length)
			if (a[i] != b[i]) return false;
		return true;
	}

	static function hydration() {
		var count = signal(1), clicks = 0;
		var items = signal(["x", "y"]);
		var h = hydrate(<><p class="c">n: {count}{"!"}</p><ul><For each={items} render={(i:String) -> <li>{i}</li>}/></ul><button onClick={() -> clicks++}>b</button></>);
		check("hydration: every node kept", same(h.before, nodes(h.el)), h.el.innerHTML);
		count.value = 2;
		(cast h.el.querySelector("button") : Element).click();
		check("hydration: reactive afterwards", h.el.querySelector("p").textContent == "n: 2!" && clicks == 1, h.el.innerHTML);
		var li = h.el.querySelectorAll("li");
		items.value = ["y", "x", "z"];
		var after = h.el.querySelectorAll("li");
		check("hydration: a list's rows kept and moved", after.length == 3 && after[0] == li[1] && after[1] == li[0], h.el.innerHTML);
		// an empty text (<!--#-->), nested regions, a region's content replaced later
		var name = signal(""), on = signal(true);
		var view = <p>{name}{() -> on.value ? [() -> <b>on</b>] : null}</p>;
		check("the static renderer's markers", Static.render(view) == "<p><!--#--><!--[--><!--[--><b>on</b><!--]--><!--]--></p>", Static.render(view));
		h = hydrate(view);
		var b = h.el.querySelector("b");
		check("hydration: nested regions kept", b != null && h.before.indexOf(b) >= 0 && h.el.innerHTML == "<p><b>on</b><!--]--><!--]--></p>",
			h.el.innerHTML);
		name.value = "N";
		on.value = false;
		check("hydration: an empty text, a region replaced", h.el.innerHTML == "<p>N<!--]--></p>", h.el.innerHTML);
		h.dispose();
		check("hydration: dispose", h.el.innerHTML == "", h.el.innerHTML);
		// a mismatch: rendered again
		h = hydrate(<div><b>client</b></div>, "<div><i>server</i></div>");
		check("a mismatch rendered again", h.el.innerHTML == "<div><b>client</b></div>" && h.el.firstChild != h.before[0], h.el.innerHTML);
		h = hydrate(<div>a</div>, "<div>a</div><div>left over</div>");
		check("nodes left over: rendered again", h.el.innerHTML == "<div>a</div>", h.el.innerHTML);
	}
}
