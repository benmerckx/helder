package helder.ui;

import helder.test.Test;

// helder.ui's fingers and pens (Ui.pointerDown with a pointer id): their
// own events and captures, taps that click, a drag that scrolls and
// cancels the press, cancels, a node leaving the tree, whose pointer a
// press is (natively and as wasm32-wasi: `bun run helder test
// src/helder/ui`). The gestures' arena: Gestures.test.hx.
function tests() {
	describe("ui's pointers", () -> {
		var t = 0.0;
		var ui:Ui = null, log:Array<String> = [];
		var a:Node = null, b:Node = null, list:Node = null, item:Node = null;
		function listen(n:Node, name:String) {
			n.onPointerDown = e -> log.push('$name down ${e.pointerId}${e.isPrimary ? " primary" : ""}');
			n.onPointerMove = e -> log.push('$name move ${e.pointerId}');
			n.onPointerUp = e -> log.push('$name up ${e.pointerId}');
			n.onPointerCancel = e -> log.push('$name cancel ${e.pointerId}');
			n.onClick = e -> log.push('$name click ${e.pointerId}');
			n.onLostPointerCapture = e -> log.push('$name lost ${e.pointerId}');
		}
		beforeEach(() -> {
			t = 0;
			Ui.now = () -> t;
			ui = new Ui(null, 300, 200);
			log = [];
			// two buttons side by side, a list that scrolls under them
			a = box(ui.root, 0, 0, 100, 50);
			b = box(ui.root, 100, 0, 100, 50);
			list = box(ui.root, 0, 50, 300, 150);
			list.style.overflow = Scroll;
			item = new Node("item");
			item.style.height = 600;
			item.style.shrink = 0;
			list.append(item);
			listen(a, "a");
			listen(b, "b");
			listen(item, "item");
			ui.update();
		});
		test("two fingers at once: each its own events, each tap a click", () -> {
			assert(ui.pointerDown(50, 25, 1, 1, Touch));
			assert(ui.pointerDown(150, 25, 1, 2, Touch));
			ui.pointerMove(52, 25, 1);
			ui.pointerUp(52, 25, 1, 1);
			ui.pointerUp(150, 25, 1, 2);
			equals(log, ["a down 1 primary", "b down 2", "a move 1", "a up 1", "a lost 1", "a click 1", "b up 2", "b lost 2", "b click 2"]);
		});
		test("a finger is its node's until it lifts (implicit capture)", () -> {
			ui.pointerDown(97, 25, 1, 1, Touch);
			ui.pointerMove(103, 25, 1);
			ui.pointerUp(103, 25, 1, 1);
			equals(log, ["a down 1 primary", "a move 1", "a up 1", "a lost 1"], "over b, within the slop: a's, no click");
		});
		test("capture moved to another node, then released", () -> {
			a.onPointerDown = e -> b.capture();
			ui.pointerDown(50, 25, 1, 1, Touch);
			ui.pointerMove(53, 25, 1);
			b.releaseCapture();
			ui.pointerMove(55, 25, 1);
			ui.pointerUp(55, 25, 1, 1);
			equals(log, ["a lost 1", "b move 1", "b lost 1", "a move 1", "a up 1"]);
		});
		test("a cancel: no click", () -> {
			ui.pointerDown(50, 25, 1, 1, Touch);
			ui.pointerCancel(1);
			ui.pointerUp(50, 25, 1, 1);
			equals(log, ["a down 1 primary", "a cancel 1", "a lost 1"]);
		});
		test("a node leaving the tree cancels its press", () -> {
			ui.pointerDown(50, 25, 1, 1, Touch);
			ui.root.remove(a);
			ui.pointerUp(50, 25, 1, 1);
			equals(log, ["a down 1 primary", "a cancel 1", "a lost 1"]);
		});
		test("a drag scrolls what is under where it started, its press cancelled", () -> {
			var wheel = 0.0;
			ui.root.onWheel = e -> wheel += e.deltaY;
			ui.pointerDown(50, 150, 1, 1, Touch);
			t += 0.016;
			ui.pointerMove(50, 145, 1);
			equals(list.scrollY, 0.0, "within the slop");
			t += 0.016;
			ui.pointerMove(50, 130, 1);
			t += 0.016;
			ui.pointerMove(50, 100, 1);
			equals([wheel, list.scrollY], [50.0, 50.0], "by the whole motion since the press, the content following");
			// (rested, then let go: no glide)
			t += 0.5;
			ui.pointerUp(50, 100, 1, 1);
			equals(log, ["item down 1 primary", "item move 1", "item move 1", "item cancel 1", "item lost 1"]);
			ui.update();
			equals(list.scrollY, 50.0);
		});
		test("a flick glides on, slowing; a new touch stops it", () -> {
			ui.pointerDown(50, 190, 1, 1, Touch);
			for (k in 1...4) {
				t += 0.016;
				ui.pointerMove(50, 190 - 30 * k, 1);
			}
			ui.pointerUp(50, 100, 1, 1);
			var before = list.scrollY;
			equals(before, 90.0);
			for (_ in 0...10) {
				t += 1 / 60;
				ui.update();
			}
			assert(list.scrollY > before + 100, 'glided to ${list.scrollY}');
			assert(ui.needsFrame, "frames while it glides");
			var at = list.scrollY;
			ui.pointerDown(50, 100, 1, 1, Touch);
			t += 1 / 60;
			ui.update();
			equals(list.scrollY, at);
			ui.pointerUp(50, 100, 1, 1);
		});
		test("a second finger's drag scrolls nothing (the first finger's alone)", () -> {
			ui.pointerDown(50, 150, 1, 1, Touch);
			ui.pointerDown(150, 150, 1, 2, Touch);
			ui.pointerMove(150, 100, 2);
			ui.pointerUp(150, 100, 1, 2);
			ui.pointerUp(50, 150, 1, 1);
			equals(list.scrollY, 0.0);
			assert(log.contains("item move 2") && !log.contains("item click 2") && log.contains("item click 1"), log.join(", "));
		});
		test("whose a press is: a node's, not the root's nor a world's under the ui", () -> {
			var world = box(ui.root, 200, 0, 50, 50, new WorldBox("scene"));
			ui.update();
			assert(ui.pointerDown(50, 25, 1, 1, Touch), "a button");
			assert(!ui.pointerDown(225, 25, 1, 2, Touch), "a world's box");
			assert(!ui.pointerDown(275, 25, 1, 3, Touch), "the root");
			equals(ui.captureOf(2), (world : Node));
		});
	});
}

private function box(parent:Node, x:Float, y:Float, w:Float, h:Float, ?n:Node):Node {
	if (n == null) n = new Node("box");
	n.style.position = Absolute;
	n.style.left = x;
	n.style.top = y;
	n.style.width = w;
	n.style.height = h;
	parent.append(n);
	return n;
}

// (a box drawing a world under the ui: a <Scene>'s)
private class WorldBox extends Node {
	override public function ownsPointer():Bool
		return false;
}
