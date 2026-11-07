package helder.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// The markup macro's half of the source map (helder.view.Source): in dev
// builds (-D hxmc.dev) and headless runs (-D helder.headless) the spans of a
// literal's elements and of its components' calls and functions, as
// expressions of helder.view.Sources.span; in any other build none
// (null), so a release build has no trace of it.
class SourceMap {
	public static function enabled():Bool
		return Context.defined("hxmc.dev") || Context.defined("helder.headless");

	// (the literals being planned, innermost last: their elements' ends, the parser's;
	// a hole typed while one is planned may plan a literal of its own)
	static final literals:Array<Map<Int, Int>> = [];

	// f, planning a literal whose elements end at ends
	public static function within<T>(ends:Map<Int, Int>, f:Void->T):T {
		literals.push(ends);
		var r = try f() catch (e:Dynamic) {
			literals.pop();
			throw e;
		}
		literals.pop();
		return r;
	}

	// the statement telling element, of the tag at at of the literal at base of file, where it is (null: none kept)
	public static function element(element:Expr, file:String, base:Int, at:Int, pos:Position):Null<Expr> {
		var span = literal(file, base, at);
		return span == null ? null : macro @:pos(pos) helder.view.Sources.element($element, $span);
	}

	// a component's factory's body: Sources.enter(its name, its call's span, its function's) first
	public static function factory(body:Expr, callee:Expr, file:String, base:Int, at:Int):Expr {
		var enter = component(callee, file, base, at);
		return enter == null ? body : macro @:pos(body.pos) {
			$enter;
			$body;
		};
	}

	// the span of the element whose PElement's at is at, in the literal at base of file
	static function literal(file:String, base:Int, at:Int):Null<Expr> {
		if (!enabled() || literals.length == 0) return null;
		var end = literals[literals.length - 1].get(at);
		if (end == null) return null;
		return span(file, base + at - 1, base + end);
	}

	static function component(callee:Expr, file:String, base:Int, at:Int):Null<Expr> {
		var call = literal(file, base, at);
		if (call == null) return null;
		var name = haxe.macro.ExprTools.toString(callee);
		var def:Expr = macro null;
		var t = try Context.typeExpr(callee) catch (_:Dynamic) null;
		if (t != null)
			switch t.expr {
				case TField(_, FStatic(_, cf)):
					var p = Context.getPosInfos(cf.get().pos);
					if (p.file != null && p.file != "" && sys.FileSystem.exists(p.file)) def = span(p.file, p.min, p.max);
				case _:
			}
		return macro @:pos(callee.pos) helder.view.Sources.enter($v{name}, $call, $def);
	}

	// Sources.span(file, start, end, line, col, endLine, endCol) of a range of file's bytes
	public static function span(file:String, start:Int, end:Int):Expr {
		var path = full(file);
		var a = place(path, start), b = place(path, end);
		return macro helder.view.Sources.span($v{path}, $v{start}, $v{end}, $v{a.line}, $v{a.col}, $v{b.line}, $v{b.col});
	}

	static final fulls = new Map<String, String>();

	static function full(file:String):String {
		var f = fulls.get(file);
		if (f == null) {
			f = try sys.FileSystem.fullPath(file) catch (_:Dynamic) file;
			f = f.split("\\").join("/");
			fulls.set(file, f);
		}
		return f;
	}

	// (each file's lines' starts, bytes)
	static final lines = new Map<String, Array<Int>>();

	// a byte offset's line and column (1-based)
	public static function place(path:String, offset:Int):{line:Int, col:Int} {
		var starts = lines.get(path);
		if (starts == null) {
			starts = [0];
			var bytes = try sys.io.File.getBytes(path) catch (_:Dynamic) haxe.io.Bytes.alloc(0);
			for (i in 0...bytes.length)
				if (bytes.get(i) == "\n".code) starts.push(i + 1);
			lines.set(path, starts);
		}
		var lo = 0, hi = starts.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			if (starts[mid] <= offset) lo = mid else hi = mid - 1;
		}
		return {line: lo + 1, col: offset - starts[lo] + 1};
	}
}
#end
