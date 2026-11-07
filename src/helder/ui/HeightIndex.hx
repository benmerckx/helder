package helder.ui;

import haxe.io.Bytes;

// A long list's rows' heights (VirtualScroll's): a sum tree over the rows,
// each measured (its height) or not yet (the estimate's, which can change:
// every row not measured follows it). The rows are in leaves of up to LEAF
// rows; a Fenwick tree over the leaves sums their rows, their rows not
// measured and their measured heights, so a row's offset (offsetOf), the
// row at an offset (rowAt), a measure (set) and an insert or remove in the
// middle are O(log n) and a leaf's LEAF rows (a split or a leaf gone: the
// Fenwick tree built again over the leaves, n / LEAF). A leaf keeps its
// heights as 4 bytes a row (32-bit floats: a measure kept as it reads
// back), none while none of its rows is measured: a million rows never
// measured take under a byte a row, measured four and a half. Offsets are
// 64-bit sums. Nothing is allocated by a lookup, nor by a measure but a
// leaf's first.
class HeightIndex {
	static inline var LEAF = 128;
	// (a row not measured, in a leaf's heights)
	static inline var NONE = -1.0;

	// the rows
	public var length(default, null) = 0;
	// a row's height while it is not measured
	public var estimate:Float;
	// the rows measured, and their heights' sum
	public var measuredCount(default, null) = 0;
	public var measuredSum(default, null) = 0.0;

	// (the leaves: heights, NONE each not measured (null: none is), rows, rows not measured, measured heights' sum)
	final heights:Array<Null<Bytes>> = [];
	final rows:Array<Int> = [];
	final open:Array<Int> = [];
	final sums:Array<Float> = [];
	var leaves = 0;
	// (the Fenwick tree over the leaves, from 1: rows, rows not measured, measured sums)
	final fRows:Array<Int> = [0];
	final fOpen:Array<Int> = [0];
	final fSums:Array<Float> = [0.0];
	// (the highest power of two up to leaves: the descents' first step)
	var top = 0;
	// (locate's answer: the row's place in its leaf; prefix's: the leaves' before one)
	var local = 0;
	var preRows = 0;
	var preOpen = 0;
	var preSum = 0.0;

	public function new(estimate:Float, length = 0) {
		this.estimate = estimate;
		reset(length);
	}

	// every row's height together (the list's extent)
	public inline function total():Float
		return measuredSum + (length - measuredCount) * estimate;

	// the measured rows' mean height (the estimate's when none is)
	public function mean():Float
		return measuredCount == 0 ? estimate : measuredSum / measuredCount;

	// n rows, none measured
	public function reset(n:Int) {
		heights.resize(0);
		rows.resize(0);
		open.resize(0);
		sums.resize(0);
		var left = n;
		while (left > 0) {
			var k = left < LEAF ? left : LEAF;
			heights.push(null);
			rows.push(k);
			open.push(k);
			sums.push(0);
			left -= k;
		}
		length = n;
		measuredCount = 0;
		measuredSum = 0;
		rebuild();
	}

	// where row i starts (i == length: the end)
	public function offsetOf(i:Int):Float {
		if (i <= 0) return 0;
		if (i >= length) return total();
		var j = locate(i);
		prefix(j);
		var y = preSum + preOpen * estimate, h = heights[j];
		if (h == null) return y + local * estimate;
		for (k in 0...local) {
			var v = h.getFloat(k << 2);
			y += v < 0 ? estimate : v;
		}
		return y;
	}

	// the row at offset y (its start up to before its end; above the first:
	// the first, past the last: the last); -1 when there is none
	public function rowAt(y:Float):Int {
		if (length == 0) return -1;
		if (y <= 0) return 0;
		if (y >= total()) return length - 1;
		var pos = 0, start = 0, rem = y, step = top, est = estimate;
		while (step > 0) {
			var at = pos + step;
			if (at <= leaves) {
				var v = fSums[at] + fOpen[at] * est;
				if (v <= rem) {
					pos = at;
					rem -= v;
					start += fRows[at];
				}
			}
			step >>= 1;
		}
		if (pos >= leaves) return length - 1;
		var h = heights[pos], n = rows[pos];
		if (h == null) {
			var k = est <= 0 ? 0 : Std.int(rem / est);
			return start + (k < n ? k : n - 1);
		}
		for (k in 0...n) {
			var v = h.getFloat(k << 2);
			if (v < 0) v = est;
			if (rem < v) return start + k;
			rem -= v;
		}
		return start + n - 1 < length ? start + n - 1 : length - 1;
	}

	// row i's height (measured, else the estimate)
	public function heightOf(i:Int):Float {
		var j = locate(i), h = heights[j];
		if (h == null) return estimate;
		var v = h.getFloat(local << 2);
		return v < 0 ? estimate : v;
	}

	// whether row i is measured
	public function isMeasured(i:Int):Bool {
		var j = locate(i), h = heights[j];
		return h != null && h.getFloat(local << 2) >= 0;
	}

	// row i measured at height (at least 0); what its height was
	public function set(i:Int, height:Float):Float {
		if (i < 0 || i >= length) throw 'HeightIndex.set: row $i of $length';
		if (!(height >= 0)) height = 0;
		var j = locate(i), h = heights[j];
		if (h == null) heights[j] = h = blank();
		var p = local << 2, was = h.getFloat(p);
		h.setFloat(p, height);
		var v = h.getFloat(p);
		if (was < 0) {
			open[j]--;
			sums[j] += v;
			measuredCount++;
			measuredSum += v;
			add(j, 0, -1, v);
			return estimate;
		}
		if (v != was) {
			sums[j] += v - was;
			measuredSum += v - was;
			add(j, 0, 0, v - was);
		}
		return was;
	}

	// row i not measured again (the estimate's)
	public function forget(i:Int) {
		var j = locate(i), h = heights[j];
		if (h == null) return;
		var p = local << 2, was = h.getFloat(p);
		if (was < 0) return;
		h.setFloat(p, NONE);
		open[j]++;
		sums[j] -= was;
		measuredCount--;
		measuredSum -= was;
		add(j, 0, 1, -was);
	}

	// count rows not measured before row i (i == length: at the end)
	public function insert(i:Int, count:Int) {
		if (count <= 0) return;
		if (i < 0 || i > length) throw 'HeightIndex.insert: at $i of $length';
		if (leaves == 0) {
			reset(count);
			return;
		}
		var j:Int, at:Int;
		if (i == length) {
			j = leaves - 1;
			at = rows[j];
		} else {
			j = locate(i);
			at = local;
		}
		length += count;
		var n = rows[j], h = heights[j];
		if (n + count <= LEAF) {
			// (in its leaf: the rows after moved on)
			if (h != null) {
				var k = n - 1;
				while (k >= at) {
					h.setFloat((k + count) << 2, h.getFloat(k << 2));
					k--;
				}
				for (k in at...at + count)
					h.setFloat(k << 2, NONE);
			}
			rows[j] = n + count;
			open[j] += count;
			add(j, count, count, 0);
			return;
		}
		var before = [for (k in 0...at) valueAt(h, k)], after = [for (k in at...n) valueAt(h, k)];
		heights.splice(j, 1);
		rows.splice(j, 1);
		open.splice(j, 1);
		sums.splice(j, 1);
		if (count + n <= 2 * LEAF) {
			// (its leaf split in two: the rows before, the new ones, the rows after)
			var vals = before;
			for (_ in 0...count)
				vals.push(NONE);
			for (v in after)
				vals.push(v);
			var half = vals.length >> 1;
			put(put(j, vals.slice(0, half)), vals.slice(half));
		} else {
			// (the rows before, full leaves of new ones (no heights), the rows after)
			var w = put(j, before), left = count;
			while (left > 0) {
				var k = left < LEAF ? left : LEAF;
				heights.insert(w, null);
				rows.insert(w, k);
				open.insert(w, k);
				sums.insert(w, 0);
				w++;
				left -= k;
			}
			put(w, after);
		}
		rebuild();
	}

	// count rows from row i taken out
	public function remove(i:Int, count:Int) {
		if (count <= 0) return;
		if (i < 0 || i + count > length) throw 'HeightIndex.remove: $count from $i of $length';
		var j = locate(i), at = local, structural = false;
		while (count > 0) {
			var n = rows[j], take = n - at < count ? n - at : count, h = heights[j];
			var dOpen = 0, dSum = 0.0;
			if (h == null) dOpen = take else {
				for (k in at...at + take) {
					var v = h.getFloat(k << 2);
					if (v < 0) dOpen++ else dSum += v;
				}
				for (k in at + take...n)
					h.setFloat((k - take) << 2, h.getFloat(k << 2));
			}
			rows[j] = n - take;
			open[j] -= dOpen;
			sums[j] -= dSum;
			measuredCount -= take - dOpen;
			measuredSum -= dSum;
			length -= take;
			count -= take;
			// (a leaf emptied: dropped, the tree built again)
			if (take == n) structural = true else if (!structural) add(j, -take, -dOpen, -dSum);
			j++;
			at = 0;
		}
		if (structural) rebuild();
		if (measuredCount == 0) measuredSum = 0;
	}

	static inline function valueAt(h:Null<Bytes>, k:Int):Float
		return h == null ? NONE : h.getFloat(k << 2);

	// what it holds, in bytes (about: its arrays and the leaves' heights)
	public function bytes():Int {
		var b = leaves * 2 * (8 + 4 + 4 + 8);
		for (h in heights)
			if (h != null) b += h.length + 16;
		return b + 128;
	}

	// --- the leaves

	// (a leaf's heights, none measured)
	static function blank():Bytes {
		var b = Bytes.alloc(LEAF << 2);
		for (k in 0...LEAF)
			b.setFloat(k << 2, NONE);
		return b;
	}

	// (heights vals as leaves at w, up to LEAF each: the place after them)
	function put(w:Int, vals:Array<Float>):Int {
		var k = 0;
		while (k < vals.length) {
			var n = vals.length - k < LEAF ? vals.length - k : LEAF;
			var h:Null<Bytes> = null, o = 0, s = 0.0;
			for (x in k...k + n) {
				var v = vals[x];
				if (v < 0) o++ else {
					if (h == null) h = blank();
					h.setFloat((x - k) << 2, v);
					s += v;
				}
			}
			heights.insert(w, h);
			rows.insert(w, n);
			open.insert(w, o);
			sums.insert(w, s);
			w++;
			k += n;
		}
		return w;
	}

	// (the leaf of row i, its place in it in local)
	function locate(i:Int):Int {
		if (i < 0 || i >= length) throw 'HeightIndex: row $i of $length';
		var pos = 0, rem = i, step = top;
		while (step > 0) {
			var at = pos + step;
			if (at <= leaves && fRows[at] <= rem) {
				pos = at;
				rem -= fRows[at];
			}
			step >>= 1;
		}
		local = rem;
		return pos;
	}

	// (the sums of the leaves before leaf j)
	function prefix(j:Int) {
		var r = 0, o = 0, s = 0.0, k = j;
		while (k > 0) {
			r += fRows[k];
			o += fOpen[k];
			s += fSums[k];
			k &= k - 1;
		}
		preRows = r;
		preOpen = o;
		preSum = s;
	}

	// (leaf j's sums changed by these)
	function add(j:Int, dRows:Int, dOpen:Int, dSum:Float) {
		var k = j + 1;
		while (k <= leaves) {
			fRows[k] += dRows;
			fOpen[k] += dOpen;
			fSums[k] += dSum;
			k += k & -k;
		}
	}

	// (the Fenwick tree over the leaves, built again; the empty leaves dropped)
	function rebuild() {
		var w = 0;
		for (j in 0...rows.length)
			if (rows[j] > 0) {
				heights[w] = heights[j];
				rows[w] = rows[j];
				open[w] = open[j];
				sums[w] = sums[j];
				w++;
			}
		heights.resize(w);
		rows.resize(w);
		open.resize(w);
		sums.resize(w);
		leaves = w;
		fRows.resize(w + 1);
		fOpen.resize(w + 1);
		fSums.resize(w + 1);
		fRows[0] = fOpen[0] = 0;
		fSums[0] = 0;
		for (k in 1...w + 1) {
			fRows[k] = rows[k - 1];
			fOpen[k] = open[k - 1];
			fSums[k] = sums[k - 1];
		}
		for (k in 1...w + 1) {
			var p = k + (k & -k);
			if (p <= w) {
				fRows[p] += fRows[k];
				fOpen[p] += fOpen[k];
				fSums[p] += fSums[k];
			}
		}
		top = 1;
		while (top * 2 <= w)
			top *= 2;
		if (w == 0) top = 0;
	}
}
