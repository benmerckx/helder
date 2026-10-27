package helder.ui;

// A key with modifiers, written as menus show it: "Mod+S", "Ctrl+Shift+Z",
// "Alt+Enter", "F5", "Escape". Modifiers: Shift, Ctrl (Control), Alt
// (Option), Meta (Cmd, Command, Super) and Mod, the platform's own (Control
// or Command: either matches, as the text fields take both). Keys: a
// character ("s", "/", "Plus" for "+"), Enter, Escape (Esc), Tab, Space,
// Backspace, Delete, Insert, Home, End, PageUp, PageDown, Up, Down, Left,
// Right (or ArrowUp...), Menu, F1 to F12. Letters match with or without
// Shift's capital (a key's code is its unshifted character).
class Shortcut {
	// labels in macOS's symbols (⇧⌘S); UiWindow sets it on macOS
	public static var mac = false;

	public final key:Int;
	public final mods:Int;
	// Mod: Control or Meta
	public final mod:Bool;

	public function new(key:Int, mods:Int, mod:Bool) {
		this.key = key;
		this.mods = mods;
		this.mod = mod;
	}

	static final KEYS = [
		"enter" => Key.ENTER, "return" => Key.ENTER, "escape" => Key.ESCAPE, "esc" => Key.ESCAPE, "tab" => Key.TAB, "space" => Key.SPACE,
		"backspace" => Key.BACKSPACE, "delete" => Key.DELETE, "del" => Key.DELETE, "insert" => Key.INSERT, "home" => Key.HOME, "end" => Key.END,
		"pageup" => Key.PAGE_UP, "pagedown" => Key.PAGE_DOWN, "up" => Key.UP, "down" => Key.DOWN, "left" => Key.LEFT, "right" => Key.RIGHT,
		"arrowup" => Key.UP, "arrowdown" => Key.DOWN, "arrowleft" => Key.LEFT, "arrowright" => Key.RIGHT, "menu" => Key.MENU, "plus" => "+".code
	];

	public static function parse(s:String):Shortcut {
		var parts = StringTools.trim(s).split("+");
		// ("Mod++": a plus as the key)
		if (parts.length > 1 && parts[parts.length - 1] == "" && parts[parts.length - 2] == "") parts = parts.slice(0, parts.length - 2).concat(["+"]);
		var mods = 0, mod = false, key = -1;
		for (i in 0...parts.length) {
			var p = StringTools.trim(parts[i]), l = p.toLowerCase();
			if (i < parts.length - 1) {
				switch l {
					case "shift": mods |= Key.MOD_SHIFT;
					case "ctrl" | "control": mods |= Key.MOD_CONTROL;
					case "alt" | "option" | "opt": mods |= Key.MOD_ALT;
					case "meta" | "cmd" | "command" | "super": mods |= Key.MOD_META;
					case "mod": mod = true;
					case _: throw "helder.ui: " + p + " is not a modifier, in " + s;
				}
				continue;
			}
			if (KEYS.exists(l)) key = KEYS.get(l);
			else if (l.length > 1 && l.charAt(0) == "f" && Std.parseInt(l.substr(1)) != null) {
				var n = Std.parseInt(l.substr(1));
				if (n < 1 || n > 24) throw "helder.ui: " + p + " is not a key, in " + s;
				key = Key.F1 + n - 1;
			} else if (p.length == 1) key = l.charCodeAt(0);
			else throw "helder.ui: " + p + " is not a key, in " + s;
		}
		if (key < 0) throw "helder.ui: no key in " + s;
		return new Shortcut(key, mods, mod);
	}

	// whether a key press with these modifiers is this shortcut
	public function matches(key:Int, mods:Int):Bool {
		if (key >= "A".code && key <= "Z".code) key += 32;
		if (key != this.key) return false;
		var held = mods & (Key.MOD_SHIFT | Key.MOD_CONTROL | Key.MOD_ALT | Key.MOD_META);
		if (!mod) return held == this.mods;
		// (Mod: exactly one of Control and Command, besides the rest)
		var platform = held & (Key.MOD_CONTROL | Key.MOD_META);
		return (platform == Key.MOD_CONTROL || platform == Key.MOD_META) && held & ~(Key.MOD_CONTROL | Key.MOD_META) == this.mods & ~(Key.MOD_CONTROL | Key.MOD_META);
	}

	// as the platform's menus show it: "Ctrl+Shift+S", "⇧⌘S" (mac)
	public function label():String {
		var ctrl = mods & Key.MOD_CONTROL != 0 || (mod && !mac), meta = mods & Key.MOD_META != 0 || (mod && mac);
		var shift = mods & Key.MOD_SHIFT != 0, alt = mods & Key.MOD_ALT != 0;
		var k = keyName();
		if (mac) return (ctrl ? "⌃" : "") + (alt ? "⌥" : "") + (shift ? "⇧" : "") + (meta ? "⌘" : "") + k;
		return (ctrl ? "Ctrl+" : "") + (alt ? "Alt+" : "") + (shift ? "Shift+" : "") + (meta ? "Meta+" : "") + k;
	}

	function keyName():String
		return switch key {
			case Key.ENTER: mac ? "↩" : "Enter";
			case Key.ESCAPE: mac ? "⎋" : "Esc";
			case Key.TAB: mac ? "⇥" : "Tab";
			case Key.SPACE: "Space";
			case Key.BACKSPACE: mac ? "⌫" : "Backspace";
			case Key.DELETE: mac ? "⌦" : "Del";
			case Key.INSERT: "Ins";
			case Key.HOME: mac ? "↖" : "Home";
			case Key.END: mac ? "↘" : "End";
			case Key.PAGE_UP: mac ? "⇞" : "PgUp";
			case Key.PAGE_DOWN: mac ? "⇟" : "PgDn";
			case Key.UP: "↑";
			case Key.DOWN: "↓";
			case Key.LEFT: "←";
			case Key.RIGHT: "→";
			case Key.MENU: "Menu";
			case k if (k >= Key.F1 && k < Key.F1 + 24): "F" + (k - Key.F1 + 1);
			case k: String.fromCharCode(k).toUpperCase();
		}

	public function toString():String
		return label();
}
