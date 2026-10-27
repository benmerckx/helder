package helder.scoped;

import helder.scoped.Memory.*;

// A reference to one element of a Slice or a Grow (their `ref(i)`), rooted
// at what it refers into: `r.get()`, `r.set(v)`. A reference to a struct
// element is the struct itself (`r.get().x`).
@:using(helder.scoped.Ref.RefAnyOps, helder.scoped.Ref.RefBoolOps, helder.scoped.Ref.RefFloatOps, helder.scoped.Ref.RefIntOps, helder.scoped.Ref.RefU8Ops)
abstract Ref<T>(Addr) to Addr {}

class RefIntOps {
	public static inline function get(r:Ref<Int>):Int
		return getI32((r : Addr));

	public static inline function set(r:Ref<Int>, v:Int):Int {
		setI32((r : Addr), v);
		return v;
	}
}

class RefFloatOps {
	public static inline function get(r:Ref<Float>):Float
		return getF64((r : Addr));

	public static inline function set(r:Ref<Float>, v:Float):Float {
		setF64((r : Addr), v);
		return v;
	}
}

class RefBoolOps {
	public static inline function get(r:Ref<Bool>):Bool
		return getU8((r : Addr)) != 0;

	public static inline function set(r:Ref<Bool>, v:Bool):Bool {
		setU8((r : Addr), v ? 1 : 0);
		return v;
	}
}

class RefU8Ops {
	public static inline function get(r:Ref<U8>):U8
		return getU8((r : Addr));

	public static inline function set(r:Ref<U8>, v:U8):U8 {
		setU8((r : Addr), v);
		return v;
	}
}

class RefAnyOps {
	// the struct referred to, in place
	public static inline function get<T>(r:Ref<T>):T
		return cast(r : Addr);
}
