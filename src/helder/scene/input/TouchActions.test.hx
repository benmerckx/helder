package helder.scene.input;

#if (target.name == "hxmc")
import helder.os.Pointer;
import helder.os.Pointers;
import helder.test.Test;

// Actions from fingers (helder.os.Pointers' slots fed as a back end does,
// no window: a 400 x 300 one by setSize): on-screen sticks and buttons,
// touch zones, a look zone's drag, the ui's presses left alone, cancels,
// and nothing allocated per step (natively and as wasm32-wasi:
// `bun run helder test src/helder/scene --target host,wasm`).
function tests() {
	describe("touch actions", () -> {
		var a:Actions = null, move:VirtualStick = null, fire:VirtualButton = null;
		var t = 0.0;
		function down(key:Int, x:Float, y:Float):Pointer
			return @:privateAccess Pointers.press(null, key, Touch, x, y, 1, t++);
		function to(p:Pointer, x:Float, y:Float)
			@:privateAccess p.moveTo(x, y, 1, t++);
		function up(p:Pointer, cancelled = false)
			@:privateAccess Pointers.lift(p, cancelled, t++);
		beforeEach(() -> {
			@:privateAccess Pointers.reset();
			a = new Actions();
			a.setSize(400, 300);
			// the left half's lower part a floating stick (40 points), a fire button on the right, the right half's top a look zone
			move = new VirtualStick({zone: Zone.rect(0, 0.4, 0.5, 1), radius: 40, deadZone: 0.1});
			fire = new VirtualButton({zone: Zone.circle(0.875, 0.8, 30), slop: 10});
			a.bind("moveX", Stick(move, 0)).bind("moveY", Stick(move, 1)).bind("moveX", KeyAxis(0x61, 0x64));
			a.bind("fire", Button(fire)).bind("fire", Key(0x20));
			a.bind("lookX", TouchDelta(0, Zone.rect(0.5, 0, 1, 0.6), 0.5)).bind("lookY", TouchDelta(1, Zone.rect(0.5, 0, 1, 0.6), 0.5));
			a.bind("grab", Touch(Zone.rect(0, 0, 0.5, 0.4)));
		});
		test("a floating stick: where the thumb landed, full tilt at its radius, back to rest", () -> {
			var p = down(1, 100, 250);
			a.step();
			assert(move.active && move.centerX == 100 && a.axis("moveX") == 0);
			to(p, 140, 250);
			a.step();
			equals([a.axis("moveX"), a.axis("moveY")], [1.0, 0.0], "40 points right: full tilt");
			to(p, 100, 230);
			a.step();
			approx(a.axis("moveY"), (0.5 - 0.1) / 0.9, 1e-9, "20 up: half, past the dead zone");
			to(p, 102, 250);
			a.step();
			equals(a.axis("moveX"), 0.0, "within the dead zone");
			to(p, 300, 250);
			a.step();
			equals(a.axis("moveX"), 1.0, "dragged anywhere, still its");
			up(p);
			a.step();
			assert(!move.active && a.axis("moveX") == 0);
		});
		test("a fixed stick: from its zone's centre", () -> {
			var fixed = new VirtualStick({zone: Zone.circle(0.5, 0.5, 50), floating: false, radius: 50, deadZone: 0});
			var b = new Actions();
			b.setSize(400, 300);
			b.bind("x", Stick(fixed, 0));
			down(1, 210, 150);
			b.step();
			approx(b.axis("x"), 0.2);
		});
		test("a cancel lets go: the player stops", () -> {
			var p = down(1, 100, 250), q = down(2, 350, 240);
			to(p, 140, 250);
			a.step();
			assert(a.axis("moveX") == 1 && a.held("fire"));
			up(p, true);
			up(q, true);
			a.step();
			assert(a.axis("moveX") == 0 && !a.held("fire") && a.released("fire"));
		});
		test("a button: a tap within a step counts, sliding off lets go, sliding on does not press", () -> {
			var p = down(1, 350, 240);
			up(p);
			a.step();
			assert(a.pressed("fire") && a.released("fire") && !a.held("fire"), "a tap");
			p = down(1, 350, 240);
			a.step();
			assert(a.pressed("fire") && a.held("fire"));
			to(p, 352, 205);
			a.step();
			assert(a.held("fire"), "within its slop");
			to(p, 250, 150);
			a.step();
			assert(!a.held("fire") && a.released("fire"), "slid off");
			to(p, 350, 240);
			a.step();
			assert(!a.held("fire"), "back over it: not again");
			up(p);
			// (a finger from the look zone sliding over the button: the look's)
			var q = down(2, 300, 50);
			a.step();
			to(q, 350, 240);
			a.step();
			assert(!a.held("fire"));
			// (and the keyboard drives the same action)
			var e = new helder.os.Event();
			e.kind = KeyDown;
			e.key = 0x20;
			a.event(e);
			a.step();
			assert(a.pressed("fire"));
		});
		test("a touch zone: held while its finger is down, wherever it goes", () -> {
			var p = down(1, 50, 50);
			a.step();
			assert(a.pressed("grab") && a.held("grab"));
			to(p, 390, 290);
			a.step();
			assert(a.held("grab") && !move.active, "out of its zone: still held; the stick's zone: not the stick's");
			up(p);
			a.step();
			assert(a.released("grab"));
		});
		test("a look zone: the drag over a step, in points times its scale, any fingers", () -> {
			var p = down(1, 300, 50), q = down(2, 350, 100);
			a.step();
			to(p, 310, 40);
			to(p, 320, 40);
			to(q, 360, 100);
			a.step();
			equals([a.axis("lookX"), a.axis("lookY")], [(20 + 10) * 0.5, -10 * 0.5]);
			a.step();
			equals(a.axis("lookX"), 0.0, "no drag this step");
			// (a press and its moves within one step: from where it came down)
			up(p);
			up(q);
			var r = down(3, 300, 50);
			to(r, 304, 50);
			a.step();
			equals(a.axis("lookX"), 2.0);
		});
		test("a press on ui is the ui's", () -> {
			var p = down(1, 100, 250);
			p.owner = Ui;
			to(p, 140, 250);
			a.step();
			assert(!move.active && a.axis("moveX") == 0);
			var q = down(2, 120, 250);
			a.step();
			assert(move.active && q.owner == Control);
		});
		test("one finger per stick, the next one to the zones after", () -> {
			var p = down(1, 100, 250), q = down(2, 150, 250);
			a.step();
			assert(move.pointer == p.id && q.owner == None, "the second finger in the stick's zone: nobody's");
		});
		test("nothing allocated per step", () -> {
			function round(k:Int) {
				var p = down(k, 100, 250), q = down(k + 1, 300, 50), r = down(k + 2, 350, 240);
				a.step();
				to(p, 120 + k % 7, 240);
				to(q, 310, 60 + k % 3);
				a.step();
				up(p, k % 2 == 0);
				up(q);
				up(r);
				a.step();
				Pointers.step();
			}
			round(0);
			var before = hxmc.GcStats.bytesAllocated();
			for (k in 1...1000)
				round(k * 3);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
		});
	});
}
#else
function tests() {}
#end
