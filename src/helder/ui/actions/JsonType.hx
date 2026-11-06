package helder.ui.actions;

// An action's argument's type as a JSON keymap gives it (made by actions'
// handler, ActionsDefinition, from either language's types): what reads it
// (JsonTypes.read: a keymap's ["viewer::ZoomTo", 100], checked and made the
// argument), what compares two (equal), and its description as data
// (TypeScript's lowering passes it as JSON: toData, ofData).
enum JsonType {
	// (a number: Haxe's Float, TypeScript's number)
	JNumber;
	// (a whole number: Haxe's Int)
	JInt;
	JString;
	JBool;
	// (T, or null)
	JNull(t:JsonType);
	JArray(t:JsonType);
	JFields(fields:Array<JsonField>);
}

// (classes, not structures: their fields read directly, never by name)
class JsonField {
	public final name:String;
	public final type:JsonType;
	public final optional:Bool;

	public function new(name, type, optional) {
		this.name = name;
		this.type = type;
		this.optional = optional;
	}
}

// an action: its keymap name (ZoomTo: viewer::ZoomTo), its value's type in
// TypeScript (zoomTo), its arguments
class ActionInfo {
	public final name:String;
	public final type:String;
	public final params:Array<ParamInfo>;

	public function new(name, type, params) {
		this.name = name;
		this.type = type;
		this.params = params;
	}
}

class ParamInfo {
	public final name:String;
	public final type:JsonType;

	public function new(name, type) {
		this.name = name;
		this.type = type;
	}
}

// The readers of a JSON keymap's arguments: Haxe's actions' are generated
// for their types (ActionsMacro: these for its numbers, strings, booleans
// and arrays, an object's fields read by their names as written there),
// TypeScript's checked (check: a program's objects are as JSON gives them).
// No field is read by a name made at run time: that would keep every
// class's fields and methods in the program.
class JsonTypes {
	public static function number(v:Dynamic, what:String):Float {
		if (Std.isOfType(v, Int)) return (v : Int);
		if (Std.isOfType(v, Float)) return v;
		return no(what, "a number");
	}

	public static function int(v:Dynamic, what:String):Int {
		if (Std.isOfType(v, Int)) return v;
		if (Std.isOfType(v, Float) && Math.ffloor(v) == v && Math.abs(v) < 2147483648.0) return Std.int(v);
		return no(what, "a whole number");
	}

	public static function string(v:Dynamic, what:String):String
		return Std.isOfType(v, String) ? v : no(what, "a string");

	public static function bool(v:Dynamic, what:String):Bool
		return Std.isOfType(v, Bool) ? v : no(what, "a boolean");

	public static function array(v:Dynamic, what:String):Array<Dynamic>
		return Std.isOfType(v, Array) ? v : no(what, "an array");

	public static function object(v:Dynamic, what:String):Dynamic
		return v != null && !Reflect.isFunction(v) && Type.typeof(v) == TObject ? v : no(what, "an object");

	static function no(what:String, want:String):Dynamic
		throw 'helder.ui: $what is $want';

	// (two arrays the same, element by element)
	public static function sameArrays(a:Array<Dynamic>, b:Array<Dynamic>, same:(Dynamic, Dynamic) -> Bool):Bool {
		if (a == null || b == null) return a == b;
		if (a.length != b.length) return false;
		for (i in 0...a.length)
			if (!same(a[i], b[i])) return false;
		return true;
	}

	// v checked as an argument of type t (TypeScript's, whose numbers are
	// all numbers), as it is: an object's fields found among those it has
	public static function check(t:JsonType, v:Dynamic, what:String):Dynamic {
		switch t {
			case JNull(_) if (v == null):
			case JNull(t): check(t, v, what);
			case JNumber: number(v, what);
			case JInt: int(v, what);
			case JString: string(v, what);
			case JBool: bool(v, what);
			case JArray(e):
				var a = array(v, what);
				for (i in 0...a.length)
					check(e, a[i], '$what[$i]');
			case JFields(fs):
				object(v, what);
				var names = Reflect.fields(v);
				for (f in fs) {
					var x:Dynamic = null;
					for (n in names)
						if (n == f.name) x = Reflect.field(v, n);
					if (x == null && (f.optional || f.type.match(JNull(_)))) continue;
					if (x == null) throw 'helder.ui: $what needs a field ${f.name}';
					check(f.type, x, '$what.${f.name}');
				}
		}
		return v;
	}
	// as data (JSON): "number", "int", "string", "boolean", {null: t}, {array: t}, {fields: [{name, type, optional}]}
	public static function toData(t:JsonType):Dynamic
		return switch t {
			case JNumber: "number";
			case JInt: "int";
			case JString: "string";
			case JBool: "boolean";
			case JNull(t): {"null": toData(t)};
			case JArray(t): {array: toData(t)};
			case JFields(fs): {fields: [for (f in fs) {name: f.name, type: toData(f.type), optional: f.optional}]};
		}

	public static function ofData(d:Dynamic):JsonType {
		if (Std.isOfType(d, String))
			return switch (d : String) {
				case "number": JNumber;
				case "int": JInt;
				case "string": JString;
				case "boolean": JBool;
				case s: throw "helder.ui: not an argument's type: " + s;
			}
		var n:Dynamic = Reflect.field(d, "null");
		if (n != null) return JNull(ofData(n));
		var a:Dynamic = Reflect.field(d, "array");
		if (a != null) return JArray(ofData(a));
		var fs:Array<Dynamic> = Reflect.field(d, "fields");
		return JFields([for (f in fs) new JsonField(f.name, ofData(f.type), f.optional == true)]);
	}
}
