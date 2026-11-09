package helder.ui;

import helder.os.TitleBar.TitleHit;
import helder.test.Test;
import helder.view.Render;
import helder.ui.widgets.WindowButtons.WindowControls;

// An inset title bar in ui: env(titlebar-area-*) resolved and bound as the
// safe area's (the fallback without one), drag-region and the window's
// buttons answering a press (Ui.titleHit: what Windows' WM_NCHITTEST, a
// Mac's drag and Linux's moves ask), WindowControls drawing Windows' and
// Linux's buttons, macOS's box placed (natively and as wasm32-wasi)
function tests() {
	describe("TitlebarArea", () -> {
		afterEach(() -> SafeArea.setTitlebar(null));
		test("env(titlebar-area-*) resolved, the fallback without one", () -> {
			var t = new TitlebarArea(78, 0, 1102, 32), e = Edges.ZERO;
			equals(SafeArea.resolve("env(titlebar-area-x) env(titlebar-area-y) env(titlebar-area-width) env(titlebar-area-height)", e, t), "78px 0px 1102px 32px");
			equals(SafeArea.resolve("calc(env(titlebar-area-x) + 8px)", e, t), "86px");
			equals(SafeArea.resolve("env(titlebar-area-height, 40px)", e), "40px");
			equals(SafeArea.resolve("env(titlebar-area-x)", e), "0px");
		});
		test("markup's env(titlebar-area-*) follows the window's", () -> {
			var ui = new Ui(null, 800, 600);
			var dispose = Render.render(Fixture.bar(), ui.root);
			ui.update();
			var bar = ui.root.find("bar");
			equals([bar.style.paddingLeft, bar.rect().height], [12.0, 40.0]);
			SafeArea.setTitlebar(new TitlebarArea(78, 0, 722, 28));
			ui.update();
			equals([bar.style.paddingLeft, bar.rect().height], [78.0, 28.0]);
			dispose();
		});
		test("a drag region's press, a button in it the content's, the window's buttons theirs", () -> {
			var ui = new Ui(null, 800, 600);
			ui.window = new Host("windows");
			var dispose = Render.render(Fixture.bar(), ui.root);
			ui.update();
			ui.update();
			equals(ui.titleHit(300, 10), Drag);
			equals(ui.titleHit(40, 20), Content);
			equals(ui.titleHit(300, 300), Content);
			// (Windows': 46 wide at the right, close last)
			equals(ui.titleHit(800 - 23, 10), Close);
			equals(ui.titleHit(800 - 69, 10), Maximize);
			equals(ui.titleHit(800 - 115, 10), Minimize);
			dispose();
		});
		test("macOS's: a box of the system's buttons' size, placed after the layout", () -> {
			var ui = new Ui(null, 800, 600);
			var host = new Host("system");
			ui.window = host;
			var dispose = Render.render(Fixture.bar(), ui.root);
			ui.update();
			ui.update();
			var c = ui.root.find("window-controls");
			equals([c.width, c.height], [54.0, 16.0]);
			equals(ui.controlsAt, c);
			dispose();
			equals(ui.controlsAt, null);
		});
	});
}

private class Host implements WindowHost {
	final kind:String;

	public function new(kind:String)
		this.kind = kind;

	public function controls():String
		return kind;

	public function systemControls():Null<Bounds> {
		var b = new Bounds();
		b.width = 54;
		b.height = 16;
		return b;
	}

	public function placeControls(x:Float, y:Float) {}

	public function minimize() {}

	public function maximized():Bool
		return false;

	public function maximize(on:Bool) {}

	public function close() {}
}

private class Fixture implements helder.view.Markup {
	public static function bar()
		return <view tag="page">
			<view tag="bar" direction="row" align-items="center" drag-region padding-left="env(titlebar-area-x, 12px)" height="env(titlebar-area-height, 40px)">
				<view tag="button" width={60} height={20} onClick={_ -> {}}/>
				<view grow={1}/>
				<WindowControls/>
			</view>
		</view>;
}
