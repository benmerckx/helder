package helder.typescript.api.dts;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import helder.typescript.api.dts.TypeEmitter;

using haxe.macro.TypeTools;

// A module's declarations written out: its classes (their members), its
// interfaces and type aliases (abstracts), its functions (a class's static).
//
// Adapted from benmerckx/genes (src/genes/dts/DefinitionEmitter.hx, MIT,
// Copyright (c) 2019 Ben Merckx: LICENSE.genes beside this file). Reworked for
// helder: no ES module emitter underneath (a buffer, Haxe's typed classes
// from helder.typescript.api.Modules), members chosen by the module, each
// with the `//` comment written above it in its Haxe source; an abstract is
// an interface when it is called (its @:op(a()) functions: call signatures)
// and a type alias of its @:from types or its values otherwise; a class
// given as a type an opaque one; enums and module statics are not emitted.
class DefinitionEmitter {
	final out = new StringBuf();
	final writer:TypeWriter;
	var indent = "";

	public function new(declared:BaseType->Null<String>) {
		writer = {write: out.add, declared: declared};
	}

	public function toString():String
		return out.toString();

	public function write(s:String)
		out.add(s);

	public function line(s:String = "") {
		out.add(s == "" ? "\n" : indent + s + "\n");
	}

	public function comment(lines:Array<String>) {
		for (l in lines)
			line("//" + (l == "" ? "" : " " + l));
	}


	function type(t:Type):String
		return TypeEmitter.toString(writer, t);

	// (a result, a field: what helder gives)
	function given(t:Type):String {
		TypeEmitter.output = true;
		var s = type(t);
		TypeEmitter.output = false;
		return s;
	}

	function params(ps:Array<TypeParameter>):String {
		if (ps.length == 0) return "";
		return "<" + [for (p in ps) p.name].join(", ") + ">";
	}

	// a class: its constructor, statics and members
	public function emitClass(name:String, cl:ClassType, statics:Array<ClassField>, members:Array<ClassField>, ctor:Null<ClassField>) {
		comment(Docs.of(cl.pos));
		line('export declare ' + (cl.isInterface ? 'interface' : 'class') + ' ' + name + params(cl.params) + ' {');
		indent = "\t";
		if (ctor != null)
			switch ctor.type {
				case TFun(args, _):
					comment(Docs.of(ctor.pos));
					line('constructor(' + args_(args, argMetas(ctor)) + ');');
				case _:
			}
		for (f in statics)
			emitField(f, true);
		for (f in members)
			emitField(f, false);
		indent = "";
		line('}');
	}

	function emitField(f:ClassField, isStatic:Bool) {
		var s = isStatic ? 'static ' : '';
		switch f.kind {
			case FMethod(_):
				var t = TypeEmitter.typeMeta(f.meta);
				comment(Docs.of(f.pos));
				if (t != null) {
					line(s + f.name + ': ' + t + ';');
					return;
				}
				switch Context.follow(f.type) {
					case TFun(args, ret):
						var r = TypeEmitter.typeMeta(returnMeta(f));
						line(s + f.name + params(f.params) + '(' + args_(args, argMetas(f)) + '): ' + (r != null ? r : given(ret)) + ';');
					case _:
				}
			case FVar(read, write):
				comment(Docs.of(f.pos));
				var readonly = write == AccNever || write == AccNo || write == AccCtor || read == AccInline || f.isFinal;
				var t = TypeEmitter.typeMeta(f.meta);
				line(s + (readonly ? 'readonly ' : '') + f.name + ': ' + (t != null ? t : given(f.type)) + ';');
		}
	}

	function args_(args:Array<{name:String, opt:Bool, t:Type}>, metas:Array<Null<MetaAccess>>):String {
		var buf = new StringBuf();
		TypeEmitter.emitArgs({write: buf.add, declared: writer.declared}, args, metas);
		return buf.toString();
	}

	// (a function's arguments' metadata, @:typescript.type among them: its typed expression's)
	static function argMetas(f:ClassField):Array<Null<MetaAccess>> {
		var e = try f.expr() catch (_:Dynamic) null;
		return switch e == null ? null : e.expr {
			case TFunction(fn): [for (a in fn.args) a.v.meta];
			case _: [];
		}
	}

	// (@:typescript.returns("...") on a function: its result's text)
	static function returnMeta(f:ClassField):Null<MetaAccess> {
		if (!f.meta.has(":typescript.returns")) return null;
		var m = f.meta.extract(":typescript.returns")[0];
		return {
			get: () -> [{name: ":typescript.type", params: m.params, pos: m.pos}],
			extract: n -> n == ":typescript.type" ? [{name: n, params: m.params, pos: m.pos}] : [],
			add: (_, _, _) -> {},
			remove: _ -> {},
			has: n -> n == ":typescript.type"
		};
	}

	// an abstract called as a function (@:op(a())): an interface of its call
	// signatures and public functions; one of those made from other values
	// (@:from casts: Read) its call signatures only, branded, and the type of
	// what makes one (<Name>From: its @:from types, which a TSX site's
	// component props take, JSX.LibraryManagedAttributes); another a type
	// alias: its @:typescript.type, its @:from types, or its values (an enum
	// abstract). The branded ones: in `from`.
	public final from:Array<String> = [];

	public function emitAbstract(name:String, ab:AbstractType) {
		comment(Docs.of(ab.pos));
		var calls = [], methods = [];
		if (ab.impl != null)
			for (f in ab.impl.get().statics.get()) {
				var call = Lambda.exists(f.meta.extract(":op"), m -> m.params != null && m.params.length == 1 && haxe.macro.ExprTools.toString(m.params[0]) == "a()");
				if (call) calls.push(f) else if (f.isPublic && !f.meta.has(":from") && !f.meta.has(":to") && !f.meta.has(":noCompletion") && takesThis(f)) methods.push(f);
			}
		var t = TypeEmitter.typeMeta(ab.meta);
		var casts = Lambda.exists(ab.from, f -> f.field != null);
		if (t != null || calls.length == 0) {
			line('export type ' + name + params(ab.params) + ' = ' + (t != null ? t : alias(ab)) + ';');
			return;
		}
		var brand = name.charAt(0).toLowerCase() + name.substr(1) + "Brand";
		if (casts) {
			line('declare const ' + brand + ': unique symbol;');
			methods = [];
		}
		line('export interface ' + name + params(ab.params) + ' {');
		indent = "\t";
		if (casts) line('readonly [' + brand + ']: ' + (ab.params.length > 0 ? ab.params[0].name : 'unknown') + ';');
		for (f in calls.concat(methods))
			switch Context.follow(f.type) {
				case TFun(args, ret):
					comment(Docs.of(f.pos));
					// (the abstract's value, this, first)
					var own = args.slice(1);
					line((calls.indexOf(f) >= 0 ? '' : f.name) + '(' + args_(own, argMetas(f).slice(1)) + '): ' + given(ret) + ';');
				case _:
			}
		indent = "";
		line('}');
		if (casts) {
			from.push(name);
			line();
			line('// what makes a ' + name + ': a TSX site\'s component props take one of these (JSX.LibraryManagedAttributes)');
			line('export type ' + name + 'From' + params(ab.params) + ' = ' + name + params(ab.params) + ' | ' + alias(ab) + ';');
		}
	}

	// (an abstract's function of its value: its first argument this)
	static function takesThis(f:ClassField):Bool
		return switch Context.follow(f.type) {
			case TFun(args, _): args.length > 0 && args[0].name == "this";
			case _: false;
		}

	// (what an abstract's alias is: its values, its @:from types, the type under it)
	function alias(ab:AbstractType):String {
		if (ab.meta.has(":enum")) {
			var values = helder.typescript.api.Manifest.Types.enumValues(ab);
			if (values != null && values.length > 0) return [for (v in values) haxe.Json.stringify(v)].join(' | ');
		}
		var from = [for (f in ab.from) if (f.field == null) type(f.t) else switch Context.follow(f.field.type) {
			case TFun(args, _) if (args.length > 0): type(args[0].t);
			case _: continue;
		}].filter(s -> s != "unknown");
		return from.length > 0 ? from.join(' | ') : type(ab.type);
	}

	// a class given as a type: opaque, made by helder only
	public function emitOpaque(name:String, cl:ClassType) {
		comment(Docs.of(cl.pos));
		line('export declare class ' + name + params(cl.params) + ' {');
		line('\tprivate readonly ' + name.charAt(0).toLowerCase() + name.substr(1) + ': never;');
		line('}');
	}

	// a typedef: its structure, named
	public function emitTypedef(name:String, dt:DefType) {
		comment(Docs.of(dt.pos));
		var t = TypeEmitter.typeMeta(dt.meta);
		line('export type ' + name + params(dt.params) + ' = ' + (t != null ? t : type(dt.type)) + ';');
	}

	// a function of the module: a class's static
	public function emitFunction(alias:String, cls:String, field:String) {
		line('export declare const ' + alias + ': typeof ' + cls + '.' + field + ';');
	}
}

// The `//` comment above a declaration in its Haxe source, its lines
// (metadata between them and the declaration skipped).
class Docs {
	static final files = new Map<String, Array<String>>();

	public static function of(pos:haxe.macro.Expr.Position):Array<String> {
		var info = Context.getPosInfos(pos);
		var lines = files.get(info.file);
		if (lines == null) {
			lines = try sys.io.File.getContent(info.file).split("\n") catch (_:Dynamic) [];
			files.set(info.file, lines);
		}
		// (the line the declaration starts on)
		var offset = 0, at = 0;
		while (at < lines.length && offset + lines[at].length + 1 <= info.min) {
			offset += lines[at].length + 1;
			at++;
		}
		var out = [];
		var k = at - 1;
		// (metadata and conditions between, over lines of their own: skipped)
		var j = k;
		while (j >= 0 && StringTools.trim(lines[j]) != "" && !StringTools.startsWith(StringTools.trim(lines[j]), "//"))
			j--;
		if (j < k && (StringTools.startsWith(StringTools.trim(lines[j + 1]), "@:") || StringTools.startsWith(StringTools.trim(lines[j + 1]), "#"))) k = j;
		while (k >= 0) {
			var l = StringTools.trim(lines[k]);
			if (!StringTools.startsWith(l, "//")) break;
			var text = l.substr(2);
			if (StringTools.startsWith(text, " ")) text = text.substr(1);
			out.unshift(StringTools.rtrim(text));
			k--;
		}
		// (a declaration's own line comment ends at its first blank comment line from the top: none here)
		return out;
	}
}
#end
