package helder.gfx.shader;

import helder.gfx.shader.Ir;

// A slot object's variant, after its constants are folded (ShaderDefinition.
// variant): what it never reads of the optional fields dropped. The
// varyings' optional fields neither stage reads (their values with them),
// the locals nothing reads any more, then the vertex's optional fields
// (its attributes) and the stages' optional parameters nothing reads. So a
// variant of the combined vertex (pos, normal, uv, ?tangent, ?joints,
// ?weights, ?m0...) has the layout of the attributes it uses, in order.
class Prune {
	public static function program(vf:SFunction, ff:SFunction) {
		var vfs = reachable(vf), ffs = reachable(ff);
		var all = vfs.concat([for (f in ffs) if (!vfs.contains(f)) f]);
		switch vf.ret {
			case TStruct(varyings):
				var read = fieldsRead(all, varyings);
				var drop = [for (i in 0...varyings.fields.length) if (varyings.fields[i].optional && !read.exists(varyings.fields[i].field)) i];
				if (drop.length > 0) {
					for (f in vfs)
						eachExpr(f.body, x -> switch x.e {
							case ENew(args) if (x.t.match(TStruct(_)) && sameStruct(x.t, varyings)):
								var k = drop.length;
								while (k-- > 0)
									args.splice(drop[k], 1);
							case _:
						});
					var k = drop.length;
					while (k-- > 0)
						varyings.fields.splice(drop[k], 1);
				}
			case _:
		}
		for (f in all)
			deadLocals(f);
		switch vf.params.length > 0 ? vf.params[0].type : TVoid {
			case TStruct(input):
				var read = fieldsRead(vfs, input);
				var k = input.fields.length;
				while (k-- > 0)
					if (input.fields[k].optional && !read.exists(input.fields[k].field)) input.fields.splice(k, 1);
			case _:
		}
		for (f in [vf, ff]) {
			var read = localsRead(f.body);
			var k = f.params.length;
			while (k-- > 1)
				if (f.params[k].optional && !read.exists(f.params[k])) {
					f.params.splice(k, 1);
					f.fields.splice(k - 1, 1);
				}
		}
	}

	static function sameStruct(t:SType, s:SStruct):Bool
		return switch t {
			case TStruct(x): x == s;
			case _: false;
		}

	// a function and those it calls
	static function reachable(f:SFunction):Array<SFunction> {
		var out = [];
		function visit(g:SFunction) {
			if (out.contains(g)) return;
			out.push(g);
			eachExpr(g.body, x -> switch x.e {
				case ECall(h, _): visit(h);
				case _:
			});
		}
		visit(f);
		return out;
	}

	// the fields of a struct read anywhere in these functions (a value of it read whole: all of them)
	static function fieldsRead(fs:Array<SFunction>, s:SStruct):Map<String, Bool> {
		var read = new Map<String, Bool>();
		for (f in fs)
			eachExpr(f.body, x -> switch x.e {
				case EField(o, name) if (sameStruct(o.t, s)):
					for (g in s.fields)
						if (g.name == name) read.set(g.field, true);
				case _:
			});
		return read;
	}

	// the locals nothing reads, their declarations and assignments dropped (until none is left)
	static function deadLocals(f:SFunction) {
		while (true) {
			var read = localsRead(f.body);
			var changed = false;
			function keep(ss:Array<SStmt>):Array<SStmt> {
				var out = [];
				for (s in ss)
					switch s {
						case SDecl(v, _) | SAssign(v, _, _) if (!read.exists(v) && !f.params.contains(v)):
							changed = true;
						case SIf(c, a, b): out.push(SIf(c, keep(a), b == null ? null : keep(b)));
						case SWhile(c, body): out.push(SWhile(c, keep(body)));
						case _: out.push(s);
					}
				return out;
			}
			f.body = keep(f.body);
			if (!changed) return;
		}
	}

	static function localsRead(ss:Array<SStmt>):Map<SVar, Bool> {
		var read = new Map<SVar, Bool>();
		eachExpr(ss, x -> switch x.e {
			case ELocal(v): read.set(v, true);
			case _:
		});
		return read;
	}

	// each expression of statements, outermost first
	public static function eachExpr(ss:Array<SStmt>, f:SExpr->Void) {
		function e(x:SExpr) {
			f(x);
			switch x.e {
				case EField(a, _) | ESwizzle(a, _) | EColumn(a, _) | EUnop(_, a) | EConvert(a): e(a);
				case EIndex(a, i):
					e(a);
					e(i);
				case EBinop(_, a, b):
					e(a);
					e(b);
				case ECond(c, a, b):
					e(c);
					e(a);
					e(b);
				case ENew(args) | EBuiltin(_, args) | ECall(_, args):
					for (a in args)
						e(a);
				case EFloat(_) | EInt(_) | EBool(_) | ELocal(_):
			}
		}
		function s(st:SStmt)
			switch st {
				case SDecl(_, init): if (init != null) e(init);
				case SAssign(_, _, x) | SEval(x): e(x);
				case SIf(c, a, b):
					e(c);
					for (x in a)
						s(x);
					if (b != null) for (x in b)
						s(x);
				case SWhile(c, body):
					e(c);
					for (x in body)
						s(x);
				case SReturn(x): if (x != null) e(x);
				case SBreak | SContinue:
			}
		for (st in ss)
			s(st);
	}
}
