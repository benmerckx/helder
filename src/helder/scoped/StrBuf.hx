package helder.scoped;

import haxe.io.Bytes;
import helder.scoped.Memory.*;

// Builds a Str: bytes appended to a Grow of its own (so building never
// moves anything else), `toStr()` the result in the current scope.
abstract StrBuf(Grow<U8>) {
	public inline function new()
		this = Grow.make(1);

	public var length(get, never):Int;

	inline function get_length():Int
		return this.length;

	public function add(s:Str) {
		var n = s.length, a = s.data();
		for (i in 0...n)
			this.push(getU8(a + i));
	}

	public function addString(s:String) {
		var b = Bytes.ofString(s);
		for (i in 0...b.length)
			this.push(b.get(i));
	}

	public inline function addByte(b:Int)
		this.push(b);

	public function addInt(v:Int)
		addString(Std.string(v));

	public function toStr():Str
		return Str.copyOf(this.base(), this.length);

	public function toString():String
		return string(this.base(), this.length);
}
