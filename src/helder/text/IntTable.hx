package helder.text;

import haxe.ds.Vector;

// Int keys to values, for the caches read per glyph (GlyphAtlas's glyphs,
// FontFile's kerning and lookups): open addressing with linear probing, no
// removals, any key but 0x80000000 (an empty slot's). (hxmc's IntMap.get allocates on every call;
// this reads two arrays, and is made for each type: Ints unboxed.)
@:generic
class IntTable<T> {
	var keys:Vector<Int>;
	var values:Vector<T>;
	var count = 0;
	var mask:Int;

	public function new() {
		alloc(16);
	}

	function alloc(n:Int) {
		keys = new Vector(n);
		values = new Vector(n);
		for (i in 0...n)
			keys[i] = 0x80000000;
		mask = n - 1;
	}

	inline function slot(k:Int):Int {
		var h = k * 0x9E3779B1;
		return (h ^ (h >>> 15)) & mask;
	}

	// the value at k (missing: none)
	public function get(k:Int, missing:T):T {
		var i = slot(k);
		while (true) {
			var x = keys[i];
			if (x == k) return values[i];
			if (x == 0x80000000) return missing;
			i = (i + 1) & mask;
		}
	}

	public function set(k:Int, v:T) {
		var i = slot(k);
		while (true) {
			var x = keys[i];
			if (x == k) {
				values[i] = v;
				return;
			}
			if (x == 0x80000000) break;
			i = (i + 1) & mask;
		}
		keys[i] = k;
		values[i] = v;
		if (++count * 2 > mask) grow();
	}

	function grow() {
		var ks = keys, vs = values;
		alloc((mask + 1) * 2);
		count = 0;
		for (i in 0...ks.length)
			if (ks[i] != 0x80000000) set(ks[i], vs[i]);
	}
}
