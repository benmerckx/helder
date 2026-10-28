package helder.ui.gesture;

import helder.test.Test;
import helder.ui.view.NodeRenderer;

// helder.ui's gesture arena (natively and as wasm32-wasi: `bun run
// helder test src/helder/ui`): a tap and a click, a scroller's
// drag taking a press from a tap, a Pan inside a scroller winning first
// (along its axis only), a pinch and a Scale with a finger joining
// without a jump, the mouse feeding the arena, cancels, a node leaving the
// tree, markup's attributes making the recognisers.
function tests() {
	describe("gestures", () -> {
		var t = 0.0;
		var ui:Ui = null, list:Node = null, card:Node = null, log:Array<String> = [];
		function report(name:String):Gesture->Void
			return g -> log.push('$name ${stateName(g.state)} ${g.pointers} ${Math.round(g.dx)},${Math.round(g.dy)}');
		beforeEach(() -> {
			t = 0;
			Ui.now = () -> t;
			ui = new Ui(null, 300, 300);
			log = [];
			// a scroller filling the window, a card in it (its first 100 points)
			list = new Node("list");
			list.style.overflow = Scroll;
			list.style.height = 300;
			ui.root.append(list);
			card = new Node("card");
			card.style.height = 100;
			card.style.shrink = 0;
			list.append(card);
			var rest = new Node("rest");
			rest.style.height = 600;
			rest.style.shrink = 0;
			list.append(rest);
			card.onClick = e -> log.push("click");
			ui.update();
		});
		function drag(id:Int, x0:Float, y0:Float, x1:Float, y1:Float, steps = 4, lift = true) {
			ui.pointerDown(x0, y0, 1, id, Touch);
			for (k in 1...steps + 1) {
				t += 0.016;
				ui.pointerMove(x0 + (x1 - x0) * k / steps, y0 + (y1 - y0) * k / steps, id);
			}
			if (lift) ui.pointerUp(x1, y1, 1, id);
		}
		test("a tap: onTap where it was, then the click", () -> {
			var tap = card.addGesture(new Tap());
			var at = [];
			tap.onGesture = g -> at.push('${g.state == Ended} ${g.taps} ${g.x},${g.y}');
			ui.pointerDown(40, 30, 1, 1, Touch);
			ui.pointerMove(43, 31, 1);
			ui.pointerUp(43, 31, 1, 1);
			equals(at, ["true 1 43,31"]);
			equals(log, ["click"]);
		});
		test("a drag scrolls: no tap, no click", () -> {
			card.addGesture(new Tap()).onGesture = report("tap");
			drag(1, 40, 80, 40, 20);
			equals(log, []);
			equals(list.scrollY, 60.0);
		});
		test("a Pan inside a scroller wins first: the list holds still", () -> {
			card.addGesture(new Pan()).onGesture = report("pan");
			drag(1, 40, 80, 40, 20);
			equals(list.scrollY, 0.0);
			equals(log, ["pan Began 1 0,-15", "pan Changed 1 0,-15", "pan Changed 1 0,-15", "pan Changed 1 0,-15", "pan Ended 1 0,0"]);
			// (its first call has the slop's travel: a drag of 3 points, then 6)
			log.resize(0);
			ui.pointerDown(40, 50, 1, 1, Touch);
			ui.pointerMove(40, 53, 1);
			ui.pointerMove(40, 59, 1);
			ui.pointerUp(40, 59, 1, 1);
			equals(log[0], "pan Began 1 0,9");
		});
		test("a Pan along x: a vertical drag still scrolls, a sideways one pans", () -> {
			var pan = card.addGesture(new Pan(X));
			pan.onGesture = report("pan");
			drag(1, 40, 80, 40, 20);
			equals([log.length, list.scrollY], [0, 60.0]);
			list.scrollY = 0;
			drag(1, 40, 50, 100, 52);
			equals(log[0], "pan Began 1 15,0");
			equals(list.scrollY, 0.0);
		});
		test("a pinch: two fingers spreading, about their centre", () -> {
			var pinch = card.addGesture(new Scale(2));
			var seen = [];
			pinch.onGesture = g -> seen.push('${stateName(g.state)} ${Math.round(g.scale * 100) / 100} ${Math.round(g.x)},${Math.round(g.y)}');
			// (one finger alone: not a pinch; the scroll does not get it either, being a second finger's)
			ui.pointerDown(100, 50, 1, 1, Touch);
			ui.pointerDown(140, 50, 1, 2, Touch);
			t += 0.016;
			ui.pointerMove(90, 50, 1);
			ui.pointerMove(150, 50, 2);
			t += 0.016;
			ui.pointerMove(80, 50, 1);
			ui.pointerMove(160, 50, 2);
			ui.pointerUp(80, 50, 1, 1);
			ui.pointerUp(160, 50, 1, 2);
			// (each finger's move a call: the focus between them)
			equals(seen, ["Began 1.25 115,50", "Changed 1.5 120,50", "Changed 1.75 115,50", "Changed 2 120,50", "Ended 2 120,50"]);
			equals(list.scrollY, 0.0);
			equals(log, [], "no click");
		});
		test("a Scale: one finger pans, a second joins without a jump, pinches and turns", () -> {
			var s = card.addGesture(new Scale());
			var last:Array<Float> = [];
			s.onGesture = g -> last = [g.tx, g.ty, Math.round(g.scale * 100) / 100, Math.round(g.angle * 100) / 100, g.pointers];
			drag(1, 100, 50, 120, 50, 2, false);
			equals(last, [20.0, 0.0, 1.0, 0.0, 1.0]);
			ui.pointerDown(160, 50, 1, 2, Touch);
			equals(last[0], 20.0, "no jump of the focus when it joins");
			t += 0.016;
			// (the second finger swings round the first: a quarter turn, the distance kept)
			ui.pointerMove(120, 90, 2);
			equals([last[2], last[3]], [1.0, Math.round(Math.PI / 2 * 100) / 100]);
			t += 0.016;
			ui.pointerMove(120, 130, 2);
			equals(last[2], 2.0, "twice as far: scale 2");
			ui.pointerUp(120, 50, 1, 1);
			ui.pointerUp(120, 130, 1, 2);
			equals(list.scrollY, 0.0);
		});
		test("the mouse feeds the arena", () -> {
			card.addGesture(new Pan()).onGesture = report("pan");
			ui.pointerDown(40, 50, 1);
			ui.pointerMove(60, 50);
			ui.pointerMove(70, 50);
			ui.pointerUp(70, 50, 1);
			equals(log, ["pan Began 1 20,0", "pan Changed 1 10,0", "pan Ended 1 0,0", "click"]);
		});
		test("a gesture cancelled gives the pointer back; a node leaving the tree cancels its own", () -> {
			var pan = card.addGesture(new Pan());
			pan.onGesture = g -> {
				log.push(stateName(g.state));
				if (g.state == Changed) g.cancel();
			};
			drag(1, 40, 50, 40, 90, 3, false);
			equals(log, ["Began", "Changed", "Cancelled"]);
			ui.pointerUp(40, 90, 1, 1);
			log.resize(0);
			drag(2, 40, 50, 40, 70, 2, false);
			list.remove(card);
			equals(log, ["Began", "Changed", "Cancelled"]);
		});
		test("markup's attributes make the recognisers", () -> {
			var seen = [];
			NodeRenderer.listen(card, "onTap", (g:Gesture) -> seen.push("tap"));
			NodeRenderer.listen(card, "onPan", (g:Gesture) -> seen.push("pan"));
			NodeRenderer.listen(card, "onPinch", (g:Gesture) -> {});
			NodeRenderer.setAttribute(card, "pan-axis", "x");
			equals(card.gestures.length, 3);
			assert(card.gesture(Pan).axis == X && card.gesture(Scale).minPointers == 2);
			ui.pointerDown(40, 30, 1, 1, Touch);
			ui.pointerUp(40, 30, 1, 1);
			drag(1, 40, 50, 100, 50);
			equals(seen, ["tap", "pan", "pan", "pan", "pan", "pan"]);
		});
	});
}

private function stateName(s:GestureState):String
	return switch s {
		case Possible: "Possible";
		case Began: "Began";
		case Changed: "Changed";
		case Ended: "Ended";
		case Cancelled: "Cancelled";
		case Failed: "Failed";
	}
