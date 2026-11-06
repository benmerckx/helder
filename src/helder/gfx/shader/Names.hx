package helder.gfx.shader;

import helder.gfx.shader.Ir;

// The names of a shader program's code, shared by both adapters (Lower,
// Haxe's; helder.typescript's): structs and functions take global names in
// the order they are met, locals theirs per function, each one every
// language takes (letters, digits and single underscores, no keyword or
// builtin of GLSL, WGSL, MSL or HLSL, none of the entry points' own: main,
// main0, i, r, o, s, StageIn, StageOut, in_*, v_*, out_*, u_*, make_*,
// tex_*, smp_*), with _2, _3, ... when taken. The order is what keeps the
// emitted text the same from either language.
class Names {
	final globals = new Map<String, Bool>();

	public function new() {}

	// a struct's or function's name
	public function global(n:String):String {
		var s = unique(sanitize(n), n -> !globals.exists(n) && !ENTRY.match(n));
		globals.set(s, true);
		return s;
	}

	public function isGlobal(n:String):Bool
		return globals.exists(n);

	// the name, or with _2, _3, ... until free; never reserved
	public static function unique(n:String, free:String->Bool):String {
		var s = n, k = 1;
		while (!free(s) || reserved(s))
			s = n + "_" + ++k;
		return s;
	}

	public static function sanitize(n:String):String {
		var s = ~/[^A-Za-z0-9_]/g.replace(n, "_");
		s = ~/_+/g.replace(s, "_");
		while (StringTools.startsWith(s, "_"))
			s = s.substr(1);
		if (s == "" || ~/^[0-9]/.match(s)) s = "t" + s;
		return s;
	}

	// (a local may not hide a global of the same name: renamed at the end)
	public function unhide(vars:Map<SFunction, Array<SVar>>) {
		for (f => vs in vars)
			for (v in vs)
				if (globals.exists(v.name)) v.name = unique(v.name, n -> !globals.exists(n) && !Lambda.exists(vs, w -> w.name == n));
	}

	public static function same(a:SType, b:SType):Bool
		return switch [a, b] {
			case [TVec(n), TVec(m)]: n == m;
			case [TStruct(s), TStruct(r)]: s == r;
			case _: a == b;
		}

	// a type's zero (an optional field left out of a struct's value)
	public static function zero(t:SType):SExpr
		return switch t {
			case TBool: {e: EBool(false), t: t};
			case TInt: {e: EInt(0), t: t};
			case TFloat: {e: EFloat(0), t: t};
			case TVec(_): {e: ENew([{e: EFloat(0), t: TFloat}]), t: t};
			case TMat4: {e: ENew([for (_ in 0...4) {e: ENew([{e: EFloat(0), t: TFloat}]), t: TVec(4)}]), t: t};
			case TStruct(s): {e: ENew([for (f in s.fields) zero(f.type)]), t: t};
			case _: throw "zero";
		}

	// a type as the diagnostics name it
	public static function typeName(t:SType):String
		return switch t {
			case TVoid: "Void";
			case TBool: "Bool";
			case TInt: "Int";
			case TFloat: "Float";
			case TVec(n): 'Vec$n';
			case TMat4: "Mat4";
			case TTexture: "Texture2D";
			case TStruct(s): s.path;
		}

	static final ENTRY = ~/^(main|main0|i|r|o|s|StageIn|StageOut|(in|v|out|u|make|tex|smp)_.*)$/;
	static var RESERVED:Map<String, Bool>;

	// the keywords and builtins of GLSL ES 3.00, WGSL, MSL (C++) and HLSL
	public static function reserved(n:String):Bool {
		if (RESERVED == null) {
			RESERVED = new Map();
			for (w in ("attribute const uniform varying layout centroid flat smooth noperspective patch sample break continue do for while switch case default "
				+ "if else subroutine in out inout float double int void bool true false invariant precise discard return mat2 mat3 mat4 mat2x2 mat2x3 "
				+ "mat2x4 mat3x2 mat3x3 mat3x4 mat4x2 mat4x3 mat4x4 vec2 vec3 vec4 ivec2 ivec3 ivec4 bvec2 bvec3 bvec4 uint uvec2 uvec3 uvec4 lowp mediump "
				+ "highp precision sampler2D sampler3D samplerCube struct common partition active asm class union enum typedef template this resource "
				+ "goto inline noinline public static extern external interface long short half fixed unsigned superp input output filter sizeof cast "
				+ "namespace using texture sampler gl_Position gl_FragCoord "
				+ "fn let var alias override bitcast enable requires diagnostic loop continuing fallthrough f16 f32 i32 u32 vec2f vec3f vec4f vec2i "
				+ "vec3i vec4i mat4x4f array atomic ptr private storage workgroup function read write read_write select module "
				+ "auto catch char const_cast constexpr decltype delete dynamic_cast explicit export friend mutable new noexcept nullptr operator protected "
				+ "register reinterpret_cast signed static_assert static_cast thread throw try typeid typename virtual volatile wchar_t device constant "
				+ "threadgroup kernel vertex fragment packed_float3 float2 float3 float4 float4x4 half2 half3 half4 int2 int3 int4 uint2 uint3 uint4 metal "
				+ "cbuffer tbuffer row_major column_major packoffset nointerpolation linear point line triangle lineadj triangleadj vector matrix string "
				+ "technique pass compile dword min16float min16int SV_Position SV_Target TEXCOORD bool2 bool3 bool4 float1 groupshared "
				+ "abs sign floor ceil fract frac sqrt inversesqrt inverseSqrt rsqrt sin cos tan exp log min max pow step mix lerp clamp smoothstep dot "
				+ "length distance normalize reflect cross mul saturate mod atan atan2 any all transpose determinant").split(" "))
				RESERVED.set(w, true);
		}
		return RESERVED.exists(n) || StringTools.startsWith(n, "gl_");
	}
}
