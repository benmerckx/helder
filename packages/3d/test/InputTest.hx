import hxmc.os.Event;
import hxmc.scene.input.*;

// packages/3d's step 4 so far (make 3d-check: natively and as wasm32-wasi;
// not on Eval: hxmc.os.Event names a Window):
// Actions from synthetic hxmc.os events: keys, mouse buttons, screen
// regions, key axes, presses within a step, rebinding.
class InputTest {
	static var checks = 0;
	static var failed = 0;

	static function check(what:String, ok:Bool) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('InputTest: FAIL: $what');
		}
	}

	static final e = new Event();

	static function send(kind:hxmc.os.Event.EventKind, key = 0, button = 0, x = 0, y = 0) {
		e.kind = kind;
		e.key = key;
		e.button = button;
		e.x = x;
		e.y = y;
		return e;
	}

	static function main() {
		var a = new Actions();
		a.setSize(400, 300);
		a.bind("jump", Key(0x20)).bind("jump", Region(0.75, 0.5, 1, 1)).bind("fire", Mouse(1)).bind("moveX", KeyAxis(0xFF51, 0xFF53))
			.bind("moveX", KeyAxis(0x61, 0x64)).bind("moveY", KeyAxis(0xFF54, 0xFF52));
		a.step();
		check("nothing yet", !a.pressed("jump") && !a.held("jump") && a.axis("moveX") == 0 && !a.pressed("unknown"));
		a.event(send(KeyDown, 0x20));
		a.event(send(KeyDown, 0x20)); // (a repeat)
		a.step();
		check("pressed and held", a.pressed("jump") && a.held("jump") && !a.released("jump"));
		a.step();
		check("still held, not pressed again", !a.pressed("jump") && a.held("jump"));
		a.event(send(KeyUp, 0x20));
		a.step();
		check("released", a.released("jump") && !a.held("jump"));
		a.event(send(KeyDown, 0x20));
		a.event(send(KeyUp, 0x20));
		a.step();
		check("a tap within a step counts", a.pressed("jump") && a.released("jump") && !a.held("jump"));
		// (a finger or the mouse on the on-screen button: the right of the lower half)
		a.event(send(MouseDown, 0, 1, 350, 250));
		a.step();
		check("a region and a button", a.pressed("jump") && a.pressed("fire") && a.held("jump"));
		a.event(send(MouseMove, 0, 0, 100, 250));
		a.step();
		check("dragged out of the region", a.released("jump") && !a.held("jump") && a.held("fire"));
		a.event(send(MouseUp, 0, 1, 100, 250));
		a.step();
		check("the button let go", a.released("fire") && !a.held("fire"));
		a.event(send(KeyDown, 0xFF53));
		check("axis right", a.axis("moveX") == 1);
		a.event(send(KeyDown, 0x61));
		check("two bindings cancel", a.axis("moveX") == 0);
		a.event(send(KeyUp, 0xFF53));
		check("axis left", a.axis("moveX") == -1);
		a.event(send(KeyDown, 0xFF52));
		var s = a.stick("moveX", "moveY");
		check("a stick of length 1", Math.abs(s.x * s.x + s.y * s.y - 1) < 1e-12 && s.x < 0 && s.y > 0);
		a.unbind("jump").bind("jump", Key(0x77));
		a.event(send(KeyDown, 0x20));
		a.event(send(KeyDown, 0x77));
		a.step();
		check("rebound", a.pressed("jump"));
		Sys.println('InputTest: $checks checks, ' + (failed == 0 ? "ok" : '$failed FAILED'));
		if (failed > 0) Sys.exit(1);
	}
}
