package hxmc.theme;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import hxmc.theme.Tailwind;
#end

// Tailwind class lists as hxmc.ui's rules, at compile time (Tailwind.hx:
// what is read and how; RuleData.hx: the data the rules become, read once when
// the program first needs them). An unknown class is a compile error at it.
//   Tw.rules("button", "inline-flex h-9 px-4 hover:bg-primary/90")
//   Tw.rules("button", "bg-destructive text-white", "destructive")
//   Tw.sheet("shadcn.json"): a StyleSheet, its slots and tokens from the file
class Tw {
	// the rules of one class list for a slot (and a variant, a size)
	public static macro function rules(slot:String, classes:ExprOf<String>, ?variant:String, ?size:String):Expr {
		var s = switch classes.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("Tw.rules: a string literal", classes.pos);
		}
		var p = Context.getPosInfos(classes.pos);
		var tw = new Tailwind(10, (m, at, n) -> Context.error(m, Context.makePosition({file: p.file, min: p.min + 1 + at, max: p.min + 1 + at + n})));
		var e = new Encoder();
		for (r in tw.slot(slot, [{classes: s, offset: 0, variant: variant, size: size}]))
			e.rule(r);
		return macro hxmc.theme.RuleData.rules($v{e.data.toString()}, $v{e.strings.join("\n")});
	}

	// a StyleSheet from a JSON file beside the calling module: its slots'
	// class lists (a string, cn's several, or cva's {base, variant: {name:
	// classes}, size: {name: classes}}, or another slot's: {extends: slot,
	// variant and size fixed or not}; and a class after them, as cn's
	// className), "global" before each slot's that has borders (shadcn's
	// `* { border-border }`), --radius ("radius"), CSS variables a class may
	// name ("vars"), and the light and dark tokens; "include": other files
	// beside it whose slots are added (a slot in two files is an error)
	public static macro function sheet(file:String):Expr {
		var pos = Context.currentPos();
		var path = haxe.io.Path.join([haxe.io.Path.directory(Context.getPosInfos(pos).file), file]);
		var text = try sys.io.File.getContent(path) catch (e) Context.error('Tw.sheet: $path: $e', pos);
		Context.registerModuleDependency(Context.getLocalModule(), path);
		var json:Dynamic = try haxe.Json.parse(text) catch (e) Context.error('Tw.sheet: $path: $e', pos);
		var main = {path: path, text: text};
		// (each slot's file: the class lists' offsets and errors are in it)
		var slots:haxe.DynamicAccess<Dynamic> = Reflect.copy(json.slots);
		var source = [for (k in slots.keys()) k => main];
		var include:Array<String> = json.include == null ? [] : json.include;
		for (inc in include) {
			var p = haxe.io.Path.join([haxe.io.Path.directory(path), inc]);
			var t = try sys.io.File.getContent(p) catch (e) Context.error('Tw.sheet: $p: $e', pos);
			Context.registerModuleDependency(Context.getLocalModule(), p);
			var j:Dynamic = try haxe.Json.parse(t) catch (e) Context.error('Tw.sheet: $p: $e', pos);
			var more:haxe.DynamicAccess<Dynamic> = j.slots;
			for (k => x in more) {
				if (slots.exists(k)) Context.error('Tw.sheet: $p: slot $k is in ${source[k].path} too', pos);
				slots[k] = x;
				source[k] = {path: p, text: t};
			}
		}
		// (a class list's offset in the file)
		function offset(s:String):Int
			return text.indexOf('"' + s + '"') + 1;
		function sorted(m:haxe.DynamicAccess<Dynamic>):Array<String> {
			var keys = [for (k in m.keys()) k];
			keys.sort(Reflect.compare);
			return keys;
		}
		var vars = new Map<String, String>();
		var v:haxe.DynamicAccess<String> = json.vars;
		if (v != null) for (k => x in v)
			vars[k] = x;
		var tw = new Tailwind(css(json.radius), (m, at, n) -> Context.error(m, Context.makePosition({file: path, min: at, max: at + n})), vars);
		var global = {classes: (json.global : String) ?? "", offset: offset(json.global ?? "")};
		var rules = [];
		for (name in sorted(slots)) {
			path = source[name].path;
			text = source[name].text;
			var lists:Array<{classes:String, offset:Int, ?variant:String, ?size:String}> = [];
			function add(s:String, ?variant:String, ?size:String)
				lists.push({classes: s, offset: offset(s), variant: variant, size: size});
			function some(v:Dynamic, f:String->Void)
				if (Std.isOfType(v, Array)) for (s in (v : Array<String>)) f(s) else if (v != null) f(v);
			// (cva's: its base, then each variant's and size's, or the
			// variant and size an entry fixes; then the entry's class, as cn's className)
			function cva(v:Dynamic, ?variant:String, ?size:String) {
				var parent:String = Reflect.field(v, "extends");
				if (parent != null) {
					var base:Dynamic = slots[parent];
					if (base == null) Context.error('Tw.sheet: $name extends $parent, which is not a slot', pos);
					// (one fixed: the other cva's default)
					if (v.variant != null || v.size != null) cva(base, v.variant ?? "default", v.size ?? "default") else cva(base, variant, size);
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
				}
				some(Reflect.field(v, "class"), s -> add(s));
			}
			var v = slots[name];
			if (Std.isOfType(v, String) || Std.isOfType(v, Array)) some(v, s -> add(s)) else cva(v);
			var out = tw.slot(name, lists);
			if (global.classes != "" && Lambda.exists(out, r -> r.props.exists("borderWidth") || r.props.exists("borders")))
				out = tw.slot(name, [global].concat(lists));
			rules = rules.concat(out);
		}
		// (-D hxmc.theme.dump: each rule as Tailwind.describe writes it)
		if (Context.defined("hxmc.theme.dump")) for (r in rules)
			Sys.println(Tailwind.describe(r));
		var e = new Encoder();
		e.int(rules.length);
		for (r in rules)
			e.rule(r);
		for (m in [json.light, json.dark]) {
			var tokens:haxe.DynamicAccess<String> = m;
			var keys = sorted(tokens);
			e.int(keys.length);
			for (k in keys) {
				e.str(k);
				e.str(tokens[k]);
			}
		}
		return macro hxmc.theme.RuleData.sheet($v{e.data.toString()}, $v{e.strings.join("\n")});
	}

	#if macro
	// (a CSS length in px: 0.625rem, 10px)
	static function css(v:String):Float
		return StringTools.endsWith(v, "rem") ? Std.parseFloat(v) * Tailwind.REM : Std.parseFloat(v);
	#end
}

#if macro
// rules written as RuleData reads them
private class Encoder {
	static var fields:Null<Map<String, {id:Int, kind:String}>> = null;
	static final enums = new Map<String, Int>();

	public final data = new StringBuf();
	public final strings:Array<String> = [];
	final index = new Map<String, Int>();

	public function new() {
		if (fields == null) {
			fields = [];
			var list = RuleData.FIELDS.split(" ");
			for (i in 0...list.length) {
				var f = list[i].split(":");
				fields[f[0]] = {id: i, kind: f[1]};
			}
		}
	}

	public function int(v:Int) {
		if (v < 0 || v >= 15 * 64) Context.error('Tw: $v is beyond what RuleData reads', Context.currentPos());
		if (v < 64) data.addChar(48 + v) else {
			data.addChar(112 + (v >> 6));
			data.addChar(48 + (v & 63));
		}
	}

	// (a string's index in the table)
	function intern(s:String):Int {
		var i = index[s];
		if (i == null) {
			i = index[s] = strings.length;
			strings.push(s);
		}
		return i;
	}

	public function str(s:String)
		int(intern(s));

	function num(f:Float)
		str(Std.string(f));

	public function rule(r:TwRule) {
		str(r.slot);
		int(r.variant == null ? 0 : 1 + intern(r.variant));
		int(r.size == null ? 0 : 1 + intern(r.size));
		int(r.when.length);
		for (w in r.when)
			str(w);
		int(r.fields.length);
		for (k in r.fields) {
			var f = fields[k];
			if (f == null) Context.error('Tw: RuleData.FIELDS has no $k', Context.currentPos());
			int(f.id);
			value(f.kind, r.props[k]);
		}
	}

	function value(kind:String, v:TwValue) {
		switch [kind, v] {
			case ["e", VEnum(type, name)]: int(enumValue(type, name));
			case ["b", VBool(b)]: int(b ? 1 : 0);
			case ["f" | "i", VNum(n)]: num(n);
			case ["i", VInt(n)]: num(n);
			case ["d", VNum(n) | VDim(Px(n))]:
				int(0);
				num(n);
			case ["d", VDim(d)]:
				switch d {
					case Percent(p):
						int(1);
						num(p);
					case Auto: int(2);
					case MinContent: int(3);
					case MaxContent: int(4);
					case FitContent: int(5);
					case Calc(p, px):
						int(6);
						num(p);
						num(px);
					case Px(_):
				}
			case ["E", VEdges(t, r, b, l)] | ["C", VCorners(t, r, b, l)]: for (n in [t, r, b, l]) num(n);
			case ["c", VColor(s)] | ["s", VStr(s)] | ["t", VTransform(s)]: str(s);
			case ["S", VShadow(list)]:
				int(list.length);
				for (s in list) {
					for (n in [s.x, s.y, s.blur, s.spread])
						num(n);
					str(s.color);
				}
			case ["T", VTracks(list)]:
				int(list.length);
				for (t in list) {
					trackSize(t.min);
					trackSize(t.max);
				}
			case ["k", VTracks([t])]:
				trackSize(t.min);
				trackSize(t.max);
			case ["p", VPlacement(start, end, span)]: for (n in [start, end, span]) num(n);
			case _: Context.error('Tw: a $kind field cannot be ${Tailwind.value(v)}', Context.currentPos());
		}
	}

	function trackSize(s:hxmc.ui.Grid.TrackSize)
		switch s {
			case Px(v):
				int(0);
				num(v);
			case Percent(p):
				int(1);
				num(p);
			case Fr(f):
				int(2);
				num(f);
			case Auto: int(3);
			case MinContent: int(4);
			case MaxContent: int(5);
		}

	// (the Int an enum abstract's case is)
	static function enumValue(type:String, name:String):Int {
		var key = '$type.$name';
		if (enums.exists(key)) return enums[key];
		function constant(e:TypedExpr):Int
			return switch e.expr {
				case TConst(TInt(n)): n;
				case TCast(e, _) | TMeta(_, e) | TParenthesis(e): constant(e);
				case TField(_, FStatic(_, cf)): constant(cf.get().expr());
				case _: Context.error('Tw: $key is not a constant', e.pos);
			}
		return enums[key] = constant(Context.typeExpr(macro $p{["hxmc", "ui", type, name]}));
	}
}
#end
