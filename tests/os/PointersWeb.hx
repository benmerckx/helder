import helder.os.*;
import helder.os.Event;

// helder.os's pointers in a browser (`bun run test touch-web`:
// pointers-web.mjs, wasm32-wasi in headless Chromium): every event a line
// for the harness ("down 1 touch 40,30 primary", "mouse-down 1"...),
// and each frame with a change what Pointers says (the pointers down, in
// order, and their motion this frame); the mouse's events and the scrolls
// too, which a touch never makes.
class PointersWeb {
	static function main() {
		var w = new Window("PointersWeb", 300, 200);
		var last = "";
		App.run(() -> {
			var s = "frame";
			for (i in 0...Pointers.count) {
				var p = Pointers.at(i);
				s += ' ${p.id}:${Math.round(p.x)},${Math.round(p.y)}' + (Pointers.justDown(p) ? " new" : "");
			}
			if (s != last) {
				last = s;
				Sys.println(s);
			}
			App.wait(0.05);
		}, e -> {
			var p = e.pointer;
			switch e.kind {
				case PointerDown | PointerMove | PointerUp | PointerCancel:
					var name = switch e.kind {
						case PointerDown: "down";
						case PointerMove: "move";
						case PointerUp: "up";
						case _: "cancel";
					}
					var type = p.type == Mouse ? "mouse" : p.type == Touch ? "touch" : "pen";
					// (a hovering mouse's moves: left out)
					if (e.kind == PointerMove && p.type == Mouse && !p.down) return;
					Sys.println('$name ${p.id} $type ${Math.round(p.x)},${Math.round(p.y)}' + (p.primary ? " primary" : "") + ' samples ${p.samples} buttons ${p.buttons}');
				case MouseDown | MouseUp:
					Sys.println((e.kind == MouseDown ? "mouse-down" : "mouse-up") + ' ${e.button}');
				case Scroll:
					Sys.println('scroll ${Math.round(e.deltaY)} ${e.x},${e.y} mods ${e.mods}');
				case _:
			}
		});
	}
}
