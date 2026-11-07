package helder.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import helder.markup.Live;
import helder.markup.Plan.LiveAt;

// Live literals in Haxe's markup (helder.markup.Live, helder.dev.Literals):
// HaxeTarget's live and liveIn. In a dev build (-D hxmc.dev, not
// helder.release) a literal the planner marks live is read from its slot,
// helder.dev.Literals.string/int/float/bool(id, value, anchor), its place
// recorded in -D helder.literals' table when helder dev names one.
class LiveMacro {
	public static function on():Bool
		return Context.defined("hxmc.dev") && !Context.defined("helder.release");

	// a literal's slot read: value (a string, true, a literal's expression) at
	// where (base: the root literal's offset in file); null: not live
	public static function live(value:Expr, where:LiveAt, file:String, base:Int):Null<Expr> {
		if (!on()) return null;
		var full = try sys.FileSystem.fullPath(file) catch (_:Dynamic) file;
		var c = Live.content(full);
		if (c == null) return null;
		var src = c.content;
		var start = -1, end = -1, form = "quoted";
		switch where {
			case LText(at, e):
				if (e == null) return null;
				start = base + at;
				end = base + e;
				form = "text";
			case LAttr(at, name):
				// (after the name: =, then the quoted value; a flag: its name)
				var p = base + at + name.length;
				while (p < src.length && isSpace(src.charCodeAt(p))) p++;
				if (p < src.length && src.charAt(p) == "=") {
					p++;
					while (p < src.length && isSpace(src.charCodeAt(p))) p++;
					var q = src.charAt(p);
					if (q != '"' && q != "'") return null;
					var close = src.indexOf(q, p + 1);
					if (close < 0) return null;
					start = p;
					end = close + 1;
				} else {
					start = base + at;
					end = base + at + name.length;
					form = "flag";
				}
			case LExpr:
				var info = Context.getPosInfos(value.pos);
				start = info.min;
				end = info.max;
				form = switch value.expr {
					case EConst(CString(_)): "quoted";
					case _: "number";
				}
		}
		if (start < 0 || end > src.length) return null;
		var kind = "string", fn = "string";
		switch value.expr {
			case EConst(CString(s)):
				kind = form == "text" ? "text" : Live.stringKind(s);
			case EConst(CInt(_)):
				kind = "number";
				fn = "int";
			case EConst(CFloat(_)):
				kind = "number";
				fn = "float";
			case EConst(CIdent("true" | "false")):
				kind = "boolean";
				fn = "bool";
			case _:
				return null;
		}
		return slot(full, c, start, end, form, kind, fn, value);
	}

	static function slot(full:String, c:{content:String, hash:String}, start:Int, end:Int, form:String, kind:String, fn:String, value:Expr):Expr {
		var id = Live.id(full, c.content, start, kind), anchor = Live.anchor(c.content, start, end);
		var table = Context.definedValue("helder.literals");
		if (table != null && table != "" && table != "1") {
			// (written once the build's typing is done)
			if (!Live.pending()) Context.onAfterTyping(_ -> Live.flush());
			Live.record(table, full, c.hash, {id: id, start: start, end: end, form: form});
		}
		var p = value.pos;
		return macro @:pos(p) helder.dev.Literals.$fn($v{id}, $value, $v{anchor});
	}

	static inline function isSpace(c:Int):Bool
		return c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code;

	// an attribute's expression with its branches' literals live: a
	// ternary's (and if's) values, ??'s fallback, a Color's channels
	// (Color.rgb(0x3b82f6): its int a colour's slot)
	public static function liveIn(e:Expr, file:String):Expr {
		if (!on()) return e;
		function branch(x:Expr):Expr
			return switch x.expr {
				case EConst(CInt(_) | CFloat(_) | CString(_, DoubleQuotes)): live(x, LExpr, file, 0) ?? x;
				case _: liveIn(x, file);
			}
		return switch e.expr {
			case ETernary(c, a, b): {expr: ETernary(c, branch(a), branch(b)), pos: e.pos};
			case EIf(c, a, b) if (b != null): {expr: EIf(c, branch(a), branch(b)), pos: e.pos};
			case EBinop(OpNullCoal, a, b): {expr: EBinop(OpNullCoal, a, branch(b)), pos: e.pos};
			case EParenthesis(x): {expr: EParenthesis(liveIn(x, file)), pos: e.pos};
			case ECall(callee = {expr: EField({expr: EConst(CIdent("Color")) | EField(_, "Color")}, "rgb" | "rgba" | "hex")}, args):
				{expr: ECall(callee, [for (a in args) color(a, file)]), pos: e.pos};
			case _: e;
		}
	}

	// a Color's channel: an int literal, a colour's slot
	static function color(a:Expr, file:String):Expr {
		if (!a.expr.match(EConst(CInt(_)))) return a;
		var full = try sys.FileSystem.fullPath(file) catch (_:Dynamic) file;
		var c = Live.content(full);
		if (c == null) return a;
		var info = Context.getPosInfos(a.pos);
		return slot(full, c, info.min, info.max, "number", "color", "int", a);
	}
}
#end
