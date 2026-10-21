// The parts of the compiler's display JSON (haxe.display.JsonModuleTypes)
// the editor shows, as site/client/Playground.hx read them: a type as Haxe
// source, a completion item's label, kind and detail.

typedef JsonType = {kind:String, ?args:Dynamic};
typedef JsonArg = {name:String, ?opt:Bool, t:JsonType};
typedef DisplayItem = {kind:String, ?args:Dynamic, ?type:JsonType};
typedef ItemInfo = {label:String, kind:String, ?detail:String, ?doc:String};

class DisplayJson {
	public static function typeString(t:Null<JsonType>):String {
		if (t == null) return "?";
		var a:Dynamic = t.args;
		function params(ps:Null<Array<JsonType>>)
			return ps != null && ps.length > 0 ? "<" + ps.map(typeString).join(", ") + ">" : "";
		return switch t.kind {
			case "TMono": "Unknown";
			case "TInst" | "TEnum" | "TType" | "TAbstract": a.path.typeName + params(a.params);
			case "TFun": "(" + (a.args : Array<JsonArg>).map(x -> (x.opt ? "?" : "") + (x.name != null && x.name != "" ? x.name + ":" : "") + typeString(x.t)).join(", ") + ") -> " + typeString(a.ret);
			case "TAnonymous": "{ " + (a.fields != null ? (a.fields : Array<Dynamic>) : []).map(f -> f.name + ":" + typeString(f.type)).join(", ") + " }";
			case "TDynamic": a != null ? "Dynamic<" + typeString(a) + ">" : "Dynamic";
			case kind: kind;
		}
	}

	// kind: CodeMirror's completion types (the icons): method, property, variable, class, ...
	public static function itemInfo(item:DisplayItem):ItemInfo {
		var a:Dynamic = item.args != null ? item.args : {};
		var f:Dynamic = a.field;
		return switch item.kind {
			case "ClassField" | "EnumAbstractField" | "AnonField":
				{label: f.name, kind: f.kind != null && f.kind.kind == "FMethod" ? "method" : "property", detail: typeString(f.type), doc: f.doc};
			case "EnumField": {label: f.name, kind: "enum", detail: typeString(f.type), doc: f.doc};
			case "Local": {label: a.name, kind: "variable", detail: typeString(a.type)};
			case "Type":
				var pack:Array<String> = a.path.pack != null ? a.path.pack : [];
				{label: a.path.typeName, kind: a.kind == "Interface" ? "interface" : a.kind == "Enum" ? "enum" : "class", detail: pack.concat([a.path.typeName]).join("."), doc: a.doc};
			case "Package": {label: a.path != null && a.path.pack != null ? a.path.pack[(a.path.pack.length : Int) - 1] : Std.string(a), kind: "namespace"};
			case "Module": {label: a.path != null ? a.path.moduleName : Std.string(a), kind: "namespace"};
			case "Keyword": {label: a.name, kind: "keyword"};
			case "Literal": {label: a.name, kind: "constant", detail: typeString(a.type)};
			case "Metadata": {label: a.name, kind: "keyword", doc: a.doc};
			case "TypeParameter": {label: a.name, kind: "type"};
			case kind: {label: f != null && f.name != null ? f.name : a.name != null ? a.name : kind, kind: "text"};
		}
	}

	// a hover's result as one line (name : type) and its documentation
	public static function hover(r:Dynamic):Null<{text:String, doc:Null<String>}> {
		if (r == null || r.item == null) return null;
		var item:DisplayItem = r.item;
		var info = itemInfo(item);
		var type = item.type != null ? typeString(item.type) : info.detail;
		var args:Dynamic = item.args;
		var doc:Null<String> = args == null ? null : args.doc != null ? args.doc : args.field != null ? args.field.doc : null;
		var name = info.label != null && info.label != item.kind ? info.label : null;
		return {text: (name != null ? name + " : " : "") + (type != null ? type : item.kind), doc: doc != null && doc != "" ? StringTools.trim(doc) : null};
	}

	// a signature help's result: the active signature, its parameters, which one is active
	public static function signature(r:Dynamic):Null<{params:Array<String>, ret:String, active:Int, doc:Null<String>}> {
		if (r == null || r.signatures == null || r.signatures.length == 0) return null;
		var s:Dynamic = r.signatures[r.activeSignature != null ? r.activeSignature : 0];
		var args:Array<JsonArg> = s.args;
		return {
			params: args.map(x -> (x.opt ? "?" : "") + x.name + ":" + typeString(x.t)),
			ret: typeString(s.ret),
			active: r.activeParameter != null ? r.activeParameter : 0,
			doc: s.documentation,
		};
	}
}
