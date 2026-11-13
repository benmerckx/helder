package helder.story;

import helder.story.Story;
import helder.test.Test;
import helder.ui.Clock;
import helder.ui.ScreenContext;
import helder.ui.Ui;
import helder.view.View;
import helder.view.graph.Graph;

// a story's clock (Stories.settle): a story that plays (Controls.play) run
// frame by frame on its own clock to its moment, a story that never settles
// an error naming it, each story in a context of its own, let go after
function tests() {
	test("a playing story: its frames 1/60 s apart on its clock, to the moment", () -> {
		var m = Stories.mount(rolling("Ball/rolling", 1.5), 390, 844, new StoryText());
		equals(m.controls.settled(), true);
		// (the moment's frame: 90 of them, its clock 1.5 s on, the step's writes laid out)
		approx(m.context.now - ScreenContext.main.now, 1.5);
		var t = Stories.tree(rolling("Ball/rolling", 1.5));
		assert(t.indexOf('"90 frames, 1.5 s"') > 0, t);
		assert(t.indexOf("TextNode#ball 90,") > 0, t);
	});

	test("settle paints each frame but the moment's (the renderer's own)", () -> {
		var context = new ScreenContext("paint");
		context.run(() -> {
			var ui = new Ui(new StoryText(), 390, 844);
			var c = new Controls();
			var steps = 0, painted = 0;
			Clock.add(_ -> {
				steps++;
				true;
			});
			c.play(0.5);
			Stories.settle(ui, c, "paint", () -> painted++);
			equals(steps, 30);
			equals(painted, 29);
		});
	});

	test("a story that never settles: an error naming it", () -> {
		var s = new Story("Ball/stuck", c -> {
			c.settled(false);
			View.view(<view/>);
		});
		var e:String = Std.string(throws(() -> Stories.tree(s)));
		assert(e.indexOf('"Ball/stuck" never settled') >= 0, e);
		assert(e.indexOf("120 s of its clock") >= 0, e);
	});

	test("each story on a clock of its own: what one leaves running is not the next one's", () -> {
		var left = 0;
		var forever = new Story("Clock/forever", c -> {
			Clock.add(_ -> {
				left++;
				true;
			});
			c.play(0.25);
			View.view(<view/>);
		});
		Stories.tree(forever);
		equals(left, 15);
		// (a settled story's transitions finished in its own context: the other's step not run)
		Stories.tree(new Story("Clock/still", c -> View.view(<view/>)));
		equals(left, 15);
	});

	test("a story let go once its tree is read (Controls.onDispose)", () -> {
		var gone = 0;
		Stories.tree(new Story("Clock/gone", c -> {
			c.onDispose(() -> gone++);
			View.view(<view/>);
		}));
		equals(gone, 1);
	});
}

// a ball rolling a point a frame, played for seconds
private function rolling(name:String, seconds:Float):Story
	return new Story(name, c -> {
		var frames = Graph.signal(0), start = Clock.now, at = Graph.signal(0.0);
		Clock.add(t -> {
			frames(frames.peek() + 1);
			at(t - start);
			true;
		});
		c.play(seconds);
		View.view(<view>
			<text tag="ball" position="absolute" left={frames()} top={10}>o</text>
			<text tag="time" margin-top={40}>{frames() + " frames, " + at() + " s"}</text>
		</view>);
	});
