package helder.typescript.api;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import helder.typescript.api.Modules;
import helder.typescript.api.dts.DefinitionEmitter;
import helder.typescript.api.dts.TypeEmitter;

// helder's TypeScript declaration files, generated from its Haxe types
// (DESIGN.md 7.3): each module's (Modules: helder/view, helder/ui,
// helder/web), beside its declaration class (src/helder/view/index.d.ts...).
// An init macro, run by api/declarations.mjs with helder's compiler:
//
//   write(["helder.view.TypeScript", ...])        // the files written
//   write([...], true)                            // checked: an error when one differs
//
// A file declares the module's classes (`declare class`, each the Haxe class
// `__haxe` names), its functions (`const f: typeof Class.f`), its
// interfaces and type aliases (abstracts: Signal, Read; enum abstracts:
// Load), and its part of JSX: helder/view's namespace (Element, a
// renderer's elements as any tag), the neutral elements' attributes and
// events where ui's module says so (jsx(neutral): MarkupMacro.NEUTRAL_EVENTS'
// handlers typed). What it names from another module is imported.
class Declarations {
	public static function write(decls:Array<String>, check = false)
		Context.onAfterInitMacros(() -> run(decls, check));

	static function run(decls:Array<String>, check:Bool) {
		var api = Modules.of(decls);
		var stale = [];
		for (m in api.modules) {
			var text = module(api, m);
			var file = haxe.io.Path.join([m.dir, m.file]);
			var old = sys.FileSystem.exists(file) ? sys.io.File.getContent(file) : null;
			if (old == text) continue;
			if (check) stale.push(file) else sys.io.File.saveContent(file, text);
		}
		if (stale.length > 0)
			Context.fatalError("helder.typescript: " + stale.join(", ") + " differ from helder's Haxe types: write them again (node src/helder/typescript/api/declarations.mjs)",
				Context.currentPos());
	}

	// (where each type is declared: its module and name)
	static function index(api:Api):Map<String, {module:ApiModule, name:String}> {
		var out = new Map();
		for (m in api.modules) {
			for (c in m.classes)
				out.set(key(c.cls), {module: m, name: c.cls.name});
			for (t in m.types) {
				var b = base(t);
				if (b != null) out.set(key(b), {module: m, name: b.name});
			}
		}
		return out;
	}

	static function key(b:BaseType):String
		return b.module + ":" + b.name;

	static function base(t:Type):Null<BaseType>
		return switch t {
			case TInst(c, _): c.get();
			case TAbstract(a, _): a.get();
			case TType(d, _): d.get();
			case TEnum(e, _): e.get();
			case _: null;
		}

	static function module(api:Api, m:ApiModule):String {
		var where = index(api);
		var imports = new Map<String, Array<String>>();
		function declared(b:BaseType):Null<String> {
			var d = where.get(key(b));
			if (d == null) return null;
			if (d.module != m) {
				var names = imports.get(d.module.name);
				if (names == null) imports.set(d.module.name, names = []);
				if (names.indexOf(d.name) < 0) names.push(d.name);
			}
			return d.name;
		}
		var e = new DefinitionEmitter(declared);
		var decl = switch Context.getType(m.decl) {
			case TInst(c, _): c.get();
			case _: throw "unreachable";
		}
		// (the declarations first: their imports are known after)
		var haxeNames = [for (c in m.opaque.concat(m.classes)) c.cls.name + ": " + haxe.Json.stringify(c.type)];
		haxeNames.push("__module: " + haxe.Json.stringify(m.decl));
		e.line('declare const __haxe: {' + haxeNames.join(", ") + '};');
		for (t in m.types) {
			e.line();
			switch t {
				case TAbstract(a, _): e.emitAbstract(a.get().name, a.get());
				case TInst(c, _): e.emitOpaque(c.get().name, c.get());
				case TType(d, _): e.emitTypedef(d.get().name, d.get());
				case _:
			}
		}
		for (c in m.classes) {
			e.line();
			e.emitClass(c.cls.name, c.cls, c.statics, c.members, c.ctor);
			var fs = [for (f in m.functions) if (f.cls == c) f];
			if (fs.length > 0) e.line();
			for (f in fs)
				e.emitFunction(f.alias, c.cls.name, f.field);
		}
		for (j in m.jsx) {
			e.line();
			switch j {
				case "base": jsxBase(e, declared, e.from);
				case "neutral": jsxNeutral(e, declared);
				case _: Context.error("helder.typescript: @:typescript.jsx is base or neutral", decl.pos);
			}
		}
		var head = [for (l in Docs.of(decl.pos)) "//" + (l == "" ? "" : " " + l)];
		head.push("//");
		head.push("// Generated from helder's Haxe types (helder.typescript.api.Declarations: node");
		head.push("// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.");
		var names = [for (k in imports.keys()) k];
		names.sort(Reflect.compare);
		for (k in names) {
			var list = imports.get(k);
			list.sort(Reflect.compare);
			head.push('import type {' + list.join(", ") + '} from ' + haxe.Json.stringify(k) + ';');
		}
		return head.join("\n") + "\n\n" + e.toString();
	}

	// helder/view's JSX: TSX's values are Views, a component any function of
	// its props, a prop of a type made from other values (Read) taking them at
	// a TSX site (LibraryManagedAttributes: a constant, a signal, a function),
	// a renderer's elements any tag (checked when compiled)
	static function jsxBase(e:DefinitionEmitter, declared:BaseType->Null<String>, from:Array<String>) {
		var view = switch Context.getType("helder.view.View") {
			case TInst(c, _): declared(c.get());
			case _: null;
		}
		e.line('declare global {');
		e.line('\tnamespace JSX {');
		e.line('\t\ttype Element = ' + (view ?? "unknown") + ';');
		e.line('\t\t// components may return any content');
		e.line('\t\ttype ElementType = string | ((props: any) => unknown);');
		e.line('\t\tinterface ElementChildrenAttribute {');
		e.line('\t\t\tchildren: {};');
		e.line('\t\t}');
		if (from.length > 0) {
			e.line('\t\t// a component\'s props: ' + from.join(", ") + ' as what makes one');
			var t = "P[K]";
			for (f in from)
				t = 'NonNullable<P[K]> extends ' + f + '<infer T> ? ' + f + 'From<T> | Extract<P[K], undefined> : ' + t;
			e.line('\t\ttype LibraryManagedAttributes<C, P> = {[K in keyof P]: ' + t + '};');
		}
		e.line('\t\t// a renderer\'s elements: their attributes are the renderer\'s to check');
		e.line('\t\tinterface IntrinsicElements {');
		e.line('\t\t\t[tag: string]: {[attribute: string]: unknown};');
		e.line('\t\t}');
		e.line('\t}');
		e.line('}');
	}

	// the neutral elements (helder.markup.Plan's: view, text, view:button...),
	// their handlers typed by ui's events (MarkupMacro.NEUTRAL_EVENTS)
	static function jsxNeutral(e:DefinitionEmitter, declared:BaseType->Null<String>) {
		var writer:TypeWriter = {write: _ -> {}, declared: declared};
		var fields = switch Context.follow(Context.getType(helder.view.MarkupMacro.NEUTRAL_EVENTS)) {
			case TAnonymous(a): a.get().fields.copy();
			case _: [];
		}
		fields.sort((a, b) -> Context.getPosInfos(a.pos).min - Context.getPosInfos(b.pos).min);
		e.line('// a neutral element\'s attributes: any, its handlers given ui\'s events (' + helder.view.MarkupMacro.NEUTRAL_EVENTS + ')');
		e.line('export interface NeutralAttributes {');
		e.line('\t[attribute: string]: unknown;');
		for (f in fields)
			e.line('\t' + f.name + '?: ((event: ' + TypeEmitter.toString(writer, f.type) + ') => void) | null;');
		e.line('}');
		e.line();
		e.line('declare global {');
		e.line('\tnamespace JSX {');
		e.line('\t\t// the neutral elements: ui\'s, realised by each renderer');
		e.line('\t\tinterface IntrinsicElements {');
		for (n in helder.markup.Plan.NEUTRAL)
			e.line('\t\t\t' + n + ': NeutralAttributes;');
		for (n in helder.markup.Plan.NEUTRAL_PREFIXES)
			e.line('\t\t\t[tag: `' + n + ':$${string}`]: NeutralAttributes;');
		e.line('\t\t}');
		e.line('\t}');
		e.line('}');
	}
}
#end
