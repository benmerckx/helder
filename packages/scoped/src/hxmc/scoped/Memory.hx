package hxmc.scoped;

import haxe.ds.Vector;
import haxe.io.Bytes;

// Scoped memory: 16 buffers (Store, one implementation per target), as
// hxmc's data stacks are 16 reservations. Buffer 0 is the fixed stack:
// everything that does not grow (a Slice's memory, the headers of Slices,
// Grows and Strs) is bumped there. A Grow claims one of the others for its
// elements, so growing one never moves another's; a buffer that fills up is
// reallocated larger, which is safe because addresses are offsets (Addr),
// never host pointers.
//
// A scope is a mark (Scope.enter): the fixed stack's top and the claimed
// buffers. Leaving it (Scope.exit) puts the top back and releases the
// buffers claimed since: everything the scope allocated is freed by a few
// stores, however much it holds. Marks nest; leaving an outer mark leaves
// every inner one, so a mark skipped by an exception is left with its
// enclosing scope.
//
// Single-threaded: one set of buffers per program (a thread-local set per
// thread is the next step for threaded targets).
class Memory {
	public static inline var BUFFERS = 16;
	public static inline var SHIFT = 27;
	public static inline var MASK = 0x07FFFFFF;

	// (initialized on first use: static initialization order across modules
	// is not something to rely on)
	static var tops:Vector<Int>;
	// bit i: buffer i is in use (bit 0, the fixed stack, always)
	static var claimed = 1;
	static var markTop:Vector<Int>;
	static var markClaimed:Vector<Int>;
	static var depth = 0;
	// the fixed stack's top (tops[0] in a variable of its own: read in every loop)
	static var top0 = 0;

	static function init() {
		Store.init(BUFFERS);
		tops = new Vector(BUFFERS);
		for (i in 0...BUFFERS)
			tops[i] = 0;
		Store.make(0, 1 << 16);
		markTop = new Vector(64);
		markClaimed = new Vector(64);
	}

	static inline function ready() {
		if (tops == null)
			init();
	}

	// --- allocation ---

	// n bytes of the current scope, zeroed, aligned to 8
	public static function alloc(n:Int):Addr {
		ready();
		if (depth == 0)
			fail("allocating outside any scope: mark the function @:scoped");
		if (n < 0)
			fail("negative size");
		var top = top0;
		var end = top + ((n + 7) & ~7);
		if (end > Store.capacity(0))
			grow(0, end);
		Store.fill(top, end - top, 0);
		top0 = end;
		return top;
	}

	// a buffer of its own (a Grow's), empty; its address is `index << SHIFT`
	public static function claim():Int {
		ready();
		if (depth == 0)
			fail("allocating outside any scope: mark the function @:scoped");
		for (i in 1...BUFFERS) {
			if (claimed & (1 << i) == 0) {
				claimed |= 1 << i;
				if (!Store.exists(i))
					Store.make(i, 1 << 12);
				tops[i] = 0;
				return i;
			}
		}
		return fail("more than " + (BUFFERS - 1) + " Grows live at once");
	}

	// the bytes buffer i holds before it has to grow
	public static inline function capacity(i:Int):Int
		return Store.capacity(i);

	// makes room for `end` bytes in buffer i, its contents kept
	public static function reserve(i:Int, end:Int) {
		if (end > Store.capacity(i))
			grow(i, end);
	}

	static function grow(i:Int, end:Int) {
		if (end > MASK + 1)
			fail("scoped memory full (buffer " + i + ": 256 MB)");
		var cap = Store.capacity(i);
		while (cap < end)
			cap = cap * 2 > MASK + 1 ? MASK + 1 : cap * 2;
		Store.grow(i, cap, Store.capacity(i));
	}

	// --- scopes ---

	public static function enter():Int {
		ready();
		if (depth == markTop.length) {
			var t = new Vector<Int>(depth * 2), c = new Vector<Int>(depth * 2);
			Vector.blit(markTop, 0, t, 0, depth);
			Vector.blit(markClaimed, 0, c, 0, depth);
			markTop = t;
			markClaimed = c;
		}
		markTop[depth] = top0;
		markClaimed[depth] = claimed;
		return depth++;
	}

	// frees what was allocated since mark d, which stays (a loop's iterations)
	public static function rewind(d:Int) {
		var top = markTop[d];
		#if scoped_debug
		// (freed memory overwritten: a value used after its scope reads
		// garbage, which the headers' checks catch: Header.check)
		if (top0 > top)
			Store.fill(top, top0 - top, 0xA5);
		#end
		top0 = top;
		claimed = markClaimed[d];
	}

	// a loop iteration's scope: what the previous iteration left is freed
	// when the fixed stack's top or the claimed Grows changed (a compare
	// when it did not)
	public static inline function top():Int
		return top0;

	// (the claimed Grows, and the depth above them: an exception caught in
	// the loop leaves the marks of the scopes it left, dropped here too)
	public static inline function claims():Int
		return claimed | depth << 16;

	// (returns true: the Scoped macro keeps it in a variable, `__iteration`,
	// which marks the iteration for the checker)
	public static inline function restore(t:Int, c:Int):Bool {
		// (the top alone: claiming a Grow allocates its header on the fixed
		// stack, so the top moves whenever anything was allocated)
		if (top0 != t)
			restoreSlow(t, c);
		return true;
	}

	static function restoreSlow(t:Int, c:Int) {
		#if scoped_debug
		if (top0 > t)
			Store.fill(t, top0 - t, 0xA5);
		#end
		top0 = t;
		claimed = c & 0xFFFF;
		if (depth > c >>> 16)
			depth = c >>> 16;
	}

	// leaves mark d (and every mark inside it)
	public static function exit(d:Int) {
		if (d >= depth)
			return;
		rewind(d);
		depth = d;
	}

	// --- what is in use ---

	public static function used():Int {
		ready();
		return top0;
	}

	public static function grows():Int {
		var n = 0;
		for (i in 1...BUFFERS)
			if (claimed & (1 << i) != 0)
				n++;
		return n;
	}

	// --- typed access (a: an Addr, checked against its buffer) ---

	public static inline function getI32(a:Int):Int
		return Store.getI32(a);

	public static inline function setI32(a:Int, v:Int)
		Store.setI32(a, v);

	public static inline function getF64(a:Int):Float
		return Store.getF64(a);

	public static inline function setF64(a:Int, v:Float)
		Store.setF64(a, v);

	public static inline function getU8(a:Int):Int
		return Store.getU8(a);

	public static inline function setU8(a:Int, v:Int)
		Store.setU8(a, v);

	public static inline function zero(a:Int, n:Int)
		Store.fill(a, n, 0);

	// n bytes from src to dst (they may overlap)
	public static inline function copy(dst:Int, src:Int, n:Int)
		Store.copy(dst, src, n);

	// the bytes at a as a String (UTF-8)
	public static inline function string(a:Int, n:Int):String
		return Store.string(a, n);

	// the bytes of b into memory at a
	public static inline function write(a:Int, b:Bytes, pos:Int, n:Int)
		Store.write(a, b, pos, n);

	// (cold: functions of their own, so the inline accessors stay small)
	public static function fail<T>(why:String):T
		throw new ScopedError(why);

	public static function outOfRange<T>(i:Int, n:Int):T
		throw new ScopedError('index $i out of range (length $n)');

	public static function outside(a:Int)
		fail("address " + a + " outside scoped memory");
}

class ScopedError extends haxe.Exception {}
