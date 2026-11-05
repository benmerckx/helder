package helder.ui.actions;

// What a node is to the keymap (Node.keyContext; markup's key-context):
// identifiers and key=value attributes, as GPUI's: "Editor",
// "Editor mode=full read_only", "Viewer zoomed". The focused node's
// ancestors' contexts, root first, are the context stack bindings match
// against (ContextPredicate).
class KeyContext {
	public final ids:Array<String>;
	public final values:Map<String, String>;

	public function new(?ids:Array<String>, ?values:Map<String, String>) {
		this.ids = ids ?? [];
		this.values = values ?? [];
	}

	public static function parse(s:String):KeyContext {
		var c = new KeyContext();
		for (p in StringTools.trim(s).split(" ")) {
			if (p == "") continue;
			var i = p.indexOf("=");
			if (i > 0) c.values.set(p.substr(0, i), p.substr(i + 1)) else c.ids.push(p);
		}
		return c;
	}

	public inline function has(id:String):Bool
		return ids.contains(id);

	// (an identifier set, or a value of that name)
	public inline function get(key:String):Null<String>
		return values.get(key);

	public function toString():String
		return ids.concat([for (k => v in values) k + "=" + v]).join(" ");
}
