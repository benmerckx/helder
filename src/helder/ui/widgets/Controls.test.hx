package helder.ui.widgets;

import helder.test.Test;
import helder.ui.Key;
import helder.ui.Ui;
import helder.view.Render;
import helder.view.graph.Graph;
import helder.view.graph.Signal;

// Controls: a slider set by a press, a drag and the keys, in steps and
// within its range; a segmented choice by a press and the arrows
function tests() {
	describe("Controls", () -> {
		test("a slider: pressed, dragged, stepped", () -> {
			var ui = new Ui(new helder.story.StoryText(), 200, 100);
			var v = Graph.signal(10.0);
			var dispose = Render.render(Fixture.slider(v), ui.root);
			ui.update();
			var s = ui.root.find("slider");
			ui.pointerDown(s.absX + s.width * 0.75, s.absY + 5, 1);
			Graph.flush();
			equals(v.peek(), 75.0);
			ui.pointerMove(s.absX + s.width * 2, s.absY + 5);
			ui.pointerUp(s.absX + s.width * 2, s.absY + 5, 1);
			Graph.flush();
			equals(v.peek(), 100.0);
			ui.setFocus(s);
			ui.keyDown(Key.LEFT, 0);
			Graph.flush();
			equals(v.peek(), 95.0);
			ui.keyDown(Key.LEFT, Key.MOD_SHIFT);
			Graph.flush();
			equals(v.peek(), 45.0);
			ui.keyDown(Key.HOME, 0);
			Graph.flush();
			equals(v.peek(), 0.0);
			dispose();
		});
		test("a segmented choice: pressed, then the arrows", () -> {
			var ui = new Ui(new helder.story.StoryText(), 300, 100);
			var v = Graph.signal("b");
			var dispose = Render.render(Fixture.segmented(v), ui.root);
			ui.update();
			var c = ui.root.find("pick-c");
			ui.pointerDown(c.absX + 2, c.absY + 2, 1);
			ui.pointerUp(c.absX + 2, c.absY + 2, 1);
			Graph.flush();
			equals(v.peek(), "c");
			ui.setFocus(c);
			ui.keyDown(Key.RIGHT, 0);
			Graph.flush();
			equals(v.peek(), "a");
			dispose();
		});
	});
}

private class Fixture implements helder.view.Markup {
	public static function slider(v:Signal<Float>)
		return <view width={200}>
			<Controls.Slider tag="slider" label="Size" value={v} min={0} max={100} step={5} onChange={x -> v(x)}/>
		</view>;

	public static function segmented(v:Signal<String>)
		return <view direction="row">
			<Controls.Segmented tag="pick" label="Pick" value={v} onChange={x -> v(x)} options={[
				{value: "a", label: "A"},
				{value: "b", label: "B"},
				{value: "c", label: "C"}
			]}/>
		</view>;
}
