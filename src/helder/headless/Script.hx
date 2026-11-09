package helder.headless;

using StringTools;

// A headless run's script (`helder run --headless --script demo.json`):
// timestamped steps, a JSON array or {"events": [...]}, each
// {"t": seconds, "type": ..., ...}:
//
//   move, down, up         at x, y (points) or at a node (tag, path, index); button: left, middle, right
//   tap                    a press and its release (hold: seconds held, 0.05)
//   double-click           two taps (hold, gap: 0.15 s between the presses)
//   drag                   pressed, moved by dx, dy over dur seconds (0.3), released
//   wheel                  dx, dy points (positive: toward the right and the bottom)
//   key                    name ("Enter", "a", "ArrowLeft", ...) with cmd, ctrl, alt, shift, secondary
//   key-down, key-up       a key pressed and held (Shift for a click), released
//   type                   text, one key per character
//   resize                 width, height (points) or dw, dh; over dur seconds
//   menu-pick              id or label: the open pop-up menu's item chosen; menu-cancel
//   file-dialog            path: the answer to the next file dialog; file-dialog-cancel
//   mark                   name: a time to refer to (--at mark:name+0.5), nothing done
//   literal                a live literal patched (a dev build: helder run --headless --dev;
//                          helder.dev.Literals): the one of id, else of file (its path's end),
//                          value (as compiled) and line, set to set
//
// A node is aimed at by its tag, or a path of tags ("list/checkbox": a
// checkbox inside the list, as a CSS descendant selector), and/or its role
// (ARIA's: "checkbox", "button") and label (its accessible name, else its
// text): the first that matches all given, or the index'th; at its centre
// (or at ox, oy points from its top left). Steps are kept in order of time
// (a stable sort).
class Script {
	public final steps:Array<Step> = [];
	public final marks = new Map<String, Float>();
	// the last step's end (its time, and what it takes: a drag's dur, a tap's hold)
	public var last(default, null) = 0.0;

	public function new() {}

	public static function parse(json:String, source:String):Script {
		var s = new Script();
		var v:Dynamic = try haxe.Json.parse(json) catch (e:Dynamic) throw '$source: not JSON: $e';
		var list:Array<Dynamic> = Std.isOfType(v, Array) ? v : Reflect.field(v, "events");
		if (list == null) throw '$source: a list of steps, or {"events": [...]}';
		for (i in 0...list.length) {
			var o:Dynamic = list[i];
			var where = '$source: step ${i + 1}';
			var t:Null<Float> = Reflect.field(o, "t");
			var type:Null<String> = Reflect.field(o, "type");
			if (t == null || !Std.isOfType(t, Float)) throw '$where: no "t" (its time, in seconds)';
			if (type == null) throw '$where: no "type"';
			if (!TYPES.contains(type)) throw '$where: no step type $type (${TYPES.join(", ")})';
			var step = new Step(i + 1, t, type, o);
			if (type == "mark") {
				var name:Null<String> = Reflect.field(o, "name");
				if (name == null) throw '$where: a mark has a "name"';
				s.marks.set(name, t);
			}
			if (type == "key" || type == "key-down" || type == "key-up") {
				var name:Null<String> = Reflect.field(o, "name");
				if (name == null || Keys.code(name) == null) throw '$where: no key ${name ?? "(no \"name\")"} (Enter, Escape, Tab, Backspace, Delete, Space, ArrowLeft, Home, F1, a single character...)';
			}
			if (type == "type" && !Std.isOfType(Reflect.field(o, "text"), String)) throw '$where: type has a "text"';
			if (type == "literal" && !Reflect.hasField(o, "set")) throw '$where: a literal step has a "set" (its new value)';
			s.steps.push(step);
			var end = t + step.duration();
			if (end > s.last) s.last = end;
		}
		haxe.ds.ArraySort.sort(s.steps, (a, b) -> a.t < b.t ? -1 : a.t > b.t ? 1 : a.index - b.index);
		return s;
	}

	public static final TYPES = [
		"move", "down", "up", "tap", "double-click", "drag", "wheel", "key", "key-down", "key-up", "type", "resize", "menu-pick", "menu-cancel", "file-dialog",
		"file-dialog-cancel", "mark", "literal"
	];
}

class Step {
	public final index:Int;
	public final t:Float;
	public final type:String;
	public final data:Dynamic;

	public function new(index:Int, t:Float, type:String, data:Dynamic) {
		this.index = index;
		this.t = t;
		this.type = type;
		this.data = data;
	}

	public function num(name:String, fallback:Float):Float {
		var v:Dynamic = Reflect.field(data, name);
		return v == null ? fallback : (v : Float);
	}

	public function str(name:String):Null<String>
		return Reflect.field(data, name);

	public function flag(name:String):Bool
		return Reflect.field(data, name) == true;

	// what it takes after its time
	public function duration():Float
		return switch type {
			case "tap": num("hold", Headless.HOLD);
			case "double-click": num("gap", 0.15) + num("hold", Headless.HOLD);
			case "drag": num("dur", 0.3) + Headless.HOLD;
			case "resize": num("dur", 0);
			case "type": (str("text") ?? "").length * num("every", 0);
			case _: 0;
		}

	// its target, as said in messages
	public function target():String {
		var tag = str("tag"), path = str("path"), role = str("role"), label = str("label");
		var index:Null<Int> = Reflect.field(data, "index");
		if (tag != null || path != null || role != null || label != null) {
			var s = path ?? tag ?? "";
			if (role != null) s += '[role=$role]';
			if (label != null) s += '[label=${haxe.Json.stringify(label)}]';
			return s + (index != null ? '[$index]' : "");
		}
		var x:Null<Float> = Reflect.field(data, "x");
		return x != null ? '${x},${num("y", 0)}' : "the pointer";
	}

	public function toString():String
		return 'step $index ($type at ${t} s)';
}

// key names to helder.os's key codes (X11's KeySyms: Latin-1 keys their
// character's code, the others 0xFFxx)
class Keys {
	public static function code(name:String):Null<Int> {
		if (name.length == 1 || (name.length == 2 && name.charCodeAt(0) >= 0xD800)) {
			var c = name.charCodeAt(0);
			if (c >= 0xD800 && c < 0xDC00) c = 0x10000 + ((c - 0xD800) << 10) + (name.charCodeAt(1) - 0xDC00);
			// (letters: their lowercase, as a window sends a key)
			return c >= "A".code && c <= "Z".code ? c + 32 : c;
		}
		return switch name.toLowerCase() {
			case "enter" | "return": 0xFF0D;
			case "escape" | "esc": 0xFF1B;
			case "tab": 0xFF09;
			case "backspace": 0xFF08;
			case "delete" | "del": 0xFFFF;
			case "space": 0x20;
			case "arrowleft" | "left": 0xFF51;
			case "arrowup" | "up": 0xFF52;
			case "arrowright" | "right": 0xFF53;
			case "arrowdown" | "down": 0xFF54;
			case "home": 0xFF50;
			case "end": 0xFF57;
			case "pageup": 0xFF55;
			case "pagedown": 0xFF56;
			case "insert": 0xFF63;
			case "menu" | "contextmenu": 0xFF67;
			case "shift": 0xFFE1;
			case "control" | "ctrl": 0xFFE3;
			case "alt" | "option": 0xFFE9;
			case "meta" | "cmd" | "command": 0xFFE7;
			case n if (n.startsWith("f") && Std.parseInt(n.substr(1)) != null):
				var k = Std.parseInt(n.substr(1));
				k >= 1 && k <= 24 ? 0xFFBE + k - 1 : null;
			case _: null;
		}
	}

	// the character a key types (null: none, a named key)
	public static function text(name:String, shift:Bool):Null<String> {
		if (name.toLowerCase() == "space") return " ";
		if (code(name) == null || (name.length > 2 || (name.length == 2 && name.charCodeAt(0) < 0xD800))) return null;
		return shift ? name.toUpperCase() : name;
	}

	// a keycap's label: ⌃⌥⇧⌘ before it, named keys as glyphs
	public static function label(name:String, mods:Int):String {
		var s = "";
		if (mods & 2 != 0) s += "⌃";
		if (mods & 4 != 0) s += "⌥";
		if (mods & 1 != 0) s += "⇧";
		if (mods & 8 != 0) s += "⌘";
		return s + switch name.toLowerCase() {
			case "enter" | "return": "↩";
			case "escape" | "esc": "⎋";
			case "tab": "⇥";
			case "backspace": "⌫";
			case "delete" | "del": "⌦";
			case "space" | " ": "␣";
			case "arrowleft" | "left": "←";
			case "arrowright" | "right": "→";
			case "arrowup" | "up": "↑";
			case "arrowdown" | "down": "↓";
			case _ if (name.length <= 2): name.toUpperCase();
			case _: name;
		}
	}
}
