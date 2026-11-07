package helder.ui;

import helder.ui.access.Role;
import helder.ui.access.Semantics;

// A scroller over a long list's rows, only those in view made
// (UiFlow.VirtualList's; usable alone): count rows, their heights in a
// HeightIndex (estimated until measured), the rows of the window (the view
// and overscan more on each side) made by onMakeRow into a row node each and
// shown in the flow between two spacers as tall as the rows before and
// after them; rows that leave the window are hidden and kept (keep of them,
// the farthest from the window let go first, onDropRow), shown again as they
// were when they come back. After each layout (Ui.update: settle) the rows
// shown are measured and the window moved, laid out again while that
// changes it, so a frame never shows a gap or the estimates.
//
// The scroll is anchored to a row: the first in view and how far into it,
// kept through measures, a new estimate and rows put in or taken out
// before it (splice), so the content does not move. scrollToIndex (start,
// center, end or the nearest edge: auto) goes to a row made or not, held
// there while its rows are measured; focusIndex makes the row, scrolls to
// it and focuses it. The rows are a listbox's options to assistive
// technology (rowRole), each its place among all (posInSet, setSize). The
// keyboard on a row (its focus within the list): Up and Down, Page Up and
// Down, Home and End move the focus onto that row (made if need be, onRowActive
// told: a selection follows it); Enter and Space are onRowActivate's; the row
// focused or last moved to is the one Tab stops on (the others -1).
// Rows should not have margins: their measure is their border box.
@:allow(helder.ui)
class VirtualScroll extends Node {
	public final heights:HeightIndex;
	// the rows (splice, reset change it)
	public var count(default, null) = 0;
	// rows made beyond the view on each side
	public var overscan = 3;
	// rows out of the window kept made (hidden), at most
	public var keep = 64;
	// every row this high (a row not measured, its node this high); NaN: rows measured
	public var fixedHeight(default, set) = Math.NaN;
	// the estimate follows the measured rows' mean (the scroll anchored)
	public var adaptive = true;
	// what the rows are to assistive technology (null: nothing)
	public var rowRole:Null<Role> = ListBoxOption;
	// the rows focusable (Tab stops on one)
	public var focusableRows = true;

	// a row's node filled for row index (what the source keeps with it returned), a row let go
	public var onMakeRow:Null<(index:Int, row:Node) -> Dynamic> = null;
	public var onDropRow:Null<(row:Node, data:Dynamic) -> Void> = null;
	// the row the keyboard or a press moved to; Enter or Space on a row
	public var onRowActive:Null<Int->Void> = null;
	public var onRowActivate:Null<Int->Void> = null;

	// the window: the rows made and shown, from first to before end
	public var first(default, null) = 0;
	public var end(default, null) = 0;
	// the row Tab stops on (-1: the window's first)
	public var active(default, null) = -1;
	// rows made and let go since it was made (a measure of recycling)
	public var made(default, null) = 0;
	public var dropped(default, null) = 0;

	// (the rows made, by index; spacers before and after the window)
	final slots:Array<VirtualRow> = [];
	final before:Spacer;
	final after:Spacer;
	// (the anchor: a row and the offset into it at the view's top; the scroll it was taken at)
	var anchorRow = 0;
	var anchorDelta = 0.0;
	var seenScroll = 0.0;
	// (a row scrolled to, held until settled; its alignment: 0 start, 1 center, 2 end)
	var target = -1;
	var targetAlign = 0;

	public function new(?tag:String, estimate = 44.0) {
		super(tag ?? "virtual-list");
		heights = new HeightIndex(estimate);
		style.overflow = Scroll;
		before = new Spacer("before");
		after = new Spacer("after");
		append(before);
		append(after);
		semantics = ({role: ListBox} : Semantics);
		onKeyDown = key;
		onFocusIn = e -> {
			var r = rowOf(e.target);
			if (r != null && r.index != active) {
				active = r.index;
				tabStops();
			}
		};
		onClick = e -> {
			var r = rowOf(e.target);
			if (r != null && onRowActive != null) onRowActive(r.index);
		};
	}

	function set_fixedHeight(v:Float):Float {
		fixedHeight = v;
		if (!Math.isNaN(v)) heights.estimate = v;
		for (s in slots)
			s.node.style.height = Math.isNaN(v) ? DimValue.Auto : (v : Dim);
		place();
		return v;
	}

	// --- the list's rows

	// n rows, none made or measured (a new list)
	public function reset(n:Int) {
		for (s in slots.copy())
			drop(s);
		count = n;
		heights.reset(n);
		active = -1;
		target = -1;
		anchorRow = 0;
		anchorDelta = 0;
		scrollY = 0;
		seenScroll = 0;
		place();
	}

	// removed rows from start replaced by inserted rows (not measured); moved:
	// for each row removed, where it is among those inserted (-1: gone), its
	// row and its height kept there. The anchor, the active row and a row
	// scrolled to go with their rows (one taken out: where it was).
	public function splice(start:Int, removed:Int, inserted:Int, ?moved:Array<Int>) {
		if (start < 0 || removed < 0 || inserted < 0 || start + removed > count) throw 'VirtualScroll.splice: $removed from $start of $count';
		if (removed == 0 && inserted == 0) return;
		var kept:Null<Array<Float>> = null;
		if (moved != null) {
			kept = [];
			for (k in 0...removed)
				kept.push(moved[k] >= 0 && heights.isMeasured(start + k) ? heights.heightOf(start + k) : -1);
		}
		function map(i:Int):Int {
			if (i < start) return i;
			if (i >= start + removed) return i + inserted - removed;
			var to = moved == null ? -1 : moved[i - start];
			return to >= 0 ? start + to : -1;
		}
		heights.remove(start, removed);
		heights.insert(start, inserted);
		count += inserted - removed;
		if (kept != null)
			for (k in 0...removed)
				if (kept[k] >= 0) heights.set(start + moved[k], kept[k]);
		// (the rows made: moved with theirs, let go with theirs)
		var order = false;
		for (s in slots.copy()) {
			var to = map(s.index);
			if (to < 0) drop(s) else {
				s.index = to;
				order = true;
			}
		}
		if (order && moved != null) {
			slots.sort((a, b) -> a.index - b.index);
			reorder(1, [for (s in slots) s.node]);
		}
		var a = map(anchorRow);
		// (its row taken out: the row now where it was, among those put there, else the next)
		if (a < 0) {
			var k = anchorRow - start;
			anchorRow = start + (k < inserted ? k : inserted);
			if (anchorRow >= count) anchorRow = count - 1;
		} else anchorRow = a;
		if (anchorRow < 0) anchorRow = 0;
		if (active >= 0) active = map(active);
		if (target >= 0) target = map(target);
		follow();
		place();
	}

	// the rows made (by index, in order): their nodes and what the source keeps
	public function rows():Array<VirtualRow>
		return slots;

	// row index measured again when next shown (its content changed: it
	// may be shorter than it was)
	public function remeasure(index:Int) {
		var r = rowAt(index);
		if (r != null && Math.isNaN(fixedHeight)) r.node.style.minHeight = 0;
	}

	// the made row of index (null: not made)
	public function rowAt(index:Int):Null<VirtualRow> {
		var k = seek(index);
		return k < slots.length && slots[k].index == index ? slots[k] : null;
	}

	// the row a node is in (null: none of this list's)
	public function rowOf(n:Null<Node>):Null<VirtualRow> {
		while (n != null && n.parent != this)
			n = n.parent;
		if (n == null) return null;
		for (s in slots)
			if (s.node == n) return s;
		return null;
	}

	// the first and last rows in view (-1: none)
	@:typescript public function firstVisible():Int
		return count == 0 ? -1 : heights.rowAt(scrollY);

	@:typescript public function lastVisible():Int {
		if (count == 0) return -1;
		var y = scrollY + viewHeight();
		var r = heights.rowAt(y);
		// (a row starting at the view's end is not in it)
		return r > 0 && heights.offsetOf(r) >= y ? r - 1 : r;
	}

	// --- scrolling and focus

	// scrolls to row index ("start", "center", "end"; "auto": as little as
	// shows it), made or not, held there while the rows are measured
	@:typescript public function scrollToIndex(index:Int, align = "auto") {
		if (count == 0) return;
		index = index < 0 ? 0 : index >= count ? count - 1 : index;
		var a = switch align {
			case "start": 0;
			case "center": 1;
			case "end": 2;
			case _:
				var top = heights.offsetOf(index), bottom = top + heights.heightOf(index);
				if (top >= scrollY && bottom <= scrollY + viewHeight()) -1 else top < scrollY ? 0 : 2;
		}
		if (a < 0) return;
		target = index;
		targetAlign = a;
		follow();
		place();
		if (ui != null) ui.requestFrame();
	}

	// focuses row index (made, scrolled into view first), the focus ring shown
	@:typescript public function focusIndex(index:Int) {
		if (count == 0) return;
		index = index < 0 ? 0 : index >= count ? count - 1 : index;
		scrollToIndex(index);
		active = index;
		place();
		var r = rowAt(index);
		if (r != null && ui != null) {
			ui.focusVisible = true;
			ui.setFocus(r.node, false);
		}
	}

	// (the keyboard on a row)
	function key(e:Event) {
		if (e.defaultPrevented || e.mods & (Key.MOD_CONTROL | Key.MOD_META | Key.MOD_ALT) != 0) return;
		var r = rowOf(e.target);
		if (r == null) return;
		var i = r.index, to = -1;
		switch e.key {
			case Key.UP: to = i - 1;
			case Key.DOWN: to = i + 1;
			case Key.HOME: to = 0;
			case Key.END: to = count - 1;
			case Key.PAGE_UP: to = heights.rowAt(heights.offsetOf(i) - viewHeight());
			case Key.PAGE_DOWN: to = heights.rowAt(heights.offsetOf(i) + viewHeight());
			case Key.ENTER | Key.SPACE:
				if (e.target != r.node || onRowActivate == null) return;
				onRowActivate(i);
				e.preventDefault();
				return;
			case _: return;
		}
		e.preventDefault();
		e.stop();
		if (to < 0 || to >= count) return;
		focusIndex(to);
		if (onRowActive != null) onRowActive(to);
	}

	// --- the window

	// (the view's height: its content box)
	// (the view's height: its content box; no more than the window's, a list
	// as tall as its rows (not bounded by its parent) making no more than fill it)
	function viewHeight():Float {
		var s = style;
		var h = height - s.borderEdges.vertical - s.padding.vertical;
		if (ui != null && h > ui.height) h = ui.height;
		return h > 0 ? h : 0;
	}

	// (the scroll the anchor or the row scrolled to asks for, clamped)
	function wanted():Float {
		var vh = viewHeight(), y:Float;
		if (target >= 0 && target < count) {
			var top = heights.offsetOf(target), h = heights.heightOf(target);
			y = switch targetAlign {
				case 1: top + h / 2 - vh / 2;
				case 2: top + h - vh;
				case _: top;
			}
		} else y = count == 0 ? 0 : heights.offsetOf(anchorRow) + anchorDelta;
		var max = heights.total() - vh;
		if (y > max) y = max;
		return y < 0 ? 0 : y;
	}

	// (scrolled where the anchor or the target says)
	function follow() {
		var y = wanted();
		if (y != scrollY) scrollY = y;
		seenScroll = scrollY;
		if (target >= 0) anchor();
	}

	// (the anchor taken from the scroll)
	function anchor() {
		if (count == 0) {
			anchorRow = 0;
			anchorDelta = 0;
			return;
		}
		anchorRow = heights.rowAt(scrollY);
		anchorDelta = scrollY - heights.offsetOf(anchorRow);
	}

	// the rows of the window made and shown, the others hidden (keep of them
	// kept, the farthest let go), the spacers sized; whether anything changed
	function place():Bool {
		var changed = false;
		var lo = 0, hi = 0;
		if (count > 0) {
			var vh = viewHeight();
			var a = heights.rowAt(scrollY), b = heights.rowAt(scrollY + vh);
			lo = a - overscan;
			hi = b + 1 + overscan;
			if (lo < 0) lo = 0;
			if (hi > count) hi = count;
		}
		if (lo != first || hi != end) changed = true;
		first = lo;
		end = hi;
		// (shown or hidden as they are in the window)
		var k = seek(lo);
		for (j in 0...slots.length) {
			var s = slots[j], on = s.index >= lo && s.index < hi;
			if (s.shown != on) {
				s.shown = on;
				s.node.style.display = on ? Flex : None;
				changed = true;
			}
		}
		// (the window's rows not made: made in place)
		for (i in lo...hi) {
			if (k < slots.length && slots[k].index == i) {
				k++;
				continue;
			}
			make(i, k);
			k++;
			changed = true;
		}
		// (the hidden over keep: the farthest from the window let go)
		var hidden = slots.length - (hi - lo);
		while (hidden > keep) {
			var far:Null<VirtualRow> = null, d = -1;
			for (s in slots) {
				if (s.shown || ui != null && ui.focus != null && within(s.node, ui.focus)) continue;
				var e = s.index < lo ? lo - s.index : s.index - hi + 1;
				if (e > d) {
					d = e;
					far = s;
				}
			}
			if (far == null) break;
			drop(far);
			hidden--;
		}
		var top = heights.offsetOf(lo), bottom = heights.total() - heights.offsetOf(hi);
		if (setHeight(before, top)) changed = true;
		if (setHeight(after, bottom)) changed = true;
		for (s in slots)
			semanticsOf(s);
		tabStops();
		return changed;
	}

	static function setHeight(n:Spacer, h:Float):Bool {
		if (n.extent == h) return false;
		n.extent = h;
		n.markDirty();
		return true;
	}

	static function within(a:Node, b:Node):Bool {
		var n = b;
		while (n != null) {
			if (n == a) return true;
			n = n.parent;
		}
		return false;
	}

	// (the first made row at index or after: where index's goes)
	function seek(index:Int):Int {
		var lo = 0, hi = slots.length;
		while (lo < hi) {
			var m = (lo + hi) >> 1;
			if (slots[m].index < index) lo = m + 1 else hi = m;
		}
		return lo;
	}

	// (row i made at slot k)
	function make(i:Int, k:Int) {
		var n = new Node("row");
		n.style.shrink = 0;
		if (!Math.isNaN(fixedHeight)) n.style.height = fixedHeight;
		var s = new VirtualRow(i, n);
		slots.insert(k, s);
		// (after the spacer before and the rows before it)
		insert(n, k + 1);
		semanticsOf(s);
		made++;
		if (onMakeRow != null) s.data = onMakeRow(i, n);
	}

	// (a row let go)
	function drop(s:VirtualRow) {
		slots.remove(s);
		remove(s.node);
		dropped++;
		if (onDropRow != null) onDropRow(s.node, s.data);
	}

	// (a row's place among all, its role)
	function semanticsOf(s:VirtualRow) {
		if (rowRole == null) return;
		var sem = s.node.semantics;
		if (sem == null) s.node.semantics = sem = ({role: rowRole} : Semantics);
		sem.role = rowRole;
		sem.posInSet = s.index + 1;
		sem.setSize = count;
	}

	// (Tab stops on the active row, else the window's first)
	function tabStops() {
		var stop = active >= 0 && rowAt(active) != null ? active : first;
		for (s in slots) {
			if (s.node.focusable != focusableRows) s.node.focusable = focusableRows;
			s.node.tabIndex = s.index == stop ? 0 : -1;
		}
	}

	// after a layout: the rows shown measured, the scroll kept on its anchor
	// (or its target), the window moved; whether it changed anything
	override function settle():Bool {
		if (ui == null) return false;
		// (the scroll moved since: by the user, a new anchor; a target given up)
		if (scrollY != seenScroll) {
			target = -1;
			anchor();
			seenScroll = scrollY;
		}
		var changed = false;
		if (Math.isNaN(fixedHeight))
			for (s in slots) {
				if (!s.shown) continue;
				// (whole pixels: a row's height taken up to the next (its
				// min-height), so that the rows' edges are whole pixels apart
				// and stay where they are as rows above change, the layout
				// rounding each edge where it is drawn)
				var raw = @:privateAccess s.node.lh, h = Math.fceil(raw - 1 / 128);
				if (h != raw) {
					s.node.style.minHeight = h;
					changed = true;
				}
				if (!heights.isMeasured(s.index) || heights.heightOf(s.index) != h) {
					heights.set(s.index, h);
					changed = true;
				}
			}
		if (changed && adaptive && heights.measuredCount > 0) {
			// (whole pixels: the offsets as the layout rounds them)
			var m = Math.round(heights.mean());
			if (m != heights.estimate) heights.estimate = m;
		}
		var y = wanted();
		if (y != scrollY) {
			scrollY = y;
			changed = true;
		}
		seenScroll = scrollY;
		if (place()) changed = true;
		// (settled on the target: held no more, the anchor from where it is)
		if (!changed && target >= 0) {
			target = -1;
			anchor();
		}
		return changed;
	}

	override function attach(u:Null<Ui>) {
		if (ui != null && ui != u) ui.settlers.remove(this);
		super.attach(u);
		if (u != null && u.settlers.indexOf(this) < 0) u.settlers.push(this);
	}
}

// a row of a VirtualScroll made: its index, its node, what its source keeps
@:allow(helder.ui.VirtualScroll)
class VirtualRow {
	public var index(default, null):Int;
	public final node:Node;
	public var data(default, null):Dynamic = null;
	// (in the window: shown)
	var shown = true;

	function new(index:Int, node:Node) {
		this.index = index;
		this.node = node;
	}
}

// (a spacer as tall as the rows it stands for: its content's height, set
// without a style's value made each time)
private class Spacer extends Node {
	public var extent = 0.0;

	public function new(tag:String) {
		super(tag);
		style.shrink = 0;
	}

	override public function hasContent():Bool
		return true;

	override public function measureContent(text:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size
		return new Size(0, extent);
}
