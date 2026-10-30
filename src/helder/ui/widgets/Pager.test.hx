package helder.ui.widgets;

import helder.test.Test;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;

// Pager: where a swipe let go settles (a fifth of the width or a fling,
// never past the ends), and its pages laid out: the shown one in the flow
// (its height the pager's), the others beside it
function tests() {
	describe("Pager", () -> {
		test("a swipe settles on the next, the previous or the same page", () -> {
			equals(Pager.settle(0, 3, -120, 0, 400), 1);
			equals(Pager.settle(0, 3, -40, 0, 400), 0);
			equals(Pager.settle(0, 3, -30, -900, 400), 1);
			equals(Pager.settle(2, 3, -200, -900, 400), 2);
			equals(Pager.settle(1, 3, 100, 0, 400), 0);
			equals(Pager.settle(0, 3, 300, 900, 400), 0);
		});
		test("the shown page sets the pager's height", () -> {
			var ui = new Ui(null, 300, 400);
			var page = Graph.signal(0);
			var dispose = Graph.root(dispose -> {
				var pager = new Pager(page, 2, p -> page(p));
				var d = Render.render(Fixture.pages(pager), ui.root);
				() -> {
					d();
					dispose();
				};
			});
			ui.update();
			equals(ui.root.find("pager").height, 50.0);
			page(1);
			Graph.flush();
			ui.update();
			equals(ui.root.find("pager").height, 120.0);
			dispose();
		});
	});
}

private class Fixture implements helder.view.Markup {
	public static function pages(pager:Pager)
		return <view><Pager.Pages pager={pager} slides={[<view height={50}/>, <view height={120}/>]}/></view>;
}
