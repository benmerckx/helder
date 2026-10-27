package helder.scoped;

import haxe.io.Bytes;
import helder.scoped.Memory.*;

// A string in scoped memory: UTF-8 bytes and their length, immutable. The
// value is the address of a header (data, length) in the scope that made it.
// `Str.of(s)` copies a String in; `toString()` copies one out.
abstract Str(Addr) to Addr {
	static inline var DATA = 0;
	static inline var LEN = 4;
	static inline var MAGIC = 8;
	static inline var HEADER = 12;

	inline function new(h:Addr)
		this = h;

	// a view of n bytes at data (the trusted layer's)
	@:noCompletion public static function view(data:Addr, n:Int):Str {
		var h = Memory.alloc(HEADER);
		setI32(h, data);
		setI32(h + LEN, n);
		setI32(h + MAGIC, Header.MAGIC);
		return new Str(h);
	}

	// a copy of s, in the current scope
	@:from public static function of(s:String):Str {
		var b = Bytes.ofString(s);
		var d = Memory.alloc(b.length);
		write(d, b, 0, b.length);
		return view(d, b.length);
	}

	// a copy of n bytes at data, in the current scope
	@:noCompletion public static function copyOf(data:Addr, n:Int):Str {
		var d = Memory.alloc(n);
		copy(d, data, n);
		return view(d, n);
	}

	// the length in bytes
	public var length(get, never):Int;

	inline function get_length():Int
		return getI32(Header.check(this, MAGIC) + LEN);

	@:noCompletion public inline function data():Addr
		return getI32(Header.check(this, MAGIC));

	// byte i
	public inline function byteAt(i:Int):Int {
		var n = length;
		if (i < 0 || i >= n)
			outOfRange(i, n);
		return getU8(data() + i);
	}

	public inline function toString():String
		return string(data(), length);

	// bytes pos .. pos + len - 1, the same memory
	public function sub(pos:Int, len:Int):Str {
		if (pos < 0 || len < 0 || pos + len > length)
			outOfRange(pos + len, length);
		return view(data() + pos, len);
	}

	@:op(A == B) public function equals(o:Str):Bool {
		var n = length;
		if (o.length != n)
			return false;
		var a = data(), b = o.data();
		for (i in 0...n)
			if (getU8(a + i) != getU8(b + i))
				return false;
		return true;
	}

	// < 0, 0, > 0 as this sorts before, with or after o (by bytes: code points)
	public function compare(o:Str):Int {
		var n = length, m = o.length;
		var a = data(), b = o.data();
		for (i in 0...(n < m ? n : m)) {
			var d = getU8(a + i) - getU8(b + i);
			if (d != 0)
				return d;
		}
		return n - m;
	}

	// the byte index of the first `s` at or after `from`, or -1
	public function indexOf(s:Str, from = 0):Int {
		var n = length, m = s.length;
		var a = data(), b = s.data();
		var i = from < 0 ? 0 : from;
		while (i + m <= n) {
			var k = 0;
			while (k < m && getU8(a + i + k) == getU8(b + k))
				k++;
			if (k == m)
				return i;
			i++;
		}
		return -1;
	}

	public function startsWith(s:Str):Bool
		return s.length <= length && sub(0, s.length) == s;

	// FNV-1a over the bytes
	public function hash():Int {
		var h:haxe.Int32 = 0x811C9DC5, a = data();
		for (i in 0...length)
			h = (h ^ getU8(a + i)) * 0x01000193;
		return h;
	}

	// a and b one after the other, in the current scope
	@:op(A + B) public static function concat(a:Str, b:Str):Str {
		var n = a.length, m = b.length;
		var d = Memory.alloc(n + m);
		copy(d, a.data(), n);
		copy(d + n, b.data(), m);
		return view(d, n + m);
	}
}
