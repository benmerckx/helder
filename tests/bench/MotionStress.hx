import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

// helder.ui.motion's budget: 1,000 boxes in a wrapping row under motion,
// their order reversed every 0.25 s from 0.5 s on, so that every box is
// always moving (retargeted mid-flight, its edges from where they are drawn).
// Measured headless (the motion-bench lane: helder run --headless --stats):
// each frame's ms and GC bytes once the boxes move, against an idle frame's.
// Its argument: how many boxes (1000).
class MotionStress implements Markup {
	static final order = signal(new Array<Int>());

	static function main() {
		var n = Std.parseInt(Sys.args()[0] ?? "") ?? 1000;
		order([for (i in 0...n) i]);
		var next = 0.5, start = -1.0;
		Clock.add(t -> {
			if (start < 0) start = t;
			if (t - start >= next) {
				next += 0.25;
				var o = order().copy();
				o.reverse();
				order(o);
			}
			return true;
		});
		UiWindow.run(<Surface title="MotionStress" width={1000} height={640}>
			<view grow={1} motion="default" direction="row" wrap padding={8} gap={4} align-content="start" background="#f4f4f5">
				<For each={order}>{(i:Read<Int>) -> <view width={20} height={14} radius={3}
					background={["#f97316", "#22c55e", "#3b82f6", "#a855f7"][i() % 4]}/>}</For>
			</view>
		</Surface>);
	}
}
