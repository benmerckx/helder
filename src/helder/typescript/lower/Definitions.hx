package helder.typescript.lower;

import helder.definition.Kernel;
import helder.asset.AssetCheck;
import helder.dev.KeepDefinition;
import helder.jobs.JobDefinition;
import helder.story.StoryDefinition;
import helder.gfx.shader.Ir;
import helder.gfx.shader.Names;
import helder.gfx.shader.Fold;
import helder.gfx.shader.ShaderDefinition;
import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;

using StringTools;

// Definitions in TypeScript (src/helder/compiler/DESIGN.md 2): a call of a
// function helder declares as one (helder/gfx's shader: `@definition` in
// its declaration, the handler of the same name) is compiled when the
// program is: its argument's kernel tree made here from the checked AST
// (TsAdapter, which rejects what is not static at its line), the handler
// run (the same Haxe class Haxe's macro runs: helder.gfx.shader.
// ShaderDefinition), and its output passed to the function as its last
// argument, JSON (helder/gfx's shader builds the value of it).
class Definitions {
	// the definitions by module and name
	static final known = ["helder/gfx" => ["shader"], "helder/dev" => ["keep"], "helder/story" => ["story"], "helder/jobs" => ["job"], "helder/asset" => TsAssets.KINDS];

	final src:Project;
	final defined:String->Null<String>;

	public function new(src:Project, defined:String->Null<String>) {
		this.src = src;
		this.defined = defined;
	}

	// a define's value (-D), or null
	public function define(name:String):Null<String>
		return defined(name);

	// whether a call is a definition's (one of a declared module's is not
	// lowered as a call into helder's API: helder/dev's keep)
	public function defines(n:Node):Bool
		return definition(n) != null || variantOf(n) != null;

	// (a slot object's variant: <object>.variant(options), the object a
	// module-level const made by helder/gfx's slots(...), or with(...) of one)
	function variantOf(n:Node):Null<Node> {
		var callee = n.expression();
		if (callee.kind != KindPropertyAccessExpression || callee.name().text != "variant") return null;
		return new TsAdapter(src, defined, "shader").slotsSource(callee.expression()) != null ? callee.expression() : null;
	}

	function definition(n:Node):Null<{module:String, name:String, specifier:Node}> {
		var callee = n.expression();
		if (callee.kind != KindIdentifier) return null;
		var from = Scope.imported(callee.file, callee.text);
		return from == null || !known.exists(from.module) || !known.get(from.module).contains(from.name) ? null : from;
	}

	// a definition's call: what its handler made (null: not one)
	public function call(n:Node):Null<DefinitionCall> {
		var from = definition(n);
		if (from == null) {
			var self = variantOf(n);
			if (self == null) return null;
			var a = new TsAdapter(src, defined, "shader");
			var def = SlotsDef.read(a.slotsSource(self), a);
			var args = n.arguments() ?? [];
			if (args.length > 1) a.error("variant takes one argument, an object literal of options", n);
			return Generated(shaderJson(new ShaderDefinition().variant(def, args.length == 0 ? null : a.node(args[0]), a, n)));
		}
		var args = n.arguments() ?? [];
		var a = new TsAdapter(src, defined, from.name);
		// (keep(key, init): its arguments as one array)
		if (from.name == "keep") {
			var slot = new KeepDefinition().generate(new KNode(KArray([for (x in args) a.node(x)]), n), a);
			var init:Node = slot.init.source;
			var text = n.file.text();
			function source(x:Node):String
				return text.substring(n.file.skipTrivia(x.pos), x.end);
			// (as a signal's: its type by the type argument written, its initial value's source hashed)
			var type = "ts:" + [for (t in n.typeArguments() ?? []) source(t)].join(",");
			return Keep(slot.key, type, haxe.crypto.Md5.encode(source(init)).substr(0, 8), init);
		}
		if (from.module == "helder/asset") {
			var a = new TsAdapter(src, defined, "Asset." + from.name);
			if (args.length != 1) a.error("takes the file's path, a string literal", n);
			var path = new AssetCheck(from.name).generate(a.node(args[0]), a);
			return AssetCall(from.name, path, TsAssets.devFile(TsAssets.find(src, from.name, path, n, defined), defined));
		}
		if (from.name == "job") {
			var j = new TsJobAdapter(src, defined);
			if (args.length != 1) j.error("takes one argument, a module-level function", n);
			var s = new JobDefinition().generate(j.node(args[0]), j);
			return Job(s.source, [for (c in s.captures) c.name]);
		}
		if (args.length != 1) a.error('${from.name} takes one argument, an object literal', n);
		var arg = a.node(args[0]);
		return switch from.name {
			case "shader": Generated(shaderJson(new ShaderDefinition().generate(arg, a)));
			case "story":
				new StoryDefinition().generate(arg, a);
				defined("helder.release") != null ? Dropped : Checked;
			case _: null;
		}
	}

	static function shaderJson(out:ShaderOutput):String {
		var p = out.program;
		function code(s:StageCode):Dynamic {
			var o:Dynamic = {};
			for (c in s.code)
				Reflect.setField(o, c.language, c.text);
			o.bindings = [
				for (b in s.bindings)
					b.uniform ? ({name: b.name, slot: b.slot, kind: 0, size: b.size} : Dynamic) : {name: b.name, slot: b.slot, kind: 1}
			];
			return o;
		}
		function kind(t:SType):String
			return switch t {
				case TInt: "i";
				case TVec(n): Std.string(n);
				case TMat4: "m";
				case _: "f";
			}
		return haxe.Json.stringify({
			vertexCode: code(out.vertex),
			fragmentCode: code(out.fragment),
			layout: [
				{
					stride: out.stride,
					attributes: [
						for (i in 0...out.attributes.length)
							{location: i, format: out.attributes[i].components - 1, offset: out.attributes[i].offset}
					]
				}
			],
			uniforms: [for (u in p.uniforms) {name: u.struct.name, binding: u.binding, size: u.size}],
			textures: [for (t in p.textures) {name: t.name, binding: t.slot}],
			attributes: out.attributes,
			stride: out.stride,
			params: [
				for (b in out.params)
					switch b.resource {
						case RTexture(t): ({param: b.name, texture: {name: t.name, binding: t.slot}} : Dynamic);
						case RUniform(u): {
								param: b.name,
								block: {name: u.struct.name, binding: u.binding, size: u.size},
								fields: [
									for (i in 0...u.struct.fields.length)
										{field: u.struct.fields[i].field, kind: kind(u.struct.fields[i].type), offset: u.offsets[i]}
								]
							};
					}
			]
		});
	}
}

// What a definition's call is lowered to: its handler's output as the
// function's last argument (JSON); keep's slot (Interop.hotKeep under -D
// hxmc.dev, else init()); the call itself, its argument checked (story's);
// nothing (a story in a release build).
enum DefinitionCall {
	Generated(json:String);
	Keep(key:String, type:String, source:String, init:Node);
	// (its argument checked: the call lowered as helder's API's, story's Stories.define)
	Checked;
	// (a release build's: undefined, its argument not lowered)
	Dropped;
	// (job(f): f's declaration, the constants it reads)
	Job(fn:Node, captures:Array<String>);
	// (image(path)...: the kind, the path, the file where the program reads it from disk)
	AssetCall(kind:String, path:String, file:Null<String>);
}

// What a name of a file is bound to at its top level: an import (its
// module's specifier and the name it exports), a function or a type alias
// declared there, a constant.
class Scope {
	public static function imported(file:SourceFile, name:String):Null<{module:String, name:String, specifier:Node}> {
		for (s in file.root.statements())
			if (s.kind == KindImportDeclaration && s.importClause() != null) {
				var bindings = s.importClause().namedBindings();
				if (bindings == null || bindings.kind != KindNamedImports) continue;
				for (e in bindings.elements())
					if (e.name().text == name)
						return {module: s.moduleSpecifier().text, name: e.propertyName() != null ? e.propertyName().text : name, specifier: s.moduleSpecifier()};
			}
		return null;
	}

	// a top-level declaration of the file by name and kind (exported or not)
	public static function declared(file:SourceFile, name:String, kind:Kind):Null<Node> {
		for (s in file.root.statements()) {
			if (s.kind == kind && s.name() != null && s.name().text == name) return s;
			if (kind == KindVariableDeclaration && s.kind == KindVariableStatement)
				for (d in s.declarationList().declarations())
					if (d.name().kind == KindIdentifier && d.name().text == name) return d;
		}
		return null;
	}
}

// The shader definition's TypeScript adapter (ShaderAdapter), Lower's
// counterpart: a stage's function and the functions it calls, from the
// AST to the IR, typed by their annotations (the program is checked: the
// types are what tsgo agreed to) as Lower types Haxe: numbers are Float,
// helder/gfx's Vec2, Vec3, Vec4, Mat4 and Texture2D the math types, type
// aliases of object types structs (named after the alias), the methods add,
// sub, mul, div and neg the operators (c = c.add(x) is Haxe's c += x on a
// vector: c = c + x). Names are allocated in Lower's
// order (a function's parameters' types, its name, its result's type, its
// body), so that the same functions print the same text from either
// language.
class TsAdapter implements ShaderAdapter {
	final src:Project;
	final defines:String->Null<String>;
	final what:String;
	final names = new Names();
	final structs = new Map<String, SStruct>();
	final building = new Map<String, Bool>();
	final functions = new Map<String, SFunction>();
	final active:Array<String> = [];
	final vars = new Map<SFunction, Array<SVar>>();
	var varyings:Null<SType>;
	var anonymous = 0;

	var fn:SFunction;
	var scopes:Array<Map<String, SVar>>;
	var localNames:Map<String, Bool>;
	var positionLocals:Map<SVar, Bool>;
	// the stage's object of parameters (its fields are its parameters: p.frame)
	var paramsObject:Null<{name:String, fields:Map<String, SVar>}>;
	var temps = 0;
	// a slot object's variant (useSlots): its options and slots; the stage's
	// third parameter's name (the object); the slots lowered; the loop
	// variables of unrolled loops (constants)
	var slots:Null<SlotsUse>;
	var slotsSelf:Null<String>;
	final slotFunctions = new Map<String, SFunction>();
	final constants = new Map<String, SExpr>();

	public function new(src:Project, defines:String->Null<String>, what:String) {
		this.src = src;
		this.defines = defines;
		this.what = what;
	}

	public function error(message:String, pos:KPos):Dynamic
		return src.fail(pos, '$what: $message');

	public function defined(name:String):Null<String>
		return name == "target.name" ? defines(name) ?? "hxmc" : defines(name);

	public function finish()
		names.unhide(vars);

	// --- the argument's kernel tree

	public function node(n:Node):KNode {
		var pos:KPos = n;
		return new KNode(switch n.kind {
			case KindParenthesizedExpression | KindAsExpression | KindSatisfiesExpression: return node(n.expression());
			case KindStringLiteral | KindNoSubstitutionTemplateLiteral: KString(n.text);
			case KindNumericLiteral: KFloat(number(n.text));
			case KindTrueKeyword: KBool(true);
			case KindFalseKeyword: KBool(false);
			case KindNullKeyword: KNull;
			case KindObjectLiteralExpression:
				var fields:Array<KField> = [];
				function add(f:KField) {
					fields = fields.filter(g -> g.name != f.name);
					fields.push(f);
				}
				for (p in n.properties())
					switch p.kind {
						case KindPropertyAssignment if (p.name().kind == KindIdentifier || p.name().kind == KindStringLiteral):
							add({name: p.name().text, node: node(p.initializer())});
						case KindShorthandPropertyAssignment:
							add({name: p.name().text, node: node(p.name())});
						case KindMethodDeclaration if (p.name().kind == KindIdentifier):
							add({name: p.name().text, node: new KNode(KFunction(new KFunction(null, params(p), p, p)), p)});
						// (a slot object spread: its slots(...)'s fields, those after it replacing theirs)
						case KindSpreadAssignment:
							var d = slotsSource(p.expression());
							if (d == null) notStatic(p);
							switch d.value {
								case KObject(fs): for (f in fs) add(f);
								case _: notStatic(p);
							}
						case _: notStatic(p);
					}
				KObject(fields);
			case KindArrayLiteralExpression: KArray([for (e in n.elements()) node(e)]);
			case KindArrowFunction | KindFunctionExpression:
				KFunction(new KFunction(n.kind == KindFunctionExpression && n.name() != null ? n.name().text : null, params(n), n, n));
			// (a module-level function, here or imported: by its name)
			case KindIdentifier if (Scope.declared(n.file, n.text, KindFunctionDeclaration) != null || Scope.imported(n.file, n.text) != null): KRef(n.text);
			case _: notStatic(n);
		}, pos);
	}

	// a slot object's definition: the argument of the slots(...) call a
	// module-level const was made by (here or imported), with(...)'s
	// overrides applied, a spread object's fields; null: not one
	public function slotsSource(e:Node):Null<KNode> {
		var x = strip(e);
		switch x.kind {
			case KindCallExpression if (strip(x.expression()).kind == KindPropertyAccessExpression && strip(x.expression()).name().text == "with"):
				var base = slotsSource(strip(x.expression()).expression());
				var args = x.arguments() ?? [];
				if (base == null || args.length != 1) return null;
				var over = node(args[0]);
				return switch [base.value, over.value] {
					case [KObject(bs), KObject(os)]:
						// (checked as Haxe's with: the same diagnostics)
						SlotsDef.read(base, this).with(over, this);
						// (the base's fields in order, an override in its field's place)
						new KNode(KObject([for (b in bs) Lambda.find(os, o -> o.name == b.name) ?? b]), x);
					case _: null;
				}
			case KindCallExpression if (strip(x.expression()).kind == KindIdentifier):
				var callee = strip(x.expression());
				var from = Scope.imported(callee.file, callee.text);
				var args = x.arguments() ?? [];
				if (from == null || from.module != "helder/gfx" || from.name != "slots" || args.length != 1) return null;
				return node(args[0]);
			case KindIdentifier:
				var d = Scope.declared(x.file, x.text, KindVariableDeclaration);
				var from = d == null ? Scope.imported(x.file, x.text) : null;
				if (from != null) d = declaration(from.specifier, from.name, KindVariableDeclaration);
				if (d == null || d.initializer() == null) return null;
				var init = strip(d.initializer());
				return init.kind == KindCallExpression ? slotsSource(init) : null;
			case _:
				return null;
		}
	}

	// (a numeric literal's value: 0x, 0o and 0b ones, separators)
	static function number(text:String):Float {
		var t = text.split("_").join("");
		var lower = t.toLowerCase();
		function digits(base:Int):Float {
			var v = 0.0;
			for (i in 2...t.length)
				v = v * base + "0123456789abcdef".indexOf(lower.charAt(i));
			return v;
		}
		return lower.startsWith("0x") ? digits(16) : lower.startsWith("0o") ? digits(8) : lower.startsWith("0b") ? digits(2) : Std.parseFloat(t);
	}

	static function params(f:Node):Array<String>
		return [for (p in f.parameters()) p.name().kind == KindIdentifier ? p.name().text : "_"];

	function notStatic(n:Node):Dynamic
		return error(n.file.slice(n.file.skipTrivia(n.pos), n.end)
			+ " is not static (a definition takes literals, object and array literals, functions, and module-level constants and definitions)", n);

	// --- functions

	public function lowerStage(k:KFunction, name:String):SFunction {
		var f:Node = k.source;
		return lower(f.file.path + ":" + f.pos, name, f, Stage);
	}

	public function useSlots(use:SlotsUse)
		slots = use;

	function lower(key:String, name:String, f:Node, kind:LowerKind, ?input:SType):SFunction {
		var g = functions.get(key);
		if (g != null) return g;
		if (active.contains(key)) error("recursion: " + active.slice(active.indexOf(key)).concat([key]).map(display).join(" -> ") + " (shader functions cannot recurse)", f);
		active.push(key);
		var saved = {fn: fn, scopes: scopes, names: localNames, positions: positionLocals, object: paramsObject, self: slotsSelf};
		scopes = [new Map()];
		localNames = new Map();
		positionLocals = new Map();
		paramsObject = null;
		slotsSelf = null;
		var vs = [];
		var ps = f.parameters();
		var params = [], fields = [];
		var stage = kind != Plain;
		var count = ps.length;
		// (a slot object's stage: its third parameter the object, m.options.x and m.color(s, p))
		if (kind == Stage && slots != null && count == 3 && ps[2].name().kind == KindIdentifier) {
			slotsSelf = ps[2].name().text;
			if (ps[2].type() != null) selfType = ps[2].type();
			count = 2;
		}
		if (stage && count > 2) error('a ${kind == Slot ? "slot" : "stage"} takes its input and one object of parameters ({frame: Frame, image: Texture2D}), not ${count - 1}', f);
		for (i in 0...count) {
			var p = ps[i];
			if (p.name().kind != KindIdentifier) error("a destructuring is not supported in a shader", p);
			if (!stage || i == 0) {
				var t = p.type() != null ? typeOf(p.type()) : kind == Slot && i == 0 && input != null ? input : kind == Stage && i == 0 && varyings != null
					&& f.kind != KindFunctionDeclaration ? varyings : error('the parameter ${p.name().text} needs its type', p);
				params.push(declare(p.name().text, t, p, vs, true));
				continue;
			}
			// (a stage's object of parameters: its fields the parameters, in order)
			var members = p.type() == null ? null : objectMembers(p.type());
			if (members == null)
				error('${p.name().text}: a stage\'s parameters are an object of uniform blocks and textures ({frame: Frame, image: Texture2D})' + (p.type() == null ? ", its type written" : ""), f);
			paramsObject = {name: p.name().text, fields: new Map()};
			for (m in members) {
				if (m.kind != KindPropertySignature || m.type() == null) error('${p.name().text}: the parameters are fields, each typed', m);
				var s = declare(m.name().text, typeOf(m.type()), m, vs, true);
				s.optional = optional(m);
				// (a field, not a local: p.frame)
				scopes[0].remove(m.name().text);
				paramsObject.fields.set(m.name().text, s);
				params.push(s);
				fields.push(m.name().text);
			}
		}
		var ret = f.type() != null ? typeOf(f.type()) : null;
		g = new SFunction(names.global(name), params, ret ?? TVoid);
		g.fields = fields;
		if (ret == TTexture) error('$name: a texture is not a result (pass the parameter on)', f);
		fn = g;
		vars.set(g, vs);
		var body = [];
		var b = f.body();
		if (b == null) error('$name has no body', f);
		if (b.kind == KindBlock) block(b, body) else body.push(SReturn(retValue(b, body)));
		g.body = body;
		if (ret == null) inferred(g, f);
		if (kind == Stage && varyings == null) varyings = g.ret;
		fn = saved.fn;
		scopes = saved.scopes;
		localNames = saved.names;
		positionLocals = saved.positions;
		paramsObject = saved.object;
		slotsSelf = saved.self;
		active.pop();
		functions.set(key, g);
		return g;
	}

	// (a result's type not written: its returns')
	function inferred(g:SFunction, f:Node) {
		var found:Null<SType> = null;
		function visit(ss:Array<SStmt>)
			for (s in ss)
				switch s {
					case SReturn(e) if (e != null): if (found == null) found = e.t;
					case SIf(_, a, b):
						visit(a);
						if (b != null) visit(b);
					case SWhile(_, body): visit(body);
					case _:
				}
		visit(g.body);
		if (found != null) g.ret = found;
	}

	function retValue(e:Node, out:Array<SStmt>):SExpr {
		var x = expr(e, out, fn.ret == TVoid ? null : fn.ret);
		return fn.ret == TVoid ? x : coerce(x, fn.ret, e);
	}

	static function display(key:String):String
		return key.substr(key.lastIndexOf("/") + 1);

	function declare(name:String, t:SType, at:Node, list:Array<SVar>, param = false):SVar {
		if (t == TVoid) error('$name has no value', at);
		if (t == TTexture && !param) error('$name: a texture is a parameter, not a local', at);
		var s = new SVar(Names.unique(Names.sanitize(name), n -> !localNames.exists(n) && (t != TTexture || !localNames.exists(n + "_smp"))), t);
		localNames.set(s.name, true);
		if (t == TTexture) localNames.set(s.name + "_smp", true);
		scopes[scopes.length - 1].set(name, s);
		list.push(s);
		return s;
	}

	function temp(t:SType):SVar {
		var s = new SVar(Names.unique("t" + temps++, n -> !localNames.exists(n)), t);
		localNames.set(s.name, true);
		vars.get(fn).push(s);
		return s;
	}

	function find(name:String):Null<SVar> {
		var i = scopes.length;
		while (i-- > 0) {
			var v = scopes[i].get(name);
			if (v != null) return v;
		}
		return null;
	}

	// --- types

	function typeOf(t:Node):SType {
		return switch t.kind {
			case KindNumberKeyword: TFloat;
			case KindBooleanKeyword: TBool;
			case KindVoidKeyword: TVoid;
			case KindParenthesizedType: typeOf(t.type());
			case KindTypeLiteral:
				var key = t.file.path + ":" + t.pos;
				var s = structs.get(key);
				TStruct(s != null ? s : struct(key, "S" + anonymous++, t));
			case KindTypeReference if (t.typeName().kind == KindIdentifier):
				var n = t.typeName().text;
				var from = Scope.imported(t.file, n);
				if (from != null && from.module == "helder/gfx")
					return switch from.name {
						case "Vec2": TVec(2);
						case "Vec3": TVec(3);
						case "Vec4": TVec(4);
						case "Mat4": TMat4;
						case "Texture2D": TTexture;
						case other: error('$other is not a shader type (number, boolean, Vec2, Vec3, Vec4, Mat4, Texture2D and type aliases of object types of them)', t);
					}
				var alias = from != null ? declaration(from.specifier, from.name, KindTypeAliasDeclaration) : Scope.declared(t.file, n, KindTypeAliasDeclaration);
				if (alias == null) error('$n is not a shader type (number, boolean, Vec2, Vec3, Vec4, Mat4, Texture2D and type aliases of object types of them)', t);
				var body = alias.type();
				if (body.kind != KindTypeLiteral) return typeOf(body);
				var key = alias.file.path + ":" + alias.pos;
				var s = structs.get(key);
				TStruct(s != null ? s : struct(key, n, body));
			case _: error(t.file.slice(t.file.skipTrivia(t.pos), t.end) + " is not a shader type (number, boolean, Vec2, Vec3, Vec4, Mat4, Texture2D and type aliases of object types of them)", t);
		}
	}

	// an object type's members, through type aliases (null: not one)
	function objectMembers(t:Node):Null<Array<Node>> {
		return switch t.kind {
			case KindParenthesizedType: objectMembers(t.type());
			case KindTypeLiteral: t.members();
			case KindTypeReference if (t.typeName().kind == KindIdentifier):
				var n = t.typeName().text;
				var from = Scope.imported(t.file, n);
				if (from != null && from.module == "helder/gfx") return null;
				var alias = from != null ? declaration(from.specifier, from.name, KindTypeAliasDeclaration) : Scope.declared(t.file, n, KindTypeAliasDeclaration);
				alias == null ? null : objectMembers(alias.type());
			case _: null;
		}
	}

	// (a property signature's ?: tsgo's postfix token)
	static function optional(m:Node):Bool
		return m.postfixToken() != null && m.postfixToken().kind == KindQuestionToken;

	function struct(key:String, name:String, literal:Node):SStruct {
		if (building.exists(key)) error('$name contains itself', literal);
		building.set(key, true);
		var fields:Array<SField> = [];
		for (m in literal.members()) {
			if (m.kind != KindPropertySignature || m.type() == null) error('$name: a struct has fields of shader types (no methods, each typed)', m);
			var t = typeOf(m.type());
			if (t == TTexture) error('$name.${m.name().text}: a texture is not a struct field (it is a parameter)', m);
			fields.push({
				name: Names.unique(Names.sanitize(m.name().text), n -> !Lambda.exists(fields, g -> g.name == n)),
				field: m.name().text,
				type: t,
				position: false,
				optional: optional(m)
			});
		}
		if (fields.length == 0) error('$name has no fields', literal);
		building.remove(key);
		var s = new SStruct(names.global(name), name, fields);
		structs.set(key, s);
		return s;
	}

	// (a name another module of the program exports: its declaration there)
	function declaration(specifier:Node, name:String, kind:Kind):Null<Node> {
		var path = src.resolve(specifier);
		if (path == null) return null;
		for (f in src.files)
			if (f.path == path) return Scope.declared(f, name, kind);
		return null;
	}

	// --- statements

	function block(b:Node, out:Array<SStmt>) {
		scopes.push(new Map());
		for (s in b.statements())
			stmt(s, out);
		scopes.pop();
	}

	function body(n:Node):Array<SStmt> {
		var out = [];
		if (n.kind == KindBlock) block(n, out) else {
			scopes.push(new Map());
			stmt(n, out);
			scopes.pop();
		}
		return out;
	}

	function stmt(n:Node, out:Array<SStmt>) {
		switch n.kind {
			case KindBlock: block(n, out);
			case KindVariableStatement:
				for (d in n.declarationList().declarations()) {
					if (d.name().kind != KindIdentifier) error("a destructuring is not supported in a shader", d);
					var init = d.initializer();
					var want = d.type() != null ? typeOf(d.type()) : null;
					var p = init == null ? null : positionArg(init);
					var x = init == null ? null : expr(p ?? init, out, want);
					var t = want ?? (x != null ? x.t : error('${d.name().text} needs a type or a value', d));
					var s = declare(d.name().text, t, d, vars.get(fn));
					if (p != null) positionLocals.set(s, true);
					out.push(SDecl(s, x == null ? null : coerce(x, t, init)));
				}
			case KindExpressionStatement:
				var e = strip(n.expression());
				switch e.kind {
					case KindBinaryExpression if (isAssign(e.operatorToken().kind)): assign(e, out);
					case KindPrefixUnaryExpression | KindPostfixUnaryExpression if (e.unaryOperator() == KindPlusPlusToken
						|| e.unaryOperator() == KindMinusMinusToken):
						var v = target(e.operand());
						out.push(SAssign(v, e.unaryOperator() == KindPlusPlusToken ? Add : Sub, one(v.type)));
					case _:
						var x = expr(e, out);
						switch x.e {
							case ECall(_) | EBuiltin("discard", _): out.push(SEval(x));
							case _:
						}
				}
			case KindIfStatement:
				var c = coerce(expr(n.expression(), out), TBool, n.expression());
				// (a variant's test of a constant: the branch it takes alone)
				switch c.e {
					case EBool(k) if (slots != null):
						if (k) inline_(n.thenStatement(), out) else if (n.elseStatement() != null) inline_(n.elseStatement(), out);
					case _:
						out.push(SIf(c, body(n.thenStatement()), n.elseStatement() == null ? null : body(n.elseStatement())));
				}
			case KindWhileStatement:
				var pre = [];
				var c = coerce(expr(n.expression(), pre), TBool, n.expression());
				if (pre.length == 0) out.push(SWhile(c, body(n.statement()))) else
					out.push(SWhile({e: EBool(true), t: TBool}, pre.concat([SIf({e: EUnop(Not, c), t: TBool}, [SBreak], null)]).concat(body(n.statement()))));
			case KindForStatement if (slots != null && unrolled(n, out)):
			case KindForStatement:
				// for (init; cond; incr) body: init, then while (cond) { body; incr }
				scopes.push(new Map());
				if (n.initializer() != null) {
					var i = n.initializer();
					if (i.kind == KindVariableDeclarationList) for (d in i.declarations()) {
						var x = expr(d.initializer(), out, d.type() != null ? typeOf(d.type()) : null);
						var s = declare(d.name().text, x.t, d, vars.get(fn));
						s.assigned = true;
						out.push(SDecl(s, x));
					} else stmtOf(i, out);
				}
				var c = n.condition() == null ? {e: EBool(true), t: TBool} : coerce(expr(n.condition(), out), TBool, n.condition());
				var inner = body(n.statement());
				if (n.incrementor() != null) stmtOf(n.incrementor(), inner);
				out.push(SWhile(c, inner));
				scopes.pop();
			case KindReturnStatement:
				out.push(SReturn(n.expression() == null ? null : retValue(n.expression(), out)));
			case KindBreakStatement: out.push(SBreak);
			case KindContinueStatement: out.push(SContinue);
			case KindEmptyStatement:
			case _: error("this statement is not supported in a shader", n);
		}
	}

	// (an expression as a statement)
	function stmtOf(e:Node, out:Array<SStmt>) {
		var x = strip(e);
		switch x.kind {
			case KindBinaryExpression if (isAssign(x.operatorToken().kind)): assign(x, out);
			case KindPrefixUnaryExpression | KindPostfixUnaryExpression:
				var v = target(x.operand());
				out.push(SAssign(v, x.unaryOperator() == KindPlusPlusToken ? Add : Sub, one(v.type)));
			case _: error("this expression is not a statement in a shader", e);
		}
	}

	static function isAssign(k:Kind):Bool
		return k == KindEqualsToken || k == KindPlusEqualsToken || k == KindMinusEqualsToken || k == KindAsteriskEqualsToken || k == KindSlashEqualsToken;

	function assign(e:Node, out:Array<SStmt>):SVar {
		var v = target(e.left());
		var r = strip(e.right());
		var op:Null<SBinop> = switch e.operatorToken().kind {
			case KindPlusEqualsToken: Add;
			case KindMinusEqualsToken: Sub;
			case KindAsteriskEqualsToken: Mul;
			case KindSlashEqualsToken: Div;
			case _: null;
		}
		out.push(SAssign(v, op, coerce(expr(e.right(), out), v.type, e.right())));
		return v;
	}

	function target(e:Node):SVar {
		var x = strip(e);
		return switch x.kind {
			case KindIdentifier:
				var s = find(x.text);
				if (s == null) error('${x.text} is not a local of this function', x);
				if (s.type == TTexture) error('${x.text}: a texture parameter is not assigned', x);
				s.assigned = true;
				s;
			case KindPropertyAccessExpression | KindElementAccessExpression: error("shader values are immutable: assign to a local, not to a field", x);
			case _: error("shader code assigns to locals only", x);
		}
	}

	// --- expressions

	function expr(n:Node, out:Array<SStmt>, ?want:SType):SExpr {
		return switch n.kind {
			case KindParenthesizedExpression | KindAsExpression | KindSatisfiesExpression | KindNonNullExpression: expr(n.expression(), out, want);
			case KindNumericLiteral:
				var f = Std.parseFloat(n.text);
				if (!Math.isFinite(f)) error('${n.text} is not a finite number', n);
				{e: EFloat(f), t: TFloat};
			case KindTrueKeyword: {e: EBool(true), t: TBool};
			case KindFalseKeyword: {e: EBool(false), t: TBool};
			case KindStringLiteral | KindNoSubstitutionTemplateLiteral | KindTemplateExpression: error("a String is not a shader value", n);
			case KindNullKeyword: error("null is not a shader value", n);
			case KindThisKeyword: error("a shader function has no this", n);
			case KindIdentifier: identifier(n);
			case KindBinaryExpression if (isAssign(n.operatorToken().kind)): local(assign(n, out));
			case KindBinaryExpression: binary(n, out);
			case KindPrefixUnaryExpression:
				switch n.unaryOperator() {
					case KindMinusToken:
						var v = expr(n.operand(), out);
						if (v.t != TFloat && v.t != TInt) error('-: a ${Names.typeName(v.t)} (a vector\'s is .neg())', n);
						{e: EUnop(Neg, v), t: v.t};
					case KindPlusToken: expr(n.operand(), out, want);
					case KindExclamationToken:
						var v = {e: EUnop(Not, coerce(expr(n.operand(), out), TBool, n.operand())), t: TBool};
						slots != null ? Fold.expr(v) : v;
					case _: error("not supported in a shader", n);
				}
			case KindConditionalExpression:
				var cond = coerce(expr(n.condition(), out), TBool, n.condition());
				switch cond.e {
					case EBool(k) if (slots != null): return expr(k ? n.whenTrue() : n.whenFalse(), out, want);
					case _:
				}
				var pa = [], pb = [];
				var x = expr(n.whenTrue(), pa, want);
				var t = want ?? x.t;
				if (t == TTexture) error("a texture is chosen by no condition (pass the parameter on)", n);
				x = coerce(x, t, n.whenTrue());
				var y = coerce(expr(n.whenFalse(), pb, t), t, n.whenFalse());
				if (pa.length == 0 && pb.length == 0) {e: ECond(cond, x, y), t: t} else {
					var tmp = temp(t);
					tmp.assigned = true;
					out.push(SDecl(tmp, null));
					out.push(SIf(cond, pa.concat([SAssign(tmp, null, x)]), pb.concat([SAssign(tmp, null, y)])));
					local(tmp);
				}
			case KindCallExpression: call(n, out, want);
			case KindPropertyAccessExpression: field(n, out);
			case KindObjectLiteralExpression:
				var s = switch want {
					case TStruct(s): s;
					case _: error("an object literal is a shader value where its struct's type is known (a typed result, local or parameter)", n);
				}
				var props = n.properties();
				var args = [
					for (f in s.fields) {
						var given = Lambda.find(props, p -> p.name() != null && p.name().text == f.field);
						if (given == null && !f.optional) error('${s.path}: the field ${f.field} is not given', n);
						given;
					}
				];
				if (props.length != args.filter(x -> x != null).length) error('${s.path} is built with all its fields, no others', n);
				var xs = [];
				for (i in 0...args.length) {
					var p = args[i];
					// (an optional field left out: zero)
					if (p == null) {
						xs.push(Names.zero(s.fields[i].type));
						continue;
					}
					var v = p.kind == KindShorthandPropertyAssignment ? p.name() : p.initializer();
					var inner = positionArg(v);
					if (inner != null) {
						s.fields[i].position = true;
						v = inner;
					} else if (strip(v).kind == KindIdentifier && find(strip(v).text) != null && positionLocals.exists(find(strip(v).text))) s.fields[i].position = true;
					xs.push(coerce(expr(v, out, s.fields[i].type), s.fields[i].type, v));
				}
				{e: ENew(xs), t: TStruct(s)};
			case KindArrayLiteralExpression | KindElementAccessExpression: error("arrays are not supported in a shader (yet)", n);
			case KindArrowFunction | KindFunctionExpression: error("a closure is not supported in a shader", n);
			case _: error("not supported in a shader", n);
		}
	}

	function identifier(n:Node):SExpr {
		var s = find(n.text);
		if (s != null) return local(s);
		if (constants.exists(n.text)) return constants.get(n.text);
		if (slotsSelf != null && n.text == slotsSelf)
			error('${n.text}, the slot object, is read as ${n.text}.options.<name> and called as ${n.text}.<slot>(s, p): it is no shader value', n);
		if (paramsObject != null && n.text == paramsObject.name)
			error('${n.text}, the stage\'s parameters, is read by its fields (${n.text}.name): it is no shader value', n);
		// (a module-level constant of a number: its value)
		var d = Scope.declared(n.file, n.text, KindVariableDeclaration);
		var from = d == null ? Scope.imported(n.file, n.text) : null;
		if (from != null) d = declaration(from.specifier, from.name, KindVariableDeclaration);
		if (d != null && d.initializer() != null) {
			var i = strip(d.initializer());
			var neg = i.kind == KindPrefixUnaryExpression && i.unaryOperator() == KindMinusToken;
			if (neg) i = strip(i.operand());
			if (i.kind == KindNumericLiteral) return {e: EFloat((neg ? -1 : 1) * Std.parseFloat(i.text)), t: TFloat};
			if (i.kind == KindTrueKeyword || i.kind == KindFalseKeyword) return {e: EBool(i.kind == KindTrueKeyword), t: TBool};
		}
		return error('${n.text} is not a local of this function (a closure?) nor a constant (shader code reads module-level constants of numbers)', n);
	}

	function binary(n:Node, out:Array<SStmt>):SExpr {
		var r = binaryOf(n, out);
		return slots != null ? Fold.expr(r) : r;
	}

	function binaryOf(n:Node, out:Array<SStmt>):SExpr {
		var op = n.operatorToken().kind;
		var x = expr(n.left(), out), y = expr(n.right(), out);
		return switch op {
			case KindPlusToken | KindMinusToken | KindAsteriskToken | KindSlashToken | KindPercentToken:
				var t = x.t == TInt && y.t == TInt ? TInt : TFloat;
				if ((x.t != TFloat && x.t != TInt) || (y.t != TFloat && y.t != TInt))
					error('${Names.typeName(x.t)} and ${Names.typeName(y.t)}: operators are on numbers (a vector\'s are .add, .sub, .mul, .div)', n);
				if (op == KindPercentToken && t == TFloat) error("% on Float is not supported in a shader", n);
				{e: EBinop(switch op {
					case KindPlusToken: Add;
					case KindMinusToken: Sub;
					case KindAsteriskToken: Mul;
					case KindSlashToken: Div;
					case _: Mod;
				}, coerce(x, t, n.left()), coerce(y, t, n.right())), t: t};
			case KindEqualsEqualsEqualsToken | KindExclamationEqualsEqualsToken | KindEqualsEqualsToken | KindExclamationEqualsToken | KindLessThanToken | KindLessThanEqualsToken | KindGreaterThanToken | KindGreaterThanEqualsToken:
				var w = x.t == TFloat || y.t == TFloat ? TFloat : x.t;
				var eq = op == KindEqualsEqualsEqualsToken || op == KindExclamationEqualsEqualsToken || op == KindEqualsEqualsToken || op == KindExclamationEqualsToken;
				if (!(w == TFloat || w == TInt || (w == TBool && eq))) error('${Names.typeName(x.t)} and ${Names.typeName(y.t)} cannot be compared in a shader', n);
				{e: EBinop(switch op {
					case KindEqualsEqualsEqualsToken | KindEqualsEqualsToken: Eq;
					case KindExclamationEqualsEqualsToken | KindExclamationEqualsToken: Ne;
					case KindLessThanToken: Lt;
					case KindLessThanEqualsToken: Le;
					case KindGreaterThanToken: Gt;
					case _: Ge;
				}, coerce(x, w, n.left()), coerce(y, w, n.right())), t: TBool};
			case KindAmpersandAmpersandToken | KindBarBarToken:
				{e: EBinop(op == KindAmpersandAmpersandToken ? And : Or, coerce(x, TBool, n.left()), coerce(y, TBool, n.right())), t: TBool};
			case _: error('this operator is not supported in a shader', n);
		}
	}

	function field(n:Node, out:Array<SStmt>):SExpr {
		var recv = strip(n.expression());
		if (recv.kind == KindIdentifier && recv.text == "Math" && find("Math") == null && n.name().text == "PI") return {e: EFloat(Math.PI), t: TFloat};
		var name = n.name().text;
		if (slotsSelf != null && recv.kind == KindPropertyAccessExpression && strip(recv.expression()).kind == KindIdentifier
			&& strip(recv.expression()).text == slotsSelf && find(slotsSelf) == null && recv.name().text == "options")
			return option(name, n);
		if (slotsSelf != null && recv.kind == KindIdentifier && recv.text == slotsSelf && find(slotsSelf) == null)
			error('${recv.text}.$name: the slot object is read as ${recv.text}.options.<name> and called as ${recv.text}.<slot>(s, p)', n);
		if (recv.kind == KindIdentifier && paramsObject != null && recv.text == paramsObject.name && find(recv.text) == null) {
			var s = paramsObject.fields.get(name);
			if (s == null) error('${recv.text} has no parameter $name', n);
			return local(s);
		}
		var o = expr(recv, out);
		return switch o.t {
			case TVec(k):
				if (!~/^[xyzw]{1,4}$/.match(name) || Lambda.exists([for (i in 0...name.length) name.charAt(i)], c -> "xyzw".indexOf(c) >= k))
					error('Vec$k has no component $name', n);
				{e: ESwizzle(o, name), t: name.length == 1 ? TFloat : TVec(name.length)};
			case TMat4 if (~/^c[0-3]$/.match(name)): {e: EColumn(o, Std.parseInt(name.substr(1))), t: TVec(4)};
			case TStruct(s):
				var f = Lambda.find(s.fields, f -> f.field == name);
				if (f == null) error('${s.path} has no field $name', n);
				{e: EField(o, f.name), t: f.type};
			case t: error('the field $name of a ${Names.typeName(t)} is not a shader value', n);
		}
	}

	static function methodOp(name:String):Null<SBinop>
		return switch name {
			case "add": Add;
			case "sub": Sub;
			case "mul": Mul;
			case "div": Div;
			case _: null;
		}

	static function isMathType(t:SType):Bool
		return t.match(TVec(_) | TMat4);

	static final BUILTINS = [
		"abs", "sign", "floor", "ceil", "fract", "sqrt", "inversesqrt", "sin", "cos", "tan", "exp", "log", "min", "max", "pow", "step", "mix", "clamp",
		"smoothstep", "dot", "length", "distance", "normalize", "reflect", "cross", "sample", "sampleLevel", "discard"
	];

	function call(n:Node, out:Array<SStmt>, want:Null<SType>):SExpr {
		var callee = strip(n.expression());
		var actual = n.arguments() ?? [];
		// (a vector's or a matrix's operator: a.mul(b))
		if (callee.kind == KindPropertyAccessExpression) {
			var recv = strip(callee.expression()), name = callee.name().text;
			if (slotsSelf != null && recv.kind == KindIdentifier && recv.text == slotsSelf && find(slotsSelf) == null) return slotCall(name, actual, n, out, want);
			if (recv.kind == KindIdentifier && recv.text == "Math" && find("Math") == null) return math(name, actual, n, out);
			var a = expr(recv, out);
			if (isMathType(a.t)) {
				if (name == "neg" && actual.length == 0) return {e: EUnop(Neg, a), t: a.t};
				var op = methodOp(name);
				if (op == null || actual.length != 1) error('${Names.typeName(a.t)}.$name is not supported in a shader', n);
				var b = expr(actual[0], out);
				var t = switch [a.t, b.t] {
					case [TMat4, TVec(4)]: TVec(4);
					case [TMat4, TMat4] if (op == Mul): TMat4;
					case [TVec(k), TVec(m)] if (k == m): a.t;
					case [TVec(_), TFloat | TInt]: a.t;
					case _: error('${Names.typeName(a.t)}.$name(${Names.typeName(b.t)}) is not supported in a shader', n);
				}
				return {e: EBinop(op, a, b.t == TInt ? coerce(b, TFloat, actual[0]) : b), t: t};
			}
			return error('a method call is not supported in a shader (shader functions are module-level functions)', n);
		}
		if (callee.kind != KindIdentifier) error("this call is not supported in a shader", n);
		var name = callee.text;
		if (find(name) != null) error('$name: a closure is not supported in a shader', n);
		var from = Scope.imported(callee.file, name);
		if (from != null && from.module == "helder/gfx") return builtin(from.name, actual, n, out);
		var decl = from != null ? declaration(from.specifier, from.name, KindFunctionDeclaration) : Scope.declared(callee.file, name, KindFunctionDeclaration);
		if (decl == null) error('$name is not a shader function (shader code calls module-level functions of the program, helder/gfx\'s builtins and Math\'s)', n);
		var g = lower(decl.file.path + ":" + decl.pos, decl.name().text, decl, Plain);
		if (actual.length != g.params.length) error('${decl.name().text} takes ${g.params.length} arguments', n);
		var xs = [for (i in 0...actual.length) coerce(expr(actual[i], out, g.params[i].type), g.params[i].type, actual[i])];
		return {e: ECall(g, xs), t: g.ret};
	}

	function math(name:String, actual:Array<Node>, n:Node, out:Array<SStmt>):SExpr {
		var xs = [for (a in actual) coerce(expr(a, out), TFloat, a)];
		return switch name {
			case "sqrt" | "sin" | "cos" | "tan" | "exp" | "log" | "abs" | "pow" | "min" | "max" | "floor" | "ceil": {e: EBuiltin(name, xs), t: TFloat};
			case _: error('Math.$name is not supported in a shader', n);
		}
	}

	function builtin(name:String, actual:Array<Node>, n:Node, out:Array<SStmt>):SExpr {
		if (name == "position") error("position(...) marks a field of the varyings where the vertex stage builds them ({clip: position(...), ...})", n);
		var xs = [for (a in actual) expr(a, out)];
		function vectorOf():SType {
			for (x in xs)
				switch x.t {
					case TVec(_): return x.t;
					case _:
				}
			return TFloat;
		}
		var t:SType = switch name {
			case "vec2": TVec(2);
			case "vec3": TVec(3);
			case "vec4": TVec(4);
			case "mat4": TMat4;
			case "dot" | "length" | "distance": TFloat;
			case "cross": TVec(3);
			case "sample" | "sampleLevel": TVec(4);
			case "discard": TVoid;
			case _ if (BUILTINS.contains(name)): vectorOf();
			case _: error('$name is not a shader builtin', n);
		}
		xs = [for (i in 0...xs.length) xs[i].t == TInt ? coerce(xs[i], TFloat, actual[i]) : xs[i]];
		return switch name {
			case "vec2" | "vec3" | "vec4": {e: ENew(xs), t: t};
			case "mat4" if (xs.length == 4): {e: ENew(xs), t: t};
			case "mat4":
				var s = xs[0];
				switch s.e {
					case EFloat(_) | ELocal(_):
					case _:
						var tmp = temp(TFloat);
						out.push(SDecl(tmp, s));
						s = local(tmp);
				}
				var z = {e: EFloat(0), t: TFloat};
				{e: ENew([for (i in 0...4) {e: ENew([for (j in 0...4) i == j ? s : z]), t: TVec(4)}]), t: t};
			case _:
				// (a Float bound or weight of a vector function: a vector, as WGSL wants it)
				switch t {
					case TVec(_) if (name != "reflect" && name != "cross" && name != "sampleLevel" && name != "sample"):
						xs = [for (x in xs) x.t == TFloat ? {e: ENew([x]), t: t} : x];
					case _:
				}
				{e: EBuiltin(name, xs), t: t};
		}
	}

	// position(x)'s x
	function positionArg(n:Node):Null<Node> {
		var x = strip(n);
		if (x.kind != KindCallExpression || strip(x.expression()).kind != KindIdentifier) return null;
		var from = Scope.imported(x.file, strip(x.expression()).text);
		if (from == null || from.module != "helder/gfx" || from.name != "position" || (x.arguments() ?? []).length != 1) return null;
		return x.arguments()[0];
	}

	// --- slot objects' variants

	// a statement inlined (a branch a variant takes)
	function inline_(n:Node, out:Array<SStmt>) {
		scopes.push(new Map());
		if (n.kind == KindBlock) for (s in n.statements())
			stmt(s, out) else stmt(n, out);
		scopes.pop();
	}

	// m.options.<name>: the variant's value
	function option(name:String, n:Node):SExpr {
		var v = slots.options.get(name);
		if (v == null) error('the slot object has no option $name', n);
		return switch v {
			case KBool(b): {e: EBool(b), t: TBool};
			case KInt(i): {e: EFloat(i), t: TFloat};
			case KFloat(f): {e: EFloat(f), t: TFloat};
			case _: error('the option $name is a boolean or a number', n);
		}
	}

	// for (let k = a; k < b; k++) body, a and b constants: the body once for each k, k a constant in each
	function unrolled(n:Node, out:Array<SStmt>):Bool {
		var init = n.initializer(), cond = n.condition(), incr = n.incrementor();
		if (init == null || cond == null || incr == null || init.kind != KindVariableDeclarationList || init.declarations().length != 1) return false;
		var d = init.declarations()[0];
		if (d.name().kind != KindIdentifier || d.initializer() == null) return false;
		var k = d.name().text;
		var c = strip(cond), i = strip(incr);
		if (c.kind != KindBinaryExpression || c.operatorToken().kind != KindLessThanToken || strip(c.left()).kind != KindIdentifier || strip(c.left()).text != k) return false;
		if (!((i.kind == KindPostfixUnaryExpression || i.kind == KindPrefixUnaryExpression) && i.unaryOperator() == KindPlusPlusToken && strip(i.operand()).text == k)) return false;
		var scratch = [];
		var from = Fold.expr(expr(d.initializer(), scratch)), to = Fold.expr(expr(c.right(), scratch));
		var a = switch from.e {
			case EFloat(f) if (Math.ffloor(f) == f): Std.int(f);
			case EInt(x): x;
			case _: return false;
		}
		var b = switch to.e {
			case EFloat(f): Math.ceil(f);
			case EInt(x): x;
			case _: return false;
		}
		if (scratch.length > 0) return false;
		function breaks(x:Node):Bool {
			if (x.kind == KindBreakStatement || x.kind == KindContinueStatement) return true;
			if (x.kind == KindForStatement || x.kind == KindWhileStatement || x.kind == KindArrowFunction || x.kind == KindFunctionExpression) return false;
			for (y in x.children())
				if (breaks(y)) return true;
			return false;
		}
		if (breaks(n.statement())) error("a loop a variant unrolls has no break or continue", n);
		for (v in a...b) {
			constants.set(k, {e: EFloat(v), t: TFloat});
			inline_(n.statement(), out);
		}
		constants.remove(k);
		return true;
	}

	// m.<slot>(s, p): the slot's function (the override's, else the
	// default's), its input s; its own parameters the stage's of the same
	// names, the others joining the stage's
	function slotCall(name:String, actual:Array<Node>, n:Node, out:Array<SStmt>, want:Null<SType>):SExpr {
		var node = slots.slots.get(name);
		if (node == null) error('the slot object has no slot $name', n);
		if (actual.length == 0 || actual.length > 2) error('a slot is called with its input and the stage\'s parameters: $slotsSelf.$name(s, p)', n);
		var g = slotFunctions.get(name);
		if (g == null) {
			var f:Node = switch node.value {
				case KFunction(k): k.source;
				case KRef(ref):
					var at:Node = node.pos;
					var from = Scope.imported(at.file, ref);
					var decl = from != null ? declaration(from.specifier, from.name, KindFunctionDeclaration) : Scope.declared(at.file, ref, KindFunctionDeclaration);
					if (decl == null) error('the slot $name, $ref, is not a module-level function', at);
					decl;
				case _: error('the slot $name is a function, not ${node.describe()}', node.pos);
			}
			// (its input's type, when not written: what the slot object's type says)
			var input = slotInput(name, n);
			// (named as Haxe's: a module-level function by its own name, an override by its slot's)
			g = lower(f.file.path + ":" + f.pos, f.kind == KindFunctionDeclaration ? f.name().text : name, f, Slot, input);
			slotFunctions.set(name, g);
		}
		if (g.params.length == 0) error('the slot $name takes no input', n);
		var xs = [coerce(expr(actual[0], out, g.params[0].type), g.params[0].type, actual[0])];
		for (i in 0...g.fields.length)
			xs.push(local(stageParam(g.fields[i], g.params[i + 1].type, n)));
		if (want != null && !Names.same(g.ret, want)) error('the slot $name returns a ${Names.typeName(g.ret)}, where a ${Names.typeName(want)} is needed', n);
		return {e: ECall(g, xs), t: g.ret};
	}

	// the type of a slot's input the slot object's type gives (the stage's third parameter's type: {color: (s: Surface, p: Params) => Vec3, ...})
	var selfType:Null<Node>;

	function slotInput(name:String, at:Node):Null<SType> {
		if (selfType == null) return null;
		var members = objectMembers(selfType);
		if (members == null) return null;
		for (m in members)
			if (m.name() != null && m.name().text == name && m.type() != null && m.type().kind == KindFunctionType) {
				var ps = m.type().parameters();
				if (ps.length > 0 && ps[0].type() != null) return typeOf(ps[0].type());
			}
		return null;
	}

	// the stage's parameter of a name (a slot's: made one when the stage has none of it)
	function stageParam(name:String, t:SType, at:Node):SVar {
		if (paramsObject == null) paramsObject = {name: "p", fields: new Map()};
		var s = paramsObject.fields.get(name);
		if (s != null) {
			if (!Names.same(s.type, t)) error('the parameter $name is a ${Names.typeName(s.type)} in the stage, a ${Names.typeName(t)} in a slot', at);
			return s;
		}
		s = declare(name, t, at, vars.get(fn), true);
		scopes[0].remove(name);
		paramsObject.fields.set(name, s);
		fn.params.push(s);
		fn.fields.push(name);
		return s;
	}

	// --- helpers

	function coerce(x:SExpr, t:SType, at:Node):SExpr {
		if (Names.same(x.t, t)) return x;
		return switch [x.t, t] {
			case [TInt, TFloat]:
				switch x.e {
					case EInt(i): {e: EFloat(i), t: TFloat};
					case _: {e: EConvert(x), t: TFloat};
				}
			case _: error('${Names.typeName(x.t)} where a ${Names.typeName(t)} is needed', at);
		}
	}

	static function one(t:SType):SExpr
		return t == TFloat ? {e: EFloat(1), t: TFloat} : {e: EInt(1), t: TInt};

	static function local(v:SVar):SExpr
		return {e: ELocal(v), t: v.type};

	static function strip(n:Node):Node
		return switch n.kind {
			case KindParenthesizedExpression | KindAsExpression | KindSatisfiesExpression | KindNonNullExpression: strip(n.expression());
			case _: n;
		}
}

// what a function is lowered as: a plain function, a stage (its object of
// parameters flattened, a slot object's third parameter), a slot
enum abstract LowerKind(Int) {
	var Plain;
	var Stage;
	var Slot;
}
