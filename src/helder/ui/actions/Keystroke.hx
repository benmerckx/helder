package helder.ui.actions;

import helder.ui.Key;
import helder.ui.Shortcut;

// One key with its modifiers, as a keymap writes it (Zed's GPUI): "ctrl-s",
// "cmd-shift-p", "alt-enter", "f11", "escape", "ctrl--" (the minus key),
// "secondary-o" (Command on macOS, Control elsewhere: Keymap.mac). A
// sequence is keystrokes separated by spaces: "secondary-k secondary-s" (a
// chord: Keymap waits for the rest). Modifiers: ctrl (control), alt
// (option), shift, cmd (meta, super, win, command), secondary. Keys: a
// character ("s", "/", "=", "-", "+"), and Shortcut's names in lower case
// (enter, escape, tab, space, backspace, delete, insert, home, end, pageup,
// pagedown, up, down, left, right, menu, f1 to f24). Letters match with or
// without Shift's capital (a key's code is its unshifted character).
class Keystroke {
	public final key:Int;
	// Key.MOD_* besides secondary
	public final mods:Int;
	public final secondary:Bool;

	public function new(key:Int, mods:Int, secondary = false) {
		this.key = key;
		this.mods = mods;
		this.secondary = secondary;
	}

	// the modifiers it needs on this platform (secondary resolved)
	public inline function held():Int
		return mods | (secondary ? (Keymap.mac ? Key.MOD_META : Key.MOD_CONTROL) : 0);

	public static function parse(s:String):Keystroke {
		var t = StringTools.trim(s);
		if (t == "") throw "helder.ui: an empty keystroke";
		// (the parts before the last "-" are modifiers; "ctrl--": the minus key, "-": the key alone)
		var parts:Array<String> = [];
		var rest = t;
		while (rest.length > 1) {
			var i = rest.indexOf("-", 0);
			if (i <= 0 || i == rest.length - 1) break;
			parts.push(rest.substr(0, i));
			rest = rest.substr(i + 1);
		}
		var mods = 0, secondary = false;
		for (p in parts)
			switch p.toLowerCase() {
				case "ctrl" | "control": mods |= Key.MOD_CONTROL;
				case "alt" | "option" | "opt": mods |= Key.MOD_ALT;
				case "shift": mods |= Key.MOD_SHIFT;
				case "cmd" | "meta" | "super" | "win" | "command": mods |= Key.MOD_META;
				case "secondary" | "mod": secondary = true;
				case _: throw "helder.ui: " + p + " is not a modifier, in " + s;
			}
		return new Keystroke(keyCode(rest, s), mods, secondary);
	}

	// "secondary-k secondary-s": its keystrokes
	public static function sequence(s:String):Array<Keystroke>
		return [for (p in StringTools.trim(s).split(" ")) if (p != "") parse(p)];

	static function keyCode(name:String, whole:String):Int {
		var l = name.toLowerCase();
		var named = switch l {
			case "enter" | "return": Key.ENTER;
			case "escape" | "esc": Key.ESCAPE;
			case "tab": Key.TAB;
			case "space": Key.SPACE;
			case "backspace": Key.BACKSPACE;
			case "delete" | "del": Key.DELETE;
			case "insert": Key.INSERT;
			case "home": Key.HOME;
			case "end": Key.END;
			case "pageup": Key.PAGE_UP;
			case "pagedown": Key.PAGE_DOWN;
			case "up": Key.UP;
			case "down": Key.DOWN;
			case "left": Key.LEFT;
			case "right": Key.RIGHT;
			case "menu": Key.MENU;
			case "plus": "+".code;
			case "minus": "-".code;
			case _: -1;
		}
		if (named >= 0) return named;
		if (l.length > 1 && l.charAt(0) == "f" && Std.parseInt(l.substr(1)) != null) {
			var n = Std.parseInt(l.substr(1));
			if (n >= 1 && n <= 24) return Key.F1 + n - 1;
		}
		if (name.length == 1) return l.charCodeAt(0);
		throw "helder.ui: " + name + " is not a key, in " + whole;
	}

	// whether a key press with these modifiers is this keystroke
	public function matches(key:Int, mods:Int):Bool {
		if (key >= "A".code && key <= "Z".code) key += 32;
		return key == this.key && mods & (Key.MOD_SHIFT | Key.MOD_CONTROL | Key.MOD_ALT | Key.MOD_META) == held();
	}

	public function equals(o:Keystroke):Bool
		return o.key == key && o.held() == held();

	// as the platform's menus show it: "Ctrl+Shift+S", "⇧⌘S" (Keymap.mac)
	public function label():String {
		var was = Shortcut.mac;
		Shortcut.mac = Keymap.mac;
		var s = new Shortcut(key, held(), false).label();
		Shortcut.mac = was;
		return s;
	}

	// as a keymap writes it: "secondary-shift-s"
	public function toString():String {
		var s = (secondary ? "secondary-" : "") + (mods & Key.MOD_CONTROL != 0 ? "ctrl-" : "") + (mods & Key.MOD_ALT != 0 ? "alt-" : "")
			+ (mods & Key.MOD_SHIFT != 0 ? "shift-" : "") + (mods & Key.MOD_META != 0 ? "cmd-" : "");
		return s + switch key {
			case Key.ENTER: "enter";
			case Key.ESCAPE: "escape";
			case Key.TAB: "tab";
			case Key.SPACE: "space";
			case Key.BACKSPACE: "backspace";
			case Key.DELETE: "delete";
			case Key.INSERT: "insert";
			case Key.HOME: "home";
			case Key.END: "end";
			case Key.PAGE_UP: "pageup";
			case Key.PAGE_DOWN: "pagedown";
			case Key.UP: "up";
			case Key.DOWN: "down";
			case Key.LEFT: "left";
			case Key.RIGHT: "right";
			case Key.MENU: "menu";
			case k if (k >= Key.F1 && k < Key.F1 + 24): "f" + (k - Key.F1 + 1);
			case k: String.fromCharCode(k);
		}
	}
}
