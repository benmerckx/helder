package helder.ui.view;

import helder.markup.Syntax;
import helder.ui.view.Interpreter.Interpreted;
import helder.test.Test;
import helder.view.Render;

// The interpreter against the compiler: each literal's text interpreted and
// the same literal compiled, the two trees equal (tags, texts, boxes after a
// layout, the styles a design sets); what a design cannot run marked in
// place, the rest drawn
function tests() {
	describe("Interpreter", () -> {
		for (c in Fixture.cases())
			test(c.name, () -> equals(dump(interpreted(c.text)), dump(compiled(c.view))));
		test("a hole of code, an unknown element, a component: marked, the rest drawn", () -> {
			var i = interpret('<view padding={8}><text>{items.length} left</text><note>hi</note><Card/><text>ok</text></view>');
			var d = dump(i.ui.root.children[0]);
			equals(d.indexOf("text(ok)") > 0, true);
			equals(d.indexOf("text({items.length} left)") > 0, true);
			equals([for (e in i.interpreted.errors) e.at], [18, 50, 65]);
		});
		test("each element's offset", () -> {
			var i = interpret('<view><text>a</text></view>');
			var root = i.ui.root.children[0];
			equals(i.interpreted.sources.get(root), 0);
			equals(i.interpreted.sources.get(root.children[0]), 6);
		});
	});
}

function interpret(text:String):{ui:Ui, interpreted:Interpreted} {
	var ui = new Ui(new helder.story.StoryText(), 400, 400);
	var i = new Interpreted(new Parser(text, (m, _, _) -> throw m).document());
	Render.render(i, ui.root);
	ui.update();
	return {ui: ui, interpreted: i};
}

function interpreted(text:String):Node
	return interpret(text).ui.root;

function compiled(v:helder.view.View):Node {
	var ui = new Ui(new helder.story.StoryText(), 400, 400);
	Render.render(v, ui.root);
	ui.update();
	return ui.root;
}

function dump(n:Node):String {
	var s = n.style;
	var text = Std.isOfType(n, TextNode) ? "(" + (cast n : TextNode).text + ")" : "";
	var self = n.tag + text + ' ${n.x},${n.y} ${n.width}x${n.height} ${hex(s.background)} ${s.color == null ? "-" : hex(s.color)} ${s.fontSize} ${s.fontWeight} ${s.radius}';
	return self + (n.children.length == 0 ? "" : " [" + [for (c in n.children) dump(c)].join(", ") + "]");
}

function hex(c:Color):String
	return StringTools.hex((c : Int), 8);

private class Fixture implements helder.view.Markup {
	public static function cases():Array<{name:String, text:String, view:helder.view.View}>
		return [
			{
				name: "a view's layout and fill",
				text: '<view width={120} height={80} padding="8 12" background="#3b82f6" radius={6}/>',
				view: <view width={120} height={80} padding="8 12" background="#3b82f6" radius={6}/>
			},
			{
				name: "a row of views, a gap",
				text: '<view direction="row" gap={10} padding={4}><view width={20} height={20} background="#ef4444"/><view grow={1} height={30}/></view>',
				view: <view direction="row" gap={10} padding={4}><view width={20} height={20} background="#ef4444"/><view grow={1} height={30}/></view>
			},
			{
				name: "a text's style and text, entities, whitespace",
				text: '<text font-size={28} font-weight={700} color="#3b82f6">
					todos &amp; more
				</text>',
				view: <text font-size={28} font-weight={700} color="#3b82f6">
					todos &amp; more
				</text>
			},
			{
				name: "literal holes as text",
				text: '<text>{3} items {"left"}</text>',
				view: <text>{3} items {"left"}</text>
			},
			{
				name: "text beside elements, spans",
				text: '<view padding={2}>before<text>a <b>bold</b> word</text>after</view>',
				view: <view padding={2}>before<text>a <b>bold</b> word</text>after</view>
			},
			{
				name: "a fragment, neutral elements, flags",
				text: '<><view:button focusable padding={6}><text>Go</text></view:button><scroll height={40}/></>',
				view: <><view:button focusable padding={6}><text>Go</text></view:button><scroll height={40}/></>
			}
		];
}
