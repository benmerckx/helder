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
	// name ("vars"), the light and dark tokens, and other files' slots
	// ("include": their "slots", over the file's)
	public static macro function sheet(file:String):Expr {
		var pos = Context.currentPos();
		var path = haxe.io.Path.join([haxe.io.Path.directory(Context.getPosInfos(pos).file), file]);
		var sheet = try Sheet.read(path) catch (e) Context.error('Tw.sheet: $path: $e', pos);
		for (f in sheet.files)
			Context.registerModuleDependency(Context.getLocalModule(), f);
		// (the file a slot is read from: where errors point)
		var at = sheet.path;
		var tw = new Tailwind(css(sheet.radius), (m, offset, n) -> Context.error(m, Context.makePosition({file: at, min: offset, max: offset + n})), sheet.vars);
		var global = {classes: sheet.global, offset: sheet.globalOffset};
		var rules = [];
		for (slot in sheet.slots) {
			at = slot.file.path;
			var out = tw.slot(slot.name, slot.lists);
			if (global.classes != "" && Lambda.exists(out, r -> r.props.exists("borderWidth") || r.props.exists("borders"))) {
				at = sheet.path;
				out = tw.slot(slot.name, [global].concat(slot.lists));
			}
			rules = rules.concat(out);
		}
		var e = new Encoder();
		e.int(rules.length);
		for (r in rules)
			e.rule(r);
		for (m in [sheet.light, sheet.dark]) {
			var tokens:haxe.DynamicAccess<String> = m;
			var keys = [for (k in tokens.keys()) k];
			keys.sort(Reflect.compare);
			e.int(keys.length);
			for (k in keys) {
				e.str(k);
				e.str(tokens[k]);
			}
		}
		e.str(Std.string(css(sheet.radius)));
		// (-D hxmc.theme.dump: each rule as Tailwind.describe writes it, and the data's size)
		if (Context.defined("hxmc.theme.dump")) {
			for (r in rules)
				Sys.println(Tailwind.describe(r));
			Sys.println('Tw.sheet: ${rules.length} rules, ${e.data.length} bytes of rules, ${e.strings.join("\n").length} of strings');
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

	// (--radius plus px: "r" and the px, Length.token("radius", px) when read)
	function num(f:Float)
		str(Tailwind.isRadius(f) ? "r" + (f - Tailwind.RADIUS) : Std.string(f));

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
			case ["c", VColor(s)] | ["s", VStr(s)] | ["t", VTransform(s)] | ["r", VTransition(s)]: str(s);
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
