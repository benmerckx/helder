package helder.theme;

#if (macro || sys || eval)
// a slot's class lists as a sheet file gives them: cva's base, each
// variant's and size's (or those an entry fixes), classes under a state
// (prefix), the entry's class after them; offset: where the list is in its
// file (Tw's errors point there)
typedef SheetList = {classes:String, offset:Int, ?variant:String, ?size:String, ?prefix:String};

typedef SheetSlot = {name:String, file:{path:String, text:String}, lists:Array<SheetList>};

// A sheet file read (shadcn.json's format, README): its slots' class lists
// (its includes' slots over its own, by name), radius, vars, global and
// tokens. What Tw.sheet makes rules of and Css a stylesheet of.
class Sheet {
	public final path:String;
	public final radius:String;
	public final global:String;
	public final globalOffset:Int;
	public final vars:Map<String, String> = [];
	public final light:haxe.DynamicAccess<String>;
	public final dark:haxe.DynamicAccess<String>;
	public final slots:Array<SheetSlot> = [];
	// the files read (the sheet, then its includes)
	public final files:Array<String> = [];

	function new(path:String, text:String) {
		this.path = path;
		files.push(path);
		var json:Dynamic = haxe.Json.parse(text);
		radius = json.radius;
		global = json.global ?? "";
		globalOffset = text.indexOf('"' + global + '"') + 1;
		light = json.light;
		dark = json.dark;
		var v:haxe.DynamicAccess<String> = json.vars;
		if (v != null) for (k => x in v)
			vars[k] = x;
		var main = {path: path, text: text};
		var all:haxe.DynamicAccess<Dynamic> = Reflect.copy(json.slots), from = new Map<String, {path:String, text:String}>();
		var include:Array<String> = json.include == null ? [] : json.include;
		for (inc in include) {
			var p = haxe.io.Path.join([haxe.io.Path.directory(path), inc]);
			var t = sys.io.File.getContent(p);
			files.push(p);
			var j:Dynamic = haxe.Json.parse(t);
			var more:haxe.DynamicAccess<Dynamic> = j.slots;
			if (more != null) for (k => x in more) {
				all[k] = x;
				from[k] = {path: p, text: t};
			}
		}
		for (name in sorted(all)) {
			var file = from[name] ?? main;
			var lists:Array<SheetList> = [];
			function add(s:String, ?variant:String, ?size:String, ?prefix:String)
				lists.push({classes: s, offset: file.text.indexOf('"' + s + '"') + 1, variant: variant, size: size, prefix: prefix});
			function some(v:Dynamic, f:String->Void)
				if (Std.isOfType(v, Array)) for (s in (v : Array<String>)) f(s) else if (v != null) f(v);
			// (cva's: its base, then each variant's and size's, or the
			// variant and size an entry fixes; then the entry's class, as cn's className)
			function cva(v:Dynamic, ?variant:String, ?size:String) {
				var parent:String = Reflect.field(v, "extends");
				if (parent != null) {
					var base:Dynamic = all[parent];
					if (base == null) throw '$name extends $parent, which is not a slot';
					// (a plain list's classes; one fixed: the other cva's default)
					if (Std.isOfType(base, String) || Std.isOfType(base, Array)) some(base, s -> add(s)) else if (v.variant != null
						|| v.size != null) cva(base, v.variant ?? "default", v.size ?? "default") else cva(base, variant, size);
				} else {
					some(v.base, s -> add(s));
					for (kind in ["variant", "size"]) {
						var m:haxe.DynamicAccess<String> = Reflect.field(v, kind);
						var fixed = kind == "variant" ? variant : size;
						if (m != null) for (k in sorted(m))
							if (fixed != null) {
								if (k == fixed) add(m[k]);
							} else if (kind == "variant") add(m[k], k) else add(m[k], null, k);
					}
					// (classes under a state the widget sets, as a prop's in the component: sheet's side, data-[side=right])
					var states:haxe.DynamicAccess<String> = Reflect.field(v, "states");
					if (states != null) for (k in sorted(states))
						add(states[k], null, null, k);
				}
				some(Reflect.field(v, "class"), s -> add(s));
			}
			var v = all[name];
			if (Std.isOfType(v, String) || Std.isOfType(v, Array)) some(v, s -> add(s)) else cva(v);
			slots.push({name: name, file: file, lists: lists});
		}
	}

	// reads a sheet file and its includes (an error: what failed, thrown)
	public static function read(path:String):Sheet
		return new Sheet(path, sys.io.File.getContent(path));

	static function sorted(m:haxe.DynamicAccess<Dynamic>):Array<String> {
		var keys = [for (k in m.keys()) k];
		keys.sort(Reflect.compare);
		return keys;
	}
}
#end
