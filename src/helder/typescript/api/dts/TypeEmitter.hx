package helder.typescript.api.dts;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.TypeTools;

// Haxe types as TypeScript writes them, for helder's declaration files.
//
// Adapted from benmerckx/genes (src/genes/dts/TypeEmitter.hx, MIT, Copyright
// (c) 2019 Ben Merckx: LICENSE.genes beside this file), itself from
// nadako/hxtsdgen's TypeRenderer. Reworked for helder: the writer is a
// string buffer, a type is named only when one of the program's modules
// declares it (TypeWriter.declared, its import noted) and otherwise written
// out (a typedef's structure, an abstract's @:from types or the type under
// it, an enum abstract's values, a class no module declares `unknown`);
// @:typescript.type("...") (genes' @:genes.type) on a type, a field or an
// argument gives its TypeScript text, the type's parameters substituted;
// Any is unknown, ViewOf<R> a View.
typedef TypeWriter = {
	function write(code:String):Void;
	// the name a module declares a type as (imported when it is another module's), or null
	function declared(type:BaseType):Null<String>;
}

class TypeEmitter {
	public static function emitParams(writer:TypeWriter, params:Array<Type>, withConstraints = false) {
		final write = writer.write;
		if (params.length > 0) {
			write('<');
			var first = true;
			for (param in params) {
				if (!first) write(', ');
				first = false;
				emitType(writer, param);
				if (withConstraints)
					switch param {
						case TInst(_.get() => {kind: KTypeParameter(constraints)}, _) if (constraints.length > 0):
							write(' extends ');
							var f = true;
							for (c in constraints) {
								if (!f) write(' & ');
								f = false;
								emitType(writer, c);
							}
						default:
					}
			}
			write('>');
		}
	}

	// whether the type being written is one helder gives the program (a
	// result, a field, a callback's argument), not one it takes (an argument):
	// @:typescript.output("...") and @:typescript.input("...") are for one of them
	public static var output = false;

	// (@:typescript.type("...") on a type: its text, the type's parameters by name substituted)
	public static function template(meta:MetaAccess, names:Array<String>, args:Array<Type>, writer:TypeWriter):Null<String> {
		var text = typeMeta(meta);
		if (text == null) text = metaString(meta, output ? ":typescript.output" : ":typescript.input");
		if (text == null) return null;
		for (i in 0...names.length) {
			if (i >= args.length) break;
			var s = toString(writer, args[i]);
			text = new EReg("\\b" + names[i] + "\\b", "g").map(text, _ -> s);
		}
		return text;
	}

	public static function typeMeta(meta:Null<MetaAccess>):Null<String>
		return metaString(meta, ':typescript.type');

	static function metaString(meta:Null<MetaAccess>, name:String):Null<String> {
		if (meta == null) return null;
		return switch meta.extract(name) {
			case [{params: [{expr: EConst(CString(type))}]}]: type;
			default: null;
		}
	}

	public static function toString(writer:TypeWriter, type:Type):String {
		var buf = new StringBuf();
		emitType({write: buf.add, declared: writer.declared}, type);
		return buf.toString();
	}

	static var depth = 0;

	public static function emitType(writer:TypeWriter, type:Type, wrap = true) {
		if (depth > 10) {
			writer.write('any');
			return;
		}
		depth++;
		emit(writer, type, wrap);
		depth--;
	}

	static function emit(writer:TypeWriter, type:Type, wrap:Bool) {
		final write = writer.write;
		switch type {
			case TMono(r) if (r.get() != null):
				emitType(writer, r.get(), wrap);
			case TLazy(f):
				emitType(writer, f(), wrap);
			case TInst(ref = _.get() => cl, params):
				var t = template(cl.meta, [for (p in cl.params) p.name], params, writer);
				if (t != null) {
					write(t);
					return;
				}
				switch [cl, params] {
					case [{pack: [], name: 'String'}, _]:
						write('string');
					case [{pack: [], name: "Array"}, [elemT]]:
						var inner = toString(writer, elemT);
						write(~/^[A-Za-z0-9_.<>]+$/.match(inner) ? inner + '[]' : 'Array<' + inner + '>');
					case [{name: name, kind: KTypeParameter(_)}, _]:
						write(name);
					default:
						var name = writer.declared(cl);
						if (name == null) write('unknown') else {
							write(name);
							emitParams(writer, params);
						}
				}
			case TAbstract(_.get() => ab, params):
				var t = template(ab.meta, [for (p in ab.params) p.name], params, writer);
				if (t != null) {
					write(t);
					return;
				}
				switch [ab, params] {
					case [{pack: [], name: "Int" | "Float"}, _]:
						write('number');
					case [{pack: [], name: "Bool"}, _]:
						write('boolean');
					case [{pack: [], name: "Void"}, _]:
						write('void');
					case [{pack: [], name: "Any"}, _]:
						write('unknown');
					case [{pack: [], name: "Null"}, [realT]]:
						emitType(writer, realT);
						write(' | null');
					case [{pack: ["haxe", "extern"] | ['haxe'], name: "Rest"}, [t]]:
						emitType(writer, t);
						write('[]');
					case [{pack: ["haxe", "extern"], name: "EitherType"}, [aT, bT]]:
						emitType(writer, aT);
						write(' | ');
						emitType(writer, bT);
					default:
						var name = writer.declared(ab);
						if (name != null) {
							write(name);
							emitParams(writer, params);
						} else if (ab.meta.has(":coreType")) {
							write('any');
						} else if (ab.meta.has(":enum")) {
							var values = helder.typescript.api.Manifest.Types.enumValues(ab);
							if (values == null || values.length == 0) emitType(writer, ab.type.applyTypeParameters(ab.params, params)) else
								write([for (v in values) haxe.Json.stringify(v)].join(' | '));
						} else {
							emitType(writer, ab.type.applyTypeParameters(ab.params, params));
						}
				}
			case TAnonymous(_.get() => anon):
				var fields = anon.fields.copy();
				fields.sort((a, b) -> Context.getPosInfos(a.pos).min - Context.getPosInfos(b.pos).min);
				write('{');
				var first = true;
				for (field in fields) {
					write(first ? '' : ';');
					write(' ');
					first = false;
					write(ident(field.name));
					if (field.meta.has(':optional')) write('?');
					write(': ');
					var t = typeMeta(field.meta);
					if (t != null) write(t) else emitType(writer, unwrapOptional(field), false);
				}
				write(fields.length > 0 ? ' }' : '}');
			case TType(_.get() => dt, params):
				var t = template(dt.meta, [for (p in dt.params) p.name], params, writer);
				if (t != null) {
					write(t);
					return;
				}
				switch [dt, params] {
					case [{pack: [], name: "Null"}, [realT]]:
						emitType(writer, realT);
						write(' | null');
					default:
						var name = writer.declared(dt);
						if (name != null) {
							write(name);
							emitParams(writer, params);
						} else emitType(writer, dt.type.applyTypeParameters(dt.params, params), wrap);
				}
			case TFun(args, ret):
				if (wrap) write('(');
				write('(');
				output = !output;
				emitArgs(writer, args);
				output = !output;
				write(') => ');
				emitType(writer, ret);
				if (wrap) write(')');
			case TDynamic(null):
				write('any');
			case TDynamic(elemT):
				write('{[key: string]: ');
				emitType(writer, elemT);
				write('}');
			case TEnum(_.get() => et, _):
				var name = writer.declared(et);
				write(name == null ? 'unknown' : name);
			default:
				write('any');
		}
	}

	// (an optional field's Null<T>: its T, the ? says it)
	static function unwrapOptional(f:ClassField):Type
		return if (!f.meta.has(':optional')) f.type else switch f.type {
			case TAbstract(_.get() => {pack: [], name: "Null"}, [t]) | TType(_.get() => {pack: [], name: "Null"}, [t]): t;
			case t: t;
		}

	public static function ident(name:String):String
		return ~/^[A-Za-z_$][A-Za-z0-9_$]*$/.match(name) ? name : haxe.Json.stringify(name);

	public static function emitArgs(writer:TypeWriter, args:Array<{name:String, opt:Bool, t:Type}>, ?metas:Array<Null<MetaAccess>>) {
		final write = writer.write;
		// (trailing optional arguments only: Haxe's skipping aside, an optional
		// argument before a required one is required for TypeScript)
		var optionalFrom = args.length;
		for (i in 0...args.length) {
			final fromEnd = args.length - 1 - i;
			if (args[fromEnd].opt) optionalFrom = fromEnd else break;
		}
		for (i in 0...args.length) {
			if (i > 0) write(', ');
			var arg = args[i];
			if (isRest(arg.t)) write('...');
			write(arg.name != "" ? ident(arg.name) : 'arg$i');
			if (arg.opt && i >= optionalFrom) write("?");
			write(': ');
			var t = metas == null || metas[i] == null ? null : typeMeta(metas[i]);
			if (t != null) write(t) else emitType(writer, arg.opt && i >= optionalFrom ? unwrapNull(arg.t) : arg.t);
		}
	}

	static function unwrapNull(t:Type):Type
		return switch t {
			case TAbstract(_.get() => {pack: [], name: "Null"}, [x]) | TType(_.get() => {pack: [], name: "Null"}, [x]): x;
			case _: t;
		}

	static function isRest(type:Type)
		return switch type {
			case TType(_.get() => {module: 'haxe.extern.Rest', name: 'Rest'}, _) | TAbstract(_.get() => {module: 'haxe.Rest', name: 'Rest'}, _): true;
			default: false;
		}
}
#end
