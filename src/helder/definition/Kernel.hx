package helder.definition;

// A definition's argument as its handler sees it (src/helder/compiler/
// DESIGN.md): the same tree from either language's adapter, Haxe's
// (HaxeAdapter, from the macro's untyped expression) or TypeScript's
// (helder.typescript.lower, from tsgo's checked AST). Only what is static
// makes one: literals, object and array literals, functions, and references
// to module-level constants and other definitions; the adapter rejects
// anything else at its position before the handler runs.
//
// A function is the adapter's own (KFunction.source: Haxe's expression, a
// TypeScript node): a handler lowers its body through the adapter that made
// it (a shader's: ShaderAdapter.lowerStage, to helder.gfx.shader.Ir), so
// that each language keeps its types and structure until the handler's IR.
enum KValue {
	KString(s:String);
	KFloat(f:Float);
	KInt(i:Int);
	KBool(b:Bool);
	KNull;
	KObject(fields:Array<KField>);
	KArray(items:Array<KNode>);
	KFunction(f:KFunction);
	// a module-level constant or another definition, by its path
	KRef(path:String);
}

class KNode {
	public final value:KValue;
	public final pos:KPos;

	public function new(value, pos) {
		this.value = value;
		this.pos = pos;
	}

	// what the value is, for a handler's errors ("a function", "a string")
	public function describe():String
		return switch value {
			case KString(_): "a string";
			case KFloat(_) | KInt(_): "a number";
			case KBool(_): "a boolean";
			case KNull: "null";
			case KObject(_): "an object";
			case KArray(_): "an array";
			case KFunction(_): "a function";
			case KRef(p): p;
		}
}

typedef KField = {
	name:String,
	node:KNode
}

// a position in the definition's source, the adapter's own (a Haxe macro
// Position; a TypeScript node's file and offsets): handlers only pass it on
typedef KPos = Dynamic;

class KFunction {
	// its own name (Haxe's `function vs(...)`, TypeScript's named function expression), or null
	public final name:Null<String>;
	public final params:Array<String>;
	public final pos:KPos;
	// the adapter's: what it lowers the body from
	public final source:Any;

	public function new(name, params, pos, source) {
		this.name = name;
		this.params = params;
		this.pos = pos;
		this.source = source;
	}
}

// What a handler needs of the adapter beyond the tree: diagnostics at a
// source position (an error stops the definition: it does not return) and
// the build's defines (-D).
interface Adapter {
	function error(message:String, pos:KPos):Dynamic;
	function defined(name:String):Null<String>;
}

// A definition's handler, written once in Haxe and run by both adapters:
// it checks the argument (errors through the adapter, at the argument's
// positions) and returns what the adapter turns into the generated value
// (O: the handler's own description, such as a shader's text and layout).
interface Definition<A:Adapter, O> {
	// the definition's name, as the call and its diagnostics name it
	final name:String;
	function generate(arg:KNode, adapter:A):O;
}

// Reading an object argument: its fields by name, the unknown ones and the
// missing required ones rejected at their positions.
class KObjectReader {
	final fields:Array<KField>;
	final adapter:Adapter;
	final what:String;
	final pos:KPos;

	public function new(node:KNode, adapter:Adapter, what:String, known:Array<String>) {
		this.adapter = adapter;
		this.what = what;
		pos = node.pos;
		fields = switch node.value {
			case KObject(fs): fs;
			case _: adapter.error('$what is an object literal, not ${node.describe()}', node.pos);
		}
		for (f in fields)
			if (!known.contains(f.name)) adapter.error('$what has no field ${f.name} (it has ' + known.join(", ") + ")", f.node.pos);
	}

	public function get(name:String):Null<KNode> {
		for (f in fields)
			if (f.name == name) return f.node;
		return null;
	}

	public function require(name:String):KNode {
		var n = get(name);
		return n != null ? n : adapter.error('$what needs a field $name', pos);
	}

	public function func(name:String):Null<KFunction> {
		var n = get(name);
		return n == null ? null : switch n.value {
			case KFunction(f): f;
			case _: adapter.error('$what: $name is a function, not ${n.describe()}', n.pos);
		}
	}
}
