package helder.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Tools;
using Lambda;
#end

// Scopes for functions, as hxmc's compiler made them for scoped code:
//
//   @:build(helder.scoped.Scoped.build())
//   class Physics {
//     @:scoped static function step(ps:Slice<Particle>, dt:Float) { ... }
//   }
//
// (`@:scoped` on the class: every function of it.)
//
// - A function marks its scope on entry and leaves it at every return, so
//   what it allocated is freed. A function whose result is a scoped value
//   does not: its memory, the result included, belongs to the caller's
//   scope. An unannotated return type counts as scoped when the function
//   returns a value.
// - Each loop's iteration is a scope: what an iteration allocated is freed
//   when the next starts, and after the loop. An iteration that cannot
//   allocate (Loops.iteration: nothing in it reaches an allocation) skips
//   the check.
// - An exception leaves the memory to the enclosing scope (whose locals
//   hold the top to come back to), so nothing is freed early: the enclosing
//   function's return, or its loop's next iteration, frees it. One that
//   leaves every @:scoped function keeps that memory for good: entry points
//   (callbacks) catch their exceptions themselves.
// - Loops over a slice: in `for (i in 0...s.length)`, where neither s nor i is
//   assigned, declared again or captured in the body, `s[i]` reads the
//   elements through a view (Loops.view: the data and stride in locals) with
//   no checks, i being in range by construction.
class Scoped {
	#if macro
	static var counter = 0;

	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var cls = Context.getLocalClass();
		var all = cls != null && cls.get().meta.has(":scoped");
		for (f in fields)
			switch f.kind {
				case FFun(fn) if (fn.expr != null && (all || f.meta.exists(m -> m.name == ":scoped"))):
					// (a call to it frees what it allocated: Loops.iteration)
					if (!returnsScoped(fn, f.pos))
						f.meta.push({name: ":scopedFrees", pos: f.pos});
					fn.expr = wrap(fn, f.pos);
					fn.expr = hoist(fn);
				default:
			}
		return fields;
	}

	static function wrap(fn:Function, pos:Position):Expr {
		var keep = returnsScoped(fn, pos);
		var mark = "__scope" + counter++;
		var body = rewrite(fn.expr, keep ? null : mark);
		if (keep)
			return body;
		var c = mark + "c";
		return macro @:pos(pos) {
			var $mark = helder.scoped.Memory.enter(), $c = helder.scoped.Memory.claims();
			$body;
			helder.scoped.Memory.leave($i{mark}, $i{c});
		};
	}

	// (mark: the function's, left at each return; null: kept for the caller)
	static function rewrite(e:Expr, mark:Null<String>):Expr {
		return switch e.expr {
			case EFunction(_, _):
				e;
			// (an array comprehension's loops make its elements: not scopes)
			case EArrayDecl([x = {expr: EFor(_, _) | EWhile(_, _, _)}]):
				{expr: EArrayDecl([comprehension(x, mark)]), pos: e.pos};
			case EReturn(null) if (mark != null):
				macro @:pos(e.pos) {
					helder.scoped.Memory.leave($i{mark}, $i{mark + "c"});
					return;
				};
			case EReturn(v) if (mark != null):
				var r = rewrite(v, mark);
				macro @:pos(e.pos) {
					var __result = $r;
					helder.scoped.Memory.leave($i{mark}, $i{mark + "c"});
					return __result;
				};
			case EWhile(cond, body, normal):
				var l = "__loop" + counter++, c = "__claims" + counter++;
				var b = rewrite(body, mark);
				var loop = {expr: EWhile(rewrite(cond, mark), macro helder.scoped.Loops.iteration($i{l}, $i{c}, $b), normal), pos: e.pos};
				macro @:pos(e.pos) {
					var $l = helder.scoped.Memory.top(), $c = helder.scoped.Memory.claims();
					$loop;
					helder.scoped.Memory.restore($i{l}, $i{c});
				};
			case EFor(it, body):
				var l = "__loop" + counter++, c = "__claims" + counter++;
				var view = sliceLoop(it, body);
				if (view != null)
					body = view.body;
				var b = rewrite(body, mark);
				var loop = {expr: EFor(rewrite(it, mark), macro helder.scoped.Loops.iteration($i{l}, $i{c}, $b)), pos: e.pos};
				var out = macro @:pos(e.pos) {
					var $l = helder.scoped.Memory.top(), $c = helder.scoped.Memory.claims();
					$loop;
					helder.scoped.Memory.restore($i{l}, $i{c});
				};
				if (view == null)
					out;
				else {
					var vn = view.name, vs = view.slice;
					macro @:pos(e.pos) {
						var $vn = helder.scoped.Loops.view($i{vs});
						$out;
					};
				}
			default:
				e.map(x -> rewrite(x, mark));
		}
	}

	// (a comprehension's loops and what gives their values, as they are)
	static function comprehension(e:Expr, mark:Null<String>):Expr {
		return switch e.expr {
			case EFor(it, body): {expr: EFor(rewrite(it, mark), comprehension(body, mark)), pos: e.pos};
			case EWhile(cond, body, normal): {expr: EWhile(rewrite(cond, mark), comprehension(body, mark), normal), pos: e.pos};
			case EIf(cond, a, b): {expr: EIf(rewrite(cond, mark), comprehension(a, mark), b == null ? null : comprehension(b, mark)), pos: e.pos};
			case EBlock(el) if (el.length > 0):
				{expr: EBlock([for (i in 0...el.length) i == el.length - 1 ? comprehension(el[i], mark) : rewrite(el[i], mark)]), pos: e.pos};
			case EParenthesis(x): {expr: EParenthesis(comprehension(x, mark)), pos: e.pos};
			default: rewrite(e, mark);
		}
	}

	// the slices a function indexes, read through views: for each parameter
	// or local that is declared once (directly in a block), never assigned,
	// incremented or captured, and indexed (`s[e]`), `var __checkedN =
	// Loops.checked(s)` right after its declaration (a parameter: at the
	// start) and s[e] read as __checkedN[e]. Loops.checked is s itself for
	// anything but a Slice.
	static function hoist(fn:Function):Expr {
		var declared = new Map<String, Int>(), bad = new Map<String, Bool>(), indexed = new Map<String, Bool>();
		for (a in fn.args)
			declared.set(a.name, 1);
		function names(e:Expr):Null<String>
			return switch e.expr {
				case EConst(CIdent(n)): n;
				case EParenthesis(x): names(x);
				default: null;
			}
		function mentioned(e:Expr) {
			switch e.expr {
				case EConst(CIdent(n)): bad.set(n, true);
				default:
			}
			e.iter(mentioned);
		}
		var scan:Expr->Void = null;
		function inBlock(e:Expr) {
			// (declarations directly in a block, which a view can follow)
			switch e.expr {
				case EBlock(el):
					for (x in el)
						switch x.expr {
							case EVars(vs):
								for (v in vs) {
									declared.set(v.name, (declared.exists(v.name) ? declared.get(v.name) : 0) + 1);
									if (v.expr != null)
										scan(v.expr);
								}
							default:
								scan(x);
						}
					return;
				default:
					scan(e);
			}
		}
		scan = function(e:Expr) {
			switch e.expr {
				case EBlock(_):
					inBlock(e);
					return;
				case EVars(vs):
					// (not directly in a block: no view)
					for (v in vs) {
						bad.set(v.name, true);
						if (v.expr != null)
							scan(v.expr);
					}
					return;
				case EBinop(OpAssign | OpAssignOp(_), l, _) if (names(l) != null):
					bad.set(names(l), true);
				case EUnop(OpIncrement | OpDecrement, _, x) if (names(x) != null):
					bad.set(names(x), true);
				case EFunction(_, _):
					mentioned(e);
					return;
				case EArray(a, _) if (names(a) != null):
					indexed.set(names(a), true);
				default:
			}
			e.iter(scan);
		};
		inBlock(fn.expr);
		var views = new Map<String, String>();
		for (n in indexed.keys())
			if (declared.get(n) == 1 && !bad.exists(n) && !StringTools.startsWith(n, "__"))
				views.set(n, "__checked" + counter++);
		if (!views.keys().hasNext())
			return fn.expr;
		function decl(n:String):Expr {
			var v = views.get(n);
			return macro var $v = helder.scoped.Loops.checked($i{n});
		}
		function replace(e:Expr):Expr {
			return switch e.expr {
				case EArray(a, i) if (names(a) != null && views.exists(names(a))):
					{expr: EArray(macro $i{views.get(names(a))}, replace(i)), pos: e.pos};
				case EField(a, "length", _) if (names(a) != null && views.exists(names(a))):
					macro @:pos(e.pos) $i{views.get(names(a))}.length;
				case EBlock(el):
					var out = [];
					for (x in el) {
						out.push(replace(x));
						switch x.expr {
							case EVars(vs):
								for (v in vs)
									if (views.exists(v.name))
										out.push(decl(v.name));
							default:
						}
					}
					{expr: EBlock(out), pos: e.pos};
				case EFunction(_, _): e;
				default: e.map(replace);
			}
		}
		var body = replace(fn.expr);
		var first = [for (a in fn.args) if (views.exists(a.name)) decl(a.name)];
		return first.length == 0 ? body : {expr: EBlock(first.concat([body])), pos: body.pos};
	}

	// `for (i in 0...s.length)` whose body uses s[i] and neither assigns,
	// declares nor captures s or i: the body with s[i] read through a view
	static function sliceLoop(it:Expr, body:Expr):Null<{name:String, slice:String, body:Expr}> {
		var i:String, s:String;
		switch it.expr {
			case EBinop(OpIn, {expr: EConst(CIdent(iv))}, {expr: EBinop(OpInterval, {expr: EConst(CInt("0", _))}, {expr: EField({expr: EConst(CIdent(sv))}, "length", _)})}):
				i = iv;
				s = sv;
			default:
				return null;
		}
		var safe = true, used = false;
		function names(e:Expr):Bool
			return switch e.expr {
				case EConst(CIdent(n)): n == i || n == s;
				default: false;
			}
		function mentions(e:Expr):Bool {
			var found = false;
			function find(x:Expr)
				switch x.expr {
					case EConst(CIdent(n)) if (n == i || n == s): found = true;
					default: x.iter(find);
				}
			find(e);
			return found;
		}
		function check(e:Expr) {
			switch e.expr {
				case EBinop(OpAssign | OpAssignOp(_), l, _) if (names(l)):
					safe = false;
				case EUnop(OpIncrement | OpDecrement, _, x) if (names(x)):
					safe = false;
				case EVars(vs):
					for (v in vs)
						if (v.name == i || v.name == s)
							safe = false;
				case EFunction(_, _):
					if (mentions(e))
						safe = false;
					return;
				case EArray({expr: EConst(CIdent(a))}, {expr: EConst(CIdent(b))}) if (a == s && b == i):
					used = true;
				default:
			}
			e.iter(check);
		}
		check(body);
		if (!safe || !used)
			return null;
		var name = "__view" + counter++;
		function replace(e:Expr):Expr
			return switch e.expr {
				case EArray({expr: EConst(CIdent(a))}, {expr: EConst(CIdent(b))}) if (a == s && b == i):
					{expr: EArray(macro $i{name}, macro $i{i}), pos: e.pos};
				case EFunction(_, _): e;
				default: e.map(replace);
			}
		return {name: name, slice: s, body: replace(body)};
	}

	static function returnsScoped(fn:Function, pos:Position):Bool {
		if (fn.ret == null)
			return returnsValue(fn.expr);
		switch fn.ret {
			case TPath({pack: [], name: "Void" | "Int" | "Float" | "Bool" | "String" | "Dynamic"}):
				return false;
			default:
		}
		return try isScoped(Context.resolveType(fn.ret, pos)) catch (_:Dynamic) true;
	}

	static function returnsValue(e:Expr):Bool {
		var found = false;
		function walk(e:Expr)
			switch e.expr {
				case EFunction(_, _):
				case EReturn(v) if (v != null): found = true;
				default: e.iter(walk);
			}
		walk(e);
		return found;
	}

	// an abstract over helder.scoped.Addr (Slice, Grow, Str, Ref, the structs)
	public static function isScoped(t:Type):Bool {
		return switch t {
			case TMono(r): r.get() != null && isScoped(r.get());
			case TLazy(f): isScoped(f());
			case TType(td, []): cached("t:" + td.toString(), () -> isScoped(td.get().type));
			case TType(_.get() => td, params): isScoped(td.type.applyTypeParameters(td.params, params));
			// (the package's views and writers hold addresses too)
			case TAbstract(a, _):
				cached(a.toString(), () -> switch a.toString() {
					case "helder.scoped.GrowWriter" | "helder.scoped.SliceView" | "helder.scoped.SliceChecked": true;
					case _:
						switch a.get().type {
							case TAbstract(b, _): b.toString() == "helder.scoped.Addr";
							default: false;
						}
				});
			case TInst(c, _): c.toString() == "helder.scoped.Span";
			default: false;
		}
	}

	// (by path: a Ref's get() makes the whole type again, on every call;
	// forgotten at the end of each compilation, for the compilation server)
	static var known:Null<Map<String, Bool>> = null;

	static function cached(key:String, f:() -> Bool):Bool {
		if (known == null) {
			known = new Map();
			Context.onAfterGenerate(() -> known = null);
		}
		var v = known.get(key);
		if (v == null)
			known.set(key, v = f());
		return v;
	}
	#end
}
