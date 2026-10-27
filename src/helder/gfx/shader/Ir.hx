package helder.gfx.shader;

// The shader IR: what the shader macro (Lower) makes of a program's typed
// Haxe functions, and what the emitters (Glsl, Wgsl, Msl, Hlsl) print. Typed
// and structured (no gotos): values of scalar, vector, matrix and struct
// types, locals assigned in statements, calls to functions that are not
// recursive. Names are already the emitted ones (Lower avoids every
// language's keywords and builtins), so an emitter only prints.

enum SType {
	TVoid;
	TBool;
	TInt;
	TFloat;
	TVec(n:Int); // 2 to 4 floats
	TMat4; // 4 columns of vec4
	TTexture; // a Texture2D: a texture and its sampler (parameters only)
	TStruct(s:SStruct);
}

class SStruct {
	public final name:String;
	public final fields:Array<SField>;
	// the Haxe class (path), for errors and the CPU writers
	public final path:String;

	public function new(name, path, fields) {
		this.name = name;
		this.path = path;
		this.fields = fields;
	}
}

typedef SField = {
	name:String, // emitted
	field:String, // Haxe's
	type:SType,
	// @:position: the clip-space position of a vertex stage's output
	position:Bool
}

class SVar {
	public var name:String;
	public final type:SType;
	// assigned after its declaration (WGSL: var, else let; a parameter: copied)
	public var assigned = false;

	public function new(name, type) {
		this.name = name;
		this.type = type;
	}
}

typedef SExpr = {e:SExprDef, t:SType};

enum SExprDef {
	EFloat(f:Float);
	EInt(i:Int);
	EBool(b:Bool);
	ELocal(v:SVar);
	EField(e:SExpr, name:String); // of a struct
	ESwizzle(e:SExpr, comps:String); // of a vector: x, y, z, w
	EColumn(e:SExpr, i:Int); // of a matrix
	EUnop(op:SUnop, e:SExpr);
	EBinop(op:SBinop, a:SExpr, b:SExpr); // scalars, componentwise, matrix products
	ECond(c:SExpr, a:SExpr, b:SExpr);
	// a value of type t from its parts: a vector's components (or vectors,
	// or one scalar for all), a matrix's columns, a struct's fields
	ENew(args:Array<SExpr>);
	EBuiltin(name:String, args:Array<SExpr>); // GLSL's name (ShaderMath)
	ECall(f:SFunction, args:Array<SExpr>);
	EConvert(e:SExpr); // a scalar to t (Int, Float)
}

enum SUnop {
	Neg;
	Not;
	BitNot;
}

enum SBinop {
	Add;
	Sub;
	Mul;
	Div;
	Mod;
	Eq;
	Ne;
	Lt;
	Le;
	Gt;
	Ge;
	And;
	Or;
	BitAnd;
	BitOr;
	BitXor;
	Shl;
	Shr;
}

enum SStmt {
	SDecl(v:SVar, init:Null<SExpr>);
	SAssign(v:SVar, op:Null<SBinop>, e:SExpr);
	SEval(e:SExpr); // a call
	SIf(c:SExpr, a:Array<SStmt>, b:Null<Array<SStmt>>);
	SWhile(c:SExpr, body:Array<SStmt>);
	SBreak;
	SContinue;
	SReturn(e:Null<SExpr>);
}

class SFunction {
	public final name:String;
	public final params:Array<SVar>;
	public final ret:SType;
	public var body:Array<SStmt> = [];

	public function new(name, params, ret) {
		this.name = name;
		this.params = params;
		this.ret = ret;
	}
}

// a uniform block: a struct parameter of an entry point after its input,
// at a binding (its slot) shared by both stages (std140 offsets: the same in WGSL for
// these types; MSL and HLSL declare them explicitly)
class SUniform {
	public final struct:SStruct;
	public final binding:Int;
	public final offsets:Array<Int>;
	public final size:Int;

	public function new(struct, binding, offsets, size) {
		this.struct = struct;
		this.binding = binding;
		this.offsets = offsets;
		this.size = size;
	}
}

// a texture parameter of an entry point after its input (Texture2D), by
// its name, at a slot shared by both stages
class STexture {
	public final name:String;
	public final slot:Int;

	public function new(name, slot) {
		this.name = name;
		this.slot = slot;
	}
}

// an entry point's parameter after its input
enum SResource {
	RUniform(u:SUniform);
	RTexture(t:STexture);
}

enum abstract SStage(Int) {
	var Vertex;
	var Fragment;
}

// one stage: its function (input, then resources), what it needs in
// declaration order (structs, then functions, callees first)
class SEntry {
	public final stage:SStage;
	public final fn:SFunction;
	public final input:SStruct;
	public final resources:Array<SResource>;
	public final uniforms:Array<SUniform>;
	public final textures:Array<STexture>;
	public final structs:Array<SStruct>;
	public final functions:Array<SFunction>;

	public function new(stage, fn, input, resources:Array<SResource>, structs, functions) {
		this.stage = stage;
		this.fn = fn;
		this.input = input;
		this.resources = resources;
		uniforms = [for (r in resources) switch r {
			case RUniform(u): u;
			case _: continue;
		}];
		textures = [for (r in resources) switch r {
			case RTexture(t): t;
			case _: continue;
		}];
		this.structs = structs;
		this.functions = functions;
	}
}

class SProgram {
	public final vertex:SEntry;
	public final fragment:SEntry;
	public final uniforms:Array<SUniform>;
	public final textures:Array<STexture>;

	public function new(vertex, fragment, uniforms, textures) {
		this.vertex = vertex;
		this.fragment = fragment;
		this.uniforms = uniforms;
		this.textures = textures;
	}

	// the vertex stage's output (the varyings): the fragment stage's input
	public var varyings(get, never):SStruct;

	inline function get_varyings()
		return fragment.input;
}
