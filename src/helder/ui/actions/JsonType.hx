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

typedef JsonField = {name:String, type:JsonType, optional:Bool};

// an action: its keymap name (ZoomTo: viewer::ZoomTo), its value's type in
// TypeScript (zoomTo), its arguments
typedef ActionInfo = {name:String, type:String, params:Array<{name:String, type:JsonType}>};

class JsonTypes {
	// v (a JSON value: haxe.Json's, or a program's) as an argument of type t,
	// numbers made Int or Float as t says; throws where it is not one (what: where)
	public static function read(t:JsonType, v:Dynamic, what:String):Dynamic {
		inline function no(want:String):Dynamic
			throw 'helder.ui: $what is $want, not ' + Std.string(v);
		return switch t {
			case JNull(_) if (v == null): null;
			case JNull(t): read(t, v, what);
			case JNumber:
				if (Std.isOfType(v, Int)) {
					var f:Float = (v : Int);
					f;
				} else if (Std.isOfType(v, Float)) {
					var f:Float = v;
					f;
				} else no("a number");
			case JInt:
				if (Std.isOfType(v, Int)) {
					var i:Int = v;
					i;
				} else if (Std.isOfType(v, Float) && Math.ffloor(v) == v && Math.abs(v) < 2147483648.0) {
					var i:Int = Std.int(v);
					i;
				} else no("a whole number");
			case JString: Std.isOfType(v, String) ? v : no("a string");
			case JBool: Std.isOfType(v, Bool) ? v : no("a boolean");
			case JArray(e):
				if (!Std.isOfType(v, Array)) no("an array");
				var a:Array<Dynamic> = v;
				[for (i in 0...a.length) read(e, a[i], '$what[$i]')];
			case JFields(fs):
				if (v == null || Reflect.isFunction(v) || Type.typeof(v) != TObject) no("an object");
				var o:Dynamic = {};
				for (f in fs) {
					var x:Dynamic = Reflect.field(v, f.name);
					if (x == null && f.optional) continue;
					if (x == null && !f.optional && !f.type.match(JNull(_))) throw 'helder.ui: $what needs a field ${f.name}';
					Reflect.setField(o, f.name, read(f.type, x, '$what.${f.name}'));
				}
				o;
		}
	}

	// whether two values of type t are the same argument
	public static function equal(t:JsonType, a:Dynamic, b:Dynamic):Bool {
		if (a == null || b == null) return a == null && b == null;
		return switch t {
			case JNull(t): equal(t, a, b);
			case JNumber | JInt:
				var x:Float = a, y:Float = b;
				x == y;
			case JString | JBool: a == b;
			case JArray(e):
				var x:Array<Dynamic> = a, y:Array<Dynamic> = b;
				if (x.length != y.length) return false;
				for (i in 0...x.length)
					if (!equal(e, x[i], y[i])) return false;
				true;
			case JFields(fs):
				for (f in fs)
					if (!equal(f.type, Reflect.field(a, f.name), Reflect.field(b, f.name))) return false;
				true;
		}
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
		return JFields([for (f in fs) {name: (f.name : String), type: ofData(f.type), optional: f.optional == true}]);
	}
}
