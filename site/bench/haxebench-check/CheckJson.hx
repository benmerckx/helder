import haxe.Json;
import sys.io.File;

// BMJsonCode's round trips, fewer; the digest does not depend on field order
class CheckJson {
	static function digest(v:Dynamic):Float {
		if (v == null)
			return 1;
		if (Std.isOfType(v, String)) {
			var s:String = v;
			var h = 7.0;
			for (i in 0...s.length)
				h += s.charCodeAt(i) * (i + 1);
			return h;
		}
		if (Std.isOfType(v, Bool))
			return v ? 3 : 5;
		if (Std.isOfType(v, Float))
			return (v : Float) * 1.5 + 11;
		if (Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = v;
			var h = 13.0;
			for (i in 0...a.length)
				h += digest(a[i]) * (i + 2);
			return h;
		}
		var h = 17.0;
		for (f in Reflect.fields(v))
			h += digest(f) * 3 + digest(Reflect.field(v, f));
		return h;
	}

	static function main() {
		var text = File.getContent("../data/hxformat-schema.json");
		var schema:Any = Json.parse(text);
		var d0 = digest(schema);
		var listOfSchema:Array<Any> = [for (i in 0...20) schema];
		for (i in 0...20) {
			text = Json.stringify(schema);
			schema = Json.parse(text);
		}
		Sys.println("schema length " + text.length + ", digest " + d0 + " = " + digest(schema));
		text = Json.stringify(listOfSchema);
		var back:Array<Any> = Json.parse(text);
		Sys.println("list length " + text.length + ", " + back.length + " items, digest " + digest(back));
		Sys.println(Json.stringify([1, 2.5, -3e-7, 1e21, 0.1, true, null, "\"\\/\né\u{1F600}"]));
	}
}
