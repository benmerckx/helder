package helder.typescript.check;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;

// A checker type, as far as lowering asks: what values it holds.
class TsType {
	public final id:Int;
	public final flags:Int;
	public final objectFlags:Int;
	// its symbol's identity (as Node.symbol): a class's, an interface's
	public final symbol:Null<String>;
	// (a class's `this` type: its instances, and its subclasses')
	public final isThis:Bool;
	// a union's members; an array's element type
	public var members:Null<Array<TsType>> = null;
	public var element:Null<TsType> = null;

	public function new(id, flags, objectFlags, symbol, isThis) {
		this.id = id;
		this.flags = flags;
		this.objectFlags = objectFlags;
		this.symbol = symbol;
		this.isThis = isThis;
	}
}

// The checker's types of a program, fetched with its files (Project): of
// every expression and declared name, of every function's result; the
// members of unions and the elements of arrays among them.
class Types {
	final tsgo:Tsgo;
	final at:{snapshot:Int, project:String};
	final byId:Map<Int, TsType> = [];
	final pending:Array<TsType> = [];
	final number:Int;
	final numberLiteral:Int;
	final union:Int;
	final object:Int;
	final typeParameter:Int;
	final classFlag:Int;
	final reference:Int;

	// the kinds whose nodes have types lowering asks about
	static final typed:Array<Kind> = [
		KindIdentifier, KindThisKeyword, KindPropertyAccessExpression, KindElementAccessExpression, KindCallExpression, KindNewExpression,
		KindParenthesizedExpression, KindBinaryExpression, KindPrefixUnaryExpression, KindPostfixUnaryExpression, KindConditionalExpression,
		KindArrayLiteralExpression, KindObjectLiteralExpression, KindNumericLiteral, KindStringLiteral, KindAsExpression, KindNonNullExpression
	];

	public function new(tsgo:Tsgo, at:{snapshot:Int, project:String}, tables:Tables) {
		this.tsgo = tsgo;
		this.at = at;
		number = tables.typeFlags.get("Number");
		numberLiteral = tables.typeFlags.get("NumberLiteral");
		union = tables.typeFlags.get("Union");
		object = tables.typeFlags.get("Object");
		typeParameter = tables.typeFlags.get("TypeParameter");
		classFlag = tables.objectFlags.get("Class");
		reference = tables.objectFlags.get("Reference");
	}

	// a file's types: of its expressions and names in one request, then of
	// its functions' results
	public function load(sf:SourceFile) {
		var key = sf.string(sf.extendedData(1, 8));
		var ids = [for (i in 1...sf.count) if (typed.contains(sf.kindAt(i))) i];
		if (ids.length > 0) {
			var result:Array<Dynamic> = tsgo.call("getTypeAtLocations", {snapshot: at.snapshot, project: at.project, locations: [for (i in ids) location(sf, i, key)]});
			for (j in 0...ids.length) if (result[j] != null) sf.types.set(ids[j], add(result[j]));
		}
		for (i in 1...sf.count) if (sf.kindAt(i) == KindFunctionDeclaration || sf.kindAt(i) == KindMethodDeclaration) {
			var signature:Dynamic = tsgo.call("getSignatureFromDeclaration", {snapshot: at.snapshot, project: at.project, location: location(sf, i, key)});
			if (signature == null) continue;
			var result:Dynamic = request("getReturnTypeOfSignature", signature.id);
			if (result != null) sf.returns.set(i, add(result));
		}
		resolve();
	}

	static function location(sf:SourceFile, i:Int, key:String):String return i + "." + sf.tables.raw(sf.kindAt(i)) + "." + key;

	function request(method:String, id:Dynamic):Dynamic return tsgo.call(method, {snapshot: at.snapshot, project: at.project, objectId: id});

	function add(data:Dynamic):TsType {
		var id:Int = data.id;
		var t = byId.get(id);
		if (t == null) {
			var symbol:Dynamic = data.symbol;
			t = new TsType(id, data.flags, data.objectFlags ?? 0, symbol == null ? null : Std.string(symbol.id), data.isThisType == true);
			byId.set(id, t);
			pending.push(t);
		}
		return t;
	}

	// (the members of the unions, the elements of the arrays, found so far)
	function resolve() {
		while (pending.length > 0) {
			var t = pending.pop();
			if (t.flags & union != 0) {
				var members:Array<Dynamic> = request("getTypesOfType", t.id);
				t.members = [for (m in members ?? []) add(m)];
			}
			else if (t.flags & object != 0 && t.objectFlags & reference != 0
				&& tsgo.call("isArrayType", {snapshot: at.snapshot, project: at.project, type: t.id}) == true) {
				var args:Array<Dynamic> = tsgo.call("getTypeArguments", {snapshot: at.snapshot, project: at.project, type: t.id});
				if (args != null && args.length == 1) t.element = add(args[0]);
			}
		}
	}

	// ---- what lowering asks
	// whether every value of the type is a number
	public function isNumber(t:Null<TsType>):Bool {
		if (t == null) return false;
		if (t.members != null) return Lambda.foreach(t.members, isNumber);
		return t.flags & (number | numberLiteral) != 0 && t.flags & union == 0;
	}

	// the class whose instances (its subclasses' too) the type's values are, as its symbol
	public function instanceOf(t:Null<TsType>):Null<String> {
		if (t == null || t.symbol == null) return null;
		if (t.flags & object != 0 && t.objectFlags & (classFlag | reference) != 0) return t.symbol;
		if (t.flags & typeParameter != 0 && t.isThis) return t.symbol;
		return null;
	}

	// whether every value of the type is an array
	public function isArray(t:Null<TsType>):Bool return t != null && t.element != null;
}
