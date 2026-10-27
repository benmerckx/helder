package helder.ui.widgets;

import helder.ui.Key;

// a menu's item (Widgets' MenuItem: the same fields): its label, what
// choosing it does, a shortcut; variant, disabled, a separator, a heading;
// checked: a checkbox item, radio: one of a group; items: a submenu
typedef MenuEntry = {label:String, ?onSelect:Void->Void, ?shortcut:String, ?variant:String, ?disabled:Bool, ?separator:Bool, ?heading:Bool,
	?checked:helder.view.Signal<Bool>, ?radio:{group:helder.view.Signal<String>, value:String}, ?items:Array<MenuEntry>};

// a tree's visible row (Widgets' TreeRow): its item, depth (from 1), its
// parent's row (-1: a root), whether it has no children, is open
typedef TreeLine<T> = {item:T, level:Int, parent:Int, leaf:Bool, open:Bool};

// The widgets' behaviour without nodes: what a key does to a widget's
// state, given its state as values (an index, a value, a selection), in
// helder.ui's key codes (Key) and modifiers. What helder.ui's widgets do with
// their nodes and the DOM's widgets (packages/web, helder.web.widgets) with
// their elements is the renderer's: focusing, placing, drawing. Pure Haxe:
// it brings nothing of helder.ui but Key, Color and Days.
class Behaviour {
	// a key, Left and Right swapped right to left (the way they point in a mirrored row)
	public static inline function mirror(key:Int, rtl:Bool):Int
		return key != Key.LEFT && key != Key.RIGHT || !rtl ? key : key == Key.LEFT ? Key.RIGHT : Key.LEFT;

	// a roving group's next stop from i of n (tabs, a radio group, a toggle
	// group, a toolbar, a menu bar) for a key (mirrored already): Left and
	// Right, Up and Down (both: vertical as well), wrapping; Home and End;
	// -1: none
	public static function rove(key:Int, i:Int, n:Int, vertical = true):Int {
		if (n <= 0) return -1;
		return switch key {
			case Key.RIGHT: (i + 1) % n;
			case Key.LEFT: (i + n - 1) % n;
			case Key.DOWN if (vertical): (i + 1) % n;
			case Key.UP if (vertical): (i + n - 1) % n;
			case Key.HOME: 0;
			case Key.END: n - 1;
			case _: -1;
		}
	}

	// a value within lo and hi, to the step (0: any), without the binary
	// fractions' noise: 0.6, not 0.6000000000000001
	public static function snap(v:Float, lo:Float, hi:Float, step:Float):Float {
		v = Math.max(lo, Math.min(hi, v));
		return step > 0 ? Math.max(lo, Math.min(hi, Math.fround((lo + Math.fround((v - lo) / step) * step) * 1e9) / 1e9)) : v;
	}

	// a slider's value after a key (mirrored already): Left and Down a step
	// (or a twentieth) less, Right and Up more, Home and End its bounds; null: not its key
	public static function slide(key:Int, value:Float, lo:Float, hi:Float, step:Float):Null<Float> {
		var d = step > 0 ? step : (hi - lo) / 20;
		return switch key {
			case Key.LEFT | Key.DOWN: snap(value - d, lo, hi, step);
			case Key.RIGHT | Key.UP: snap(value + d, lo, hi, step);
			case Key.HOME: lo;
			case Key.END: hi;
			case _: null;
		}
	}

	// a chart's scale's top: the value rounded up to 1, 2, 2.5 or 5 times a power of ten
	public static function niceMax(v:Float):Float {
		if (!(v > 0)) return 1;
		var p = Math.pow(10, Math.floor(Math.log(v) / Math.log(10)));
		for (m in [1.0, 2.0, 2.5, 5.0, 10.0])
			if (m * p >= v - 1e-9) return m * p;
		return 10 * p;
	}

	// pagination's buttons in order (0 for a gap): the first, the last, the
	// current one and its neighbours, a page instead of a gap that hides one
	public static function pages(page:Int, count:Int):Array<Int> {
		var out:Array<Int> = [];
		for (i in 1...count + 1)
			if (i == 1 || i == count || Math.abs(i - page) <= 1 || (i == 2 && page == 4) || (i == count - 1 && page == count - 3)) {
				if (out.length > 0 && i - out[out.length - 1] > 1) out.push(0);
				out.push(i);
			}
		return out;
	}

	// (a menu's entry not chosen or moved to: a separator, a heading, a disabled one)
	public static function skipped(it:MenuEntry):Bool
		return it.separator == true || it.heading == true || it.disabled == true;

	// the next entry from from that can be chosen, the way d goes (-1: none)
	public static function nextEntry(list:Array<MenuEntry>, from:Int, d:Int):Int {
		var j = from + d;
		while (j >= 0 && j < list.length && skipped(list[j]))
			j += d;
		return j >= 0 && j < list.length ? j : -1;
	}

	// what choosing an entry does to its signals (a checkbox's, a radio's group), then onSelect
	public static function choose(it:MenuEntry) {
		if (it.checked != null) it.checked.value = !it.checked.peek();
		if (it.radio != null) it.radio.group.value = it.radio.value;
		if (it.onSelect != null) it.onSelect();
	}

	// a tree's visible rows: the roots and, under each open item, its children's
	public static function treeLines<T>(roots:Null<Array<T>>, children:T->Null<Array<T>>, open:Array<T>):Array<TreeLine<T>> {
		var out:Array<TreeLine<T>> = [];
		function add(items:Null<Array<T>>, level:Int, parent:Int) {
			if (items == null) return;
			for (it in items) {
				var kids = children(it);
				var leaf = kids == null || kids.length == 0;
				var isOpen = !leaf && open.indexOf(it) >= 0;
				out.push({item: it, level: level, parent: parent, leaf: leaf, open: isOpen});
				if (isOpen) add(kids, level + 1, out.length - 1);
			}
		}
		add(roots, 1, -1);
		return out;
	}

	// a calendar's marked day (a day number, Days.of) after a key (mirrored
	// already): a day, a week, the week's ends (first: its first weekday, 0
	// Sunday); null: not its key (Page Up and Down: month, by the caller)
	public static function calendarKey(key:Int, cursor:Int, first:Int):Null<Int> {
		var wd = (Days.weekday(cursor) - first + 7) % 7;
		return switch key {
			case Key.LEFT: cursor - 1;
			case Key.RIGHT: cursor + 1;
			case Key.UP: cursor - 7;
			case Key.DOWN: cursor + 7;
			case Key.HOME: cursor - wd;
			case Key.END: cursor + 6 - wd;
			case _: null;
		}
	}

	// the day delta months from cursor (the day kept within the month)
	public static function addMonths(cursor:Int, delta:Int):Int {
		var d = Days.day(cursor);
		var m = d.month - 1 + delta, y = d.year + Math.floor(m / 12);
		m = ((m % 12) + 12) % 12 + 1;
		return Days.of({year: y, month: m, day: Std.int(Math.min(d.day, Days.length(y, m)))});
	}

	// the first day a month's grid shows (its weeks from first, 0 Sunday)
	public static function gridStart(year:Int, month:Int, first:Int):Int {
		var f = Days.of({year: year, month: month, day: 1});
		return f - ((Days.weekday(f) - first + 7) % 7);
	}

	// an opaque colour from a hue in degrees, saturation and value from 0 to 1
	public static function hsv(h:Float, s:Float, v:Float):Color {
		var c = v * s, p = (h / 60) % 6, x = c * (1 - Math.abs(p % 2 - 1)), m = v - c;
		var r = 0.0, g = 0.0, b = 0.0;
		if (p < 1) {
			r = c;
			g = x;
		} else if (p < 2) {
			r = x;
			g = c;
		} else if (p < 3) {
			g = c;
			b = x;
		} else if (p < 4) {
			g = x;
			b = c;
		} else if (p < 5) {
			r = x;
			b = c;
		} else {
			r = c;
			b = x;
		}
		return Color.fromFloats(r + m, g + m, b + m);
	}

	// a colour's hue (null for a grey: none), saturation and value
	public static function hsvOf(c:Color):{h:Null<Float>, s:Float, v:Float} {
		var r = c.r / 255, g = c.g / 255, b = c.b / 255;
		var max = Math.max(r, Math.max(g, b)), d = max - Math.min(r, Math.min(g, b));
		var h:Null<Float> = null;
		if (d > 0) {
			var x = max == r ? (g - b) / d : max == g ? (b - r) / d + 2 : (r - g) / d + 4;
			h = (x * 60 + 360) % 360;
		}
		return {h: h, s: max == 0 ? 0 : d / max, v: max};
	}

	// the indices from a to b, either way round (a list box's Shift range)
	public static function range(a:Int, b:Int):Array<Int>
		return [for (i in (a < b ? a : b)...(a < b ? b : a) + 1) i];

	// what a one-time code field keeps of text: digits only (or any
	// character but spaces), at most n
	public static function code(s:String, n:Int, digits:Bool):String {
		var out = new StringBuf(), count = 0;
		for (c in new haxe.iterators.StringIteratorUnicode(s)) {
			if (count >= n) break;
			if (digits ? c >= "0".code && c <= "9".code : c > 32) {
				out.addChar(c);
				count++;
			}
		}
		return out.toString();
	}

	// (a number as it is, to ten decimals: 0.1 + 0.2 shown as 0.3)
	public static function plain(v:Float):String {
		var s = Std.string(Math.fround(v * 1e10) / 1e10);
		return StringTools.endsWith(s, ".0") ? s.substr(0, s.length - 2) : s;
	}

	// a sortable list with item moved before index to (in the list as it
	// is): the new list and the item's index there (null: no move)
	public static function moved<T>(list:Array<T>, item:T, to:Int):Null<{list:Array<T>, at:Int}> {
		var from = list.indexOf(item);
		if (from < 0 || to < 0 || to > list.length) return null;
		var out = list.copy();
		out.splice(from, 1);
		if (to > from) to--;
		out.insert(to, item);
		return {list: out, at: to};
	}
}

// type-ahead in a list (a select's, a menu's, a tree's): letters and
// digits typed within a second of each other make a prefix, the item it
// starts found from the one after (the same letter again: the next with
// it), case aside
class TypeAhead {
	var prefix = "";
	var at = -1e9;

	public function new() {}

	// the item's index for a key typed at item from (now: seconds), else -1
	public function find(key:Int, mods:Int, now:Float, labels:Array<String>, from:Int):Int {
		if (mods & (Key.MOD_CONTROL | Key.MOD_META | Key.MOD_ALT) != 0) return -1;
		var k = key;
		if (k >= "A".code && k <= "Z".code) k += 32;
		if (!(k >= "a".code && k <= "z".code || k >= "0".code && k <= "9".code)) return -1;
		var c = String.fromCharCode(k);
		prefix = now - at < 1 && prefix != c ? prefix + c : c;
		at = now;
		var n = labels.length, start = prefix.length > 1 ? from : from + 1;
		for (j in 0...n) {
			var i = ((start + j) % n + n) % n;
			if (StringTools.startsWith(labels[i].toLowerCase(), prefix)) return i;
		}
		return -1;
	}
}
