package helder.scoped;

import haxe.ds.Vector;
import haxe.io.Bytes;

// Scoped memory: 32 buffers of up to 64 MB (Store, one implementation per
// target; -D scoped_buffer_bits=27, 28 or 29 makes 16 of 128 MB, 8 of 256
// MB or 4 of 512 MB), shared by the program's threads. Each thread bumps a buffer of
// its own, its stack: everything that does not grow (a Slice's memory, the
// headers of Slices, Grows and Strs). A Grow claims another for its
// elements, so growing one never moves another's; a buffer that fills up is
// made larger, which is safe because addresses are offsets (Addr), never
// host pointers. Buffer 0 is never used: no address is 0.
//
// A scope is the thread's stack top and the Grows it holds, kept in two
// locals by the Scoped macro: leaving it (leave, or a loop's restore) puts
// the top back and releases the Grows claimed since, so everything the scope
// allocated is freed by a few stores, however much it holds. A scope an
// exception skipped is left with the scope around it.
//
// A thread claims its stack when it enters its first scope and gives it
// back when it leaves it: outside every scope it holds nothing, and
// allocating there is an error.
//
// Per thread: the top and the Grows held. On hxmc they are thread-local
// statics (a load like any other). On the other threaded targets they are
// in a sys.thread.Tls with -D scoped_threads, which costs 1.4-2.5x on
// HashLink and the JVM; without it they are statics, and scoped memory is
// for one thread at a time. Claiming and releasing buffers takes a lock.
class Memory {
	// (-D scoped_buffer_bits=27, 28 or 29: fewer, larger buffers; 2 GB in all)
	public static inline var SHIFT = #if (scoped_buffer_bits == "27") 27 #elseif (scoped_buffer_bits == "28") 28 #elseif (scoped_buffer_bits == "29") 29 #else 26 #end;
	public static inline var BUFFERS = 1 << (31 - SHIFT);
	public static inline var MASK = (1 << SHIFT) - 1;

	// bit i: buffer i is claimed (bit 0 always: never used)
	static var claimed = 1;
	static var ready_ = false;
	#if target.threaded
	static var lock = new sys.thread.Mutex();
	#end

	// --- per thread: the stack's top (an Addr; 0 outside every scope) and
	// the Grows held (bit i: buffer i)

	#if (target.name == "hxmc")
	@:hxmc.threadLocal("hxmc_scoped_top") static var top0:Int;
	@:hxmc.threadLocal("hxmc_scoped_mine") static var mine:Int;

	static inline function getTop():Int
		return top0;

	static inline function setTop(v:Int)
		top0 = v;

	static inline function getMine():Int
		return mine;

	static inline function setMine(v:Int)
		mine = v;
	#elseif (target.threaded && scoped_threads)
	static var local = new sys.thread.Tls<State>();

	static inline function state():State {
		var s = local.value;
		return s != null ? s : newState();
	}

	static function newState():State {
		var s = new State();
		local.value = s;
		return s;
	}

	static inline function getTop():Int
		return state().top;

	static inline function setTop(v:Int)
		state().top = v;

	static inline function getMine():Int
		return state().mine;

	static inline function setMine(v:Int)
		state().mine = v;
	#else
	static var top0 = 0;
	static var mine = 0;

	static inline function getTop():Int
		return top0;

	static inline function setTop(v:Int)
		top0 = v;

	static inline function getMine():Int
		return mine;

	static inline function setMine(v:Int)
		mine = v;
	#end

	static inline function ready() {
		if (!ready_)
			init();
	}

	static function init() {
		lockPool();
		if (!ready_) {
			Store.init(BUFFERS);
			ready_ = true;
		}
		unlockPool();
	}

	static inline function lockPool() {
		#if target.threaded
		lock.acquire();
		#end
	}

	static inline function unlockPool() {
		#if target.threaded
		lock.release();
		#end
	}

	// --- allocation ---

	// n bytes of the current scope, zeroed, aligned to 8
	public static function alloc(n:Int):Addr {
		var top = getTop();
		if (top == 0)
			fail("allocating outside any scope: mark the function @:scoped");
		if (n < 0)
			fail("negative size");
		var end = top + ((n + 7) & ~7);
		var b = top >>> SHIFT;
		if (end - (b << SHIFT) > Store.capacity(b))
			grow(b, end - (b << SHIFT));
		Store.fill(top, end - top, 0);
		setTop(end);
		return top;
	}

	// a buffer of its own (a Grow's), empty; its address is `index << SHIFT`
	public static function claim():Int {
		if (getTop() == 0)
			fail("allocating outside any scope: mark the function @:scoped");
		var i = take();
		setMine(getMine() | 1 << i);
		return i;
	}

	// (a free buffer, claimed)
	static function take():Int {
		ready();
		lockPool();
		for (i in 1...Store.buffers()) {
			if (claimed & (1 << i) == 0) {
				claimed |= 1 << i;
				if (!Store.exists(i))
					Store.make(i, 1 << 12);
				unlockPool();
				return i;
			}
		}
		unlockPool();
		return fail("more than " + (Store.buffers() - 1) + " stacks and Grows live at once");
	}

	static function free(bits:Int) {
		lockPool();
		claimed &= ~bits;
		unlockPool();
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
			fail("scoped memory full (a buffer holds " + ((MASK + 1) >> 20) + " MB: -D scoped_buffer_bits makes them larger)");
		var cap = Store.capacity(i);
		while (cap < end)
			cap = cap * 2 > MASK + 1 ? MASK + 1 : cap * 2;
		Store.grow(i, cap, Store.capacity(i));
	}

	// --- scopes ---

	// a function's scope: the top to come back to (0: the thread's first
	// scope, which claims its stack)
	public static inline function enter():Int {
		var t = getTop();
		if (t == 0)
			first();
		return t;
	}

	static function first() {
		var i = take();
		// (8: no address is a buffer's start, so none is 0)
		setTop((i << SHIFT) + 8);
	}

	// leaves a function's scope: everything allocated since enter freed
	public static inline function leave(t:Int, c:Int) {
		if (getTop() != t || getMine() != c)
			leaveSlow(t, c);
	}

	static function leaveSlow(t:Int, c:Int) {
		var top = getTop();
		#if scoped_debug
		if (top != 0 && t != 0 && top > t)
			Store.fill(t, top - t, 0xA5);
		#end
		var gone = getMine() & ~c;
		if (t == 0 && top != 0)
			gone |= 1 << (top >>> SHIFT);
		if (gone != 0)
			free(gone);
		setTop(t);
		setMine(c);
	}

	// a loop iteration's scope: what the previous iteration left is freed
	// when the stack's top changed (a compare when it did not)
	public static inline function top():Int
		return getTop();

	public static inline function claims():Int
		return getMine();

	// (returns true: the Scoped macro keeps it in a variable, `__iteration`,
	// which marks the iteration for the checker)
	public static inline function restore(t:Int, c:Int):Bool {
		// (the top alone: claiming a Grow allocates its header on the stack,
		// so the top moves whenever anything was allocated)
		if (getTop() != t)
			leaveSlow(t, c);
		return true;
	}

	// --- what is in use ---

	// the bytes of the thread's stack in use
	public static function used():Int
		return getTop() & MASK;

	// the Grows the thread holds
	public static function grows():Int {
		var n = 0, m = getMine();
		for (i in 1...BUFFERS)
			if (m & (1 << i) != 0)
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

	// f32: stored in 4 bytes, read as a Float (rounded to f32 when stored)
	public static inline function getF32(a:Int):Float
		return Store.getF32(a);

	public static inline function setF32(a:Int, v:Float)
		Store.setF32(a, v);

	// at any byte address (the others want one aligned to their size): a
	// little-endian 32-bit Int, a 16-bit one unsigned or signed
	public static inline function getI32U(a:Int):Int
		return #if js getU8(a) | getU8(a + 1) << 8 | getU8(a + 2) << 16 | getU8(a + 3) << 24 #else Store.getI32(a) #end;

	public static inline function setI32U(a:Int, v:Int) {
		#if js
		setU8(a, v);
		setU8(a + 1, v >> 8);
		setU8(a + 2, v >> 16);
		setU8(a + 3, v >>> 24);
		#else
		Store.setI32(a, v);
		#end
	}

	public static inline function getU16(a:Int):Int
		return getU8(a) | getU8(a + 1) << 8;

	public static inline function getI16(a:Int):Int
		return (getU16(a) << 16) >> 16;

	public static inline function setI16(a:Int, v:Int) {
		setU8(a, v);
		setU8(a + 1, v >> 8);
	}

	public static inline function setU8(a:Int, v:Int)
		Store.setU8(a, v);

	public static inline function zero(a:Int, n:Int)
		Store.fill(a, n, 0);

	// <0, 0 or >0 as the n bytes at a sort before, as or after those at b
	public static function compare(a:Int, b:Int, n:Int):Int {
		#if (target.name == "hxmc" && !hxmc.wasm_gc && !(hxmc.target == "wasm32-wasi"))
		return Store.compare(a, b, n);
		#else
		for (k in 0...n) {
			var d = getU8(a + k) - getU8(b + k);
			if (d != 0)
				return d;
		}
		return 0;
		#end
	}

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

#if (target.threaded && scoped_threads && target.name != "hxmc")
private class State {
	public var top = 0;
	public var mine = 0;

	public function new() {}
}
#end
