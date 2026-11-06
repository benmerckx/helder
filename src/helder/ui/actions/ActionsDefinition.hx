package helder.ui.actions;

import helder.definition.Kernel;
import helder.ui.actions.JsonType;

using StringTools;

// actions(namespace, ...)'s handler (src/helder/compiler/DESIGN.md 4), the
// same for both languages: Haxe's `actions("viewer", ViewerAction)` (an
// enum's constructors: ActionsMacro) and TypeScript's `actions("viewer",
// {next() {}, zoomTo(percent: number) { return {percent}; }})` (an
// object's methods: helder.typescript.lower's Definitions), each adapter
// describing its actions and their arguments' types as ArgTypes. It checks
// the namespace (an identifier, a string literal) and that every argument
// can be read from a JSON keymap (numbers, strings, booleans, and arrays and
// structures of these), and makes what both generate from: each action's
// keymap name (viewer::ZoomTo), its value's `type` in TypeScript (zoomTo)
// and its arguments' JSON types (the readers, JsonType.read).
class ActionsDefinition implements Definition<ActionsAdapter, ActionsOutput> {
	public static inline var WHAT = "numbers, strings, booleans, and arrays and structures of these";

	public final name = "actions";

	public function new() {}

	// arg: [namespace, actions], the actions the adapter's (ActionsAdapter.declared)
	public function generate(arg:KNode, a:ActionsAdapter):ActionsOutput {
		var parts = switch arg.value {
			case KArray(xs) if (xs.length == 2): xs;
			case _: a.error("takes a namespace and the actions: actions(\"viewer\", ...)", arg.pos);
		}
		var ns = namespace(parts[0], a);
		var out:Array<ActionInfo> = [];
		for (d in a.declared(parts[1])) {
			var name = d.name.charAt(0).toUpperCase() + d.name.substr(1);
			if (Lambda.exists(out, o -> o.name == name)) a.error('$ns::$name is declared twice', d.pos);
			out.push(new ActionInfo(name, d.type, [for (p in d.params) new ParamInfo(p.name, json(p.type, '$ns::$name\'s argument ${p.name}', p.pos, a))]));
		}
		return {namespace: ns, actions: out};
	}

	static function namespace(n:KNode, a:Adapter):String {
		var s = switch n.value {
			case KString(s): s;
			case _: a.error('the namespace is a string literal, not ${n.describe()}', n.pos);
		}
		if (s == "") a.error("the namespace is empty", n.pos);
		if (!~/^[A-Za-z_][A-Za-z0-9_]*$/.match(s)) a.error('the namespace "$s" is not an identifier (letters, digits and _)', n.pos);
		return s;
	}

	// the message of a duplicate namespace (both adapters')
	public static function twice(ns:String):String
		return 'the namespace $ns is declared twice (once in a program)';

	static function json(t:ArgType, what:String, pos:KPos, a:Adapter):JsonType {
		var r = reason(t, "", []);
		if (r.why != null) a.error('$what cannot be read from JSON: ${r.why} (JSON-readable: $WHAT)', pos);
		return r.type;
	}

	static function reason(t:ArgType, at:String, seen:Array<String>):{type:JsonType, why:Null<String>} {
		var here = at == "" ? "" : at + ": ";
		function bad(why:String)
			return {type: JNumber, why: why};
		return switch t.kind() {
			case ANumber: {type: JNumber, why: null};
			case AInt: {type: JInt, why: null};
			case AString: {type: JString, why: null};
			case ABool: {type: JBool, why: null};
			case ABad(m): bad(here + m);
			case ANull(i):
				var r = reason(i, at, seen);
				r.why != null ? r : {type: JNull(r.type), why: null};
			case AList(e):
				var r = reason(e, at + "[]", seen);
				r.why != null ? r : {type: JArray(r.type), why: null};
			case AFields(fs):
				if (seen.contains(t.text)) return bad(here + "recursive");
				seen.push(t.text);
				var out:Array<JsonField> = [];
				for (f in fs) {
					var r = reason(f.type, at + "." + f.name, seen);
					if (r.why != null) return r;
					out.push(new JsonField(f.name, r.type, f.optional));
				}
				seen.pop();
				{type: JFields(out), why: null};
		}
	}

	// the output as TypeScript's lowering passes it to helder/ui/actions (Script.define)
	public static function toJson(o:ActionsOutput):String
		return haxe.Json.stringify({
			namespace: o.namespace,
			actions: [
				for (x in o.actions)
					{name: x.name, type: x.type, params: [for (p in x.params) {name: p.name, type: JsonTypes.toData(p.type)}]}
			]
		});
}

typedef ActionsOutput = {
	namespace:String,
	actions:Array<ActionInfo>
}

// What an adapter tells of the actions: each one's name (Haxe's constructor,
// TypeScript's method), its value's `type` in TypeScript, and its arguments
interface ActionsAdapter extends Adapter {
	function declared(actions:KNode):Array<{name:String, type:String, params:Array<{name:String, type:ArgType, pos:KPos}>, pos:KPos}>;
}

enum ArgKind {
	ANumber;
	AInt;
	AString;
	ABool;
	ANull(t:ArgType);
	AList(e:ArgType);
	AFields(fields:Array<{name:String, type:ArgType, optional:Bool}>);
	ABad(why:String);
}

// A type as an adapter describes it: its text (as its language writes it)
// and what it is, made when asked (a recursive type's fields name it again)
class ArgType {
	public final text:String;

	final make:() -> ArgKind;
	var made:Null<ArgKind> = null;

	public function new(text:String, make:() -> ArgKind) {
		this.text = text;
		this.make = make;
	}

	public function kind():ArgKind {
		if (made == null) made = make();
		return made;
	}
}
