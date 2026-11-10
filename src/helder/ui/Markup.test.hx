package helder.ui;

import helder.test.Test;
import helder.view.Render;
import helder.view.graph.Graph;
import helder.view.graph.Signal;

// ui's markup attributes at run time: a transform from a string built
// then, pointer-events inherited by what a transform moves, onResize told
// a node's laid-out size, line-height in pixels or as a multiple, a
// wheel's modifiers
function tests() {
	describe("Markup", () -> {
		test("a transform bound to a runtime string", () -> {
			var ui = new Ui(null, 200, 200);
			var x = Graph.signal(10.0);
			var dispose = Render.render(Fixture.moved(x), ui.root);
			ui.update();
			notEquals(ui.root.find("box").style.transform, null);
			equals(tag(ui.root.hitTest(15, 5)), "box");
			x(100.0);
			Graph.flush();
			ui.update();
			equals(tag(ui.root.hitTest(15, 5)), "root");
			equals(tag(ui.root.hitTest(105, 5)), "box");
			equals(tag(ui.root.hitTest(105, 35)), "left");
			dispose();
		});
		test("pointer-events none: a moved child lets the press through", () -> {
			var ui = new Ui(null, 200, 200);
			var dispose = Render.render(Fixture.overlay(), ui.root);
			ui.update();
			equals(tag(ui.root.hitTest(10, 10)), "button");
			equals(tag(ui.root.hitTest(150, 150)), "view");
			equals(ui.root.find("chip").hittable(), false);
			dispose();
		});
		test("autofocus: focused when it comes into the window", () -> {
			var ui = new Ui(null, 200, 200);
			var open = Graph.signal(false);
			var dispose = Render.render(Fixture.dialog(open), ui.root);
			ui.update();
			equals(ui.focus == null, true);
			open(true);
			Graph.flush();
			equals(tag(ui.focus), "ok");
			dispose();
		});
		test("onResize: the size after each layout that changed it", () -> {
			var ui = new Ui(null, 200, 200);
			var w = Graph.signal(50.0), sizes = [];
			var dispose = Render.render(Fixture.sized(w, sizes), ui.root);
			ui.update();
			equals(sizes, ["50x20"]);
			ui.update();
			equals(sizes, ["50x20"]);
			w(80.0);
			ui.update();
			equals(sizes, ["50x20", "80x20"]);
			dispose();
		});
		test("a wheel's own modifiers (a pinch: Control), else the keys'", () -> {
			var ui = new Ui(null, 200, 200), seen = [];
			var dispose = Render.render(Fixture.wheeled(seen), ui.root);
			ui.update();
			ui.wheel(10, 10, 0, 5, false, Key.MOD_CONTROL);
			ui.wheel(10, 10, 0, 5);
			equals(seen, [Key.MOD_CONTROL, 0]);
			dispose();
		});
		test("line-height in pixels or as a multiple", () -> {
			var ui = new Ui(null, 200, 200);
			var dispose = Render.render(Fixture.leading(), ui.root);
			equals(ui.root.find("px").style.lineHeightPx, 22.0);
			equals(ui.root.find("px").style.lineHeight, null);
			equals(ui.root.find("times").style.lineHeight, 1.5);
			equals(ui.root.find("times").style.lineHeightPx, null);
			dispose();
		});
	});
}

function tag(n:Null<Node>):Null<String>
	return n == null ? null : n.tag;

private class Fixture implements helder.view.Markup {
	public static function moved(x:Signal<Float>)
		return <view>
			<view tag="box" position="absolute" left={0} top={0} width={20} height={20} transform={'translate(${x()}px, 0px)'}/>
			<view tag="left" position="absolute" left={x()} top={30} width={20} height={20}/>
		</view>;

	public static function sized(w:Signal<Float>, sizes:Array<String>)
		return <view>
			<view width={w()} height={20} onResize={e -> sizes.push(e.target.width + "x" + e.target.height)}/>
		</view>;

	public static function wheeled(seen:Array<Int>)
		return <view width={200} height={200} onWheel={e -> seen.push(e.mods)}/>;

	public static function leading()
		return <view>
			<text tag="px" line-height="22px">a</text>
			<text tag="times" line-height={1.5}>b</text>
		</view>;

	public static function dialog(open:Signal<Bool>)
		return <view>
			{open() ? <view tag="dialog"><view tag="cancel" focusable/><view tag="ok" focusable autofocus/></view> : null}
		</view>;

	public static function overlay()
		return <view width={200} height={200}>
			<view tag="button" position="absolute" left={0} top={0} width={40} height={40}/>
			<view position="absolute" left={0} top={0} width={200} height={200} pointer-events="none">
				<view tag="chip" position="absolute" left={0} top={0} width={40} height={40} transform="translate(140px, 140px)"/>
			</view>
		</view>;
}
