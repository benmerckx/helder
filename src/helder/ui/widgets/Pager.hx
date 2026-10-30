package helder.ui.widgets;

import helder.ui.Node;
import helder.ui.Position;
import helder.ui.gesture.Gesture;
import helder.ui.view.Motion;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// Pages side by side, one shown, swiped between: a horizontal drag moves
// them with the finger (resisting past the first and the last), let go a
// fifth of the way or fast enough it snaps to the next or the previous
// (onPage), else back; a change of page (a tab pressed) slides to it. Its
// position (in pages, fractional while dragged or sliding) is for a tab
// bar to follow. The shown page sets the pager's height (the others laid
// beside it, cut to it). A vertical drag is left to what is around it.
//   var pager = new Pager(page, 3, p -> page(p));   // (in a component)
//   <Pager.Pages pager={pager} slides={[<Overview/>, <Build/>, <Recruit/>]}/>
//   <view left={(pager.position() * 100 / 3) + "%"} .../>   // a tab bar's pill
class Pager implements helder.view.Markup {
	public final page:Read<Int>;
	public final count:Int;
	// where the pages are: the shown one's index, between two while moving
	public final position:Signal<Float>;
	final onPage:Int->Void;
	final drag = signal(0.0);
	var root:Null<Node> = null;

	// (made in a component: its spring stops with it)
	public function new(page:Read<Int>, count:Int, onPage:Int->Void) {
		this.page = page;
		this.count = count;
		this.onPage = onPage;
		position = Motion.spring(() -> page() - drag() / width(), 420, 40);
	}

	function width():Float
		return root == null || root.width <= 0 ? 1 : root.width;

	// the page a drag let go goes to: the next or the previous one past a
	// fifth of the width or flung (points a second), else the same
	public static function settle(page:Int, count:Int, travel:Float, speed:Float, width:Float):Int {
		if ((travel < -width * 0.2 || speed < -500) && travel < 0 && page < count - 1) return page + 1;
		if ((travel > width * 0.2 || speed > 500) && travel > 0 && page > 0) return page - 1;
		return page;
	}

	function pan(g:Gesture) {
		switch g.state {
			case Began | Changed:
				var p = page.peek(), t = g.tx;
				// (past the ends: a third of the way)
				if ((p == 0 && t > 0) || (p == count - 1 && t < 0)) t *= 0.3;
				drag(t);
			case Ended:
				var next = settle(page.peek(), count, g.tx, g.vx, width());
				drag(0);
				if (next != page.peek()) onPage(next);
			case Cancelled:
				drag(0);
			default:
		}
	}

	// the pages (slides), shown as the pager has them
	public static function Pages(props:{pager:Pager, slides:Array<View>}):View {
		var slides = props.slides, pager = props.pager, page = pager.page, position = pager.position;
		return <view tag="pager" overflow="hidden" onPan={pager.pan} pan-axis="x" ref={n -> pager.root = n}>
			<view position="relative" left={((page() - position()) * 100) + "%"}>
				{[for (i in 0...slides.length) <view tag={"page-" + i} position={i == page() ? Position.Relative : Position.Absolute} top={0}
					left={((i - page()) * 100) + "%"} width="100%">{slides[i]}</view>]}
			</view>
		</view>;
	}
}
