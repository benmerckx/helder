package helder.typescript.js;

// JavaScript values: undefined is Seed.undefinedValue, null is null, numbers
// are Float, strings String, booleans Bool; everything else is a JsObject.
class Hole {
	public function new() {}
}

class Accessor {
	public var getter:Dynamic;
	public var setter:Dynamic;
	public function new(getter:Dynamic, setter:Dynamic) {
		this.getter = getter;
		this.setter = setter;
	}
}

// Property attributes other than the default (enumerable, writable, configurable).
class Attr {
	public static inline var HIDDEN = 1;
	public static inline var READONLY = 2;
	public static inline var LOCKED = 4;
}

class JsObject {
	public var proto:JsObject;
	// own string-keyed properties in insertion order; accessor properties hold an Accessor
	public var names:Array<String> = null;
	public var slots:Map<String, Dynamic> = null;
	public var attrs:Map<String, Int> = null;
	// class-private elements, keyed by brand ("#name@class")
	public var privates:Map<String, Dynamic> = null;
	public var extensible = true;
	// an instance of a typed class (helder.typescript.lower): its declared
	// fields in slots of its own, before the others
	public var layout:Layout = null;

	public function new(proto:JsObject) {
		this.proto = proto;
	}

	public inline function hasOwn(k:String):Bool
		return layout != null && layout.index.exists(k) || slots != null && slots.exists(k);

	// an own property's value (an Accessor for an accessor property); hasOwn(k) first
	public function getOwn(k:String):Dynamic {
		if (layout != null) {
			var i = layout.index.get(k);
			if (i != null) return layout.get(this, i);
		}
		return slots.get(k);
	}

	// an own property's names, in order
	public function ownNames():Array<String>
		return layout == null ? names : names == null ? layout.names : layout.names.concat(names);

	public inline function attr(k:String):Int return attrs == null || !attrs.exists(k) ? 0 : attrs.get(k);

	public function setOwn(k:String, v:Dynamic, attribute:Int = 0):Void {
		writeOwn(k, v);
		if (attribute != 0) {
			if (attrs == null) attrs = [];
			attrs.set(k, attribute);
		}
		else if (attrs != null && attrs.exists(k)) attrs.remove(k);
	}

	// an own property's value set, its attributes kept
	public function writeOwn(k:String, v:Dynamic):Void {
		if (layout != null) {
			var i = layout.index.get(k);
			if (i != null) {
				layout.set(this, i, v);
				return;
			}
		}
		if (slots == null) {
			slots = [];
			names = [];
		}
		if (!slots.exists(k)) names.push(k);
		slots.set(k, v);
	}

	public function removeOwn(k:String):Void {
		if (layout != null && layout.index.exists(k)) throw "TSHX005: a typed class's field deleted: " + k;
		if (slots == null || !slots.exists(k)) return;
		slots.remove(k);
		names.remove(k);
		if (attrs != null) attrs.remove(k);
	}

	// [[Class]]-like tag for Object.prototype.toString and inspection
	public function tag():String return "Object";
}

// A typed class's fields (the frontend's typed classes): their names in
// definition order, and its code that reads and writes them by number.
class Layout {
	public final names:Array<String>;
	public final index:Map<String, Int> = [];
	public final get:(JsObject, Int) -> Dynamic;
	public final set:(JsObject, Int, Dynamic) -> Void;

	public function new(names:Array<String>, get:(JsObject, Int) -> Dynamic, set:(JsObject, Int, Dynamic) -> Void) {
		this.names = names;
		for (i in 0...names.length) index.set(names[i], i);
		this.get = get;
		this.set = set;
	}
}

// Arrays keep elements densely (holes are Lib.hole); indices too far past the
// end live in slots like other properties.
class JsArray extends JsObject {
	public var items:Array<Dynamic> = [];
	public var length:Float = 0;
	override public function tag():String return "Array";
}

class JsFunction extends JsObject {
	public static inline var PLAIN = 0; // function: callable and constructible
	public static inline var METHOD = 1; // arrow, method or accessor: callable only
	public static inline var BASE = 2; // class without extends: constructible only
	public static inline var DERIVED = 3; // class with extends
	public var kind:Int;
	// compiled code: (this, args...) for functions, (this, newTarget, args...) for classes
	public var impl:Dynamic;
	// a built-in: (this, args, newTarget) -> result
	public var native:(Dynamic, Array<Dynamic>, Dynamic) -> Dynamic;
	public var arity:Int;
	public var rest:Bool;
	public var deletedSpecial:Map<String, Bool> = null;
	public var name:String;
	// classes: the instance field initializer (this) -> Void, and the superclass
	public var fields:Dynamic;
	public var parent:Dynamic;
	// a typed class (helder.typescript.lower): its instances' layout, and
	// what makes one (an instance of its own hxmc class) from a prototype
	public var instanceLayout:Layout = null;
	public var alloc:JsObject->JsObject = null;
	public function new(proto:JsObject, kind:Int, name:String, arity:Int) {
		super(proto);
		this.kind = kind;
		this.name = name;
		this.arity = arity;
	}

	override public function tag():String return "Function";
}

class JsError extends JsObject {
	override public function tag():String return "Error";
}

class JsMap extends JsObject {
	public var keys:Array<Dynamic> = [];
	public var values:Array<Dynamic> = [];
	public var active:Array<Bool> = [];
	public var isSet:Bool;
	// (a WeakMap or WeakSet: same representation, its own methods)
	public var weak = false;
	// (lookup indexes: primitive keys by encoding, objects and symbols by identity)
	public var primitiveIndex:Map<String, Int> = null;
	public var objectIndex:haxe.ds.ObjectMap<Dynamic, Int> = null;
	public function new(proto:JsObject, isSet:Bool) {
		super(proto);
		this.isSet = isSet;
	}

	override public function tag():String return isSet ? "Set" : "Map";
}

// Built-in iterators over arrays, strings, maps and sets.
class JsIterator extends JsObject {
	public var target:Dynamic;
	public var index:Float = 0;
	public var kind:String;
	public var finished = false;
	public function new(proto:JsObject, target:Dynamic, kind:String) {
		super(proto);
		this.target = target;
		this.kind = kind;
	}
}
