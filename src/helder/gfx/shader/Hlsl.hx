package helder.gfx.shader;

import helder.gfx.shader.Ir;

// HLSL (D3D11, shader model 4.0 and 5.0). Entry points named main: vertex
// attributes at TEXCOORD<n>, the varyings TEXCOORD<n> but the position
// (SV_Position), the colour SV_Target; a uniform block is a cbuffer at
// register(b<n>), its fields u_<n>_<field> at their std140 offsets; a
// texture at slot n `Texture2D tex_<n> : register(t<n>)` and its
// `SamplerState smp_<n> : register(s<n>)`. HLSL
// has no struct constructors: make_<Struct> functions. A matrix is stored
// transposed (float4x4's rows are the columns: row_major in a cbuffer), so
// that the columns' memory order is GLSL's: m * v is mul(v, m), a * b is
// mul(b, a), a column is m[i].
class Hlsl extends Emit {
	override function type(t:SType):String
		return switch t {
			case TVoid: "void";
			case TBool: "bool";
			case TInt: "int";
			case TFloat: "float";
			case TVec(n): 'float$n';
			case TMat4: "float4x4";
			case TTexture: "Texture2D";
			case TStruct(s): s.name;
		}

	override function struct(s:SStruct) {
		super.struct(s);
		line('${s.name} make_${s.name}(' + [for (i in 0...s.fields.length) type(s.fields[i].type) + " f" + i].join(", ") + ") {");
		line('\t${s.name} s;');
		for (i in 0...s.fields.length)
			line('\ts.${s.fields[i].name} = f$i;');
		line("\treturn s;");
		line("}");
	}

	override function param(v:SVar):String
		return type(v.type) + " " + v.name + (v.type == TTexture ? ", SamplerState " + v.name + "_smp" : "");

	override function arg(e:SExpr):String
		return e.t == TTexture ? expr(e) + ", " + expr(e) + "_smp" : expr(e);

	override function construct(t:SType, args:Array<SExpr>):String
		return switch [t, args] {
			case [TStruct(s), _]: 'make_${s.name}(' + [for (a in args) expr(a)].join(", ") + ")";
			// (one scalar for every component)
			case [TVec(_), [a]] if (a.t == TFloat): "((" + type(t) + ")" + operand(a) + ")";
			case _: super.construct(t, args);
		}

	override function binary(op:SBinop, a:SExpr, b:SExpr):String
		return switch [op, a.t, b.t] {
			case [Mul, TMat4, TVec(4)]: "mul(" + expr(b) + ", " + expr(a) + ")";
			case [Mul, TMat4, TMat4]: "mul(" + expr(b) + ", " + expr(a) + ")";
			case _: super.binary(op, a, b);
		}

	override function builtin(name:String, args:Array<SExpr>, t:SType):String
		return switch name {
			case "fract": super.builtin("frac", args, t);
			case "mix": super.builtin("lerp", args, t);
			case "inversesqrt": super.builtin("rsqrt", args, t);
			case "sample" if (fragment): operand(args[0]) + ".Sample(" + expr(args[0]) + "_smp, " + expr(args[1]) + ")";
			case "sample": operand(args[0]) + ".SampleLevel(" + expr(args[0]) + "_smp, " + expr(args[1]) + ", 0.0)";
			case "sampleLevel": operand(args[0]) + ".SampleLevel(" + expr(args[0]) + "_smp, " + expr(args[1]) + ", " + expr(args[2]) + ")";
			// (an int: back to floats)
			case "sign": "((" + type(t) + ")" + super.builtin("sign", args, t) + ")";
			case _: super.builtin(name, args, t);
		}

	override function entry(p:SProgram, e:SEntry) {
		for (u in e.uniforms) {
			line('cbuffer ${u.struct.name}_block : register(b${u.binding}) {');
			for (i in 0...u.struct.fields.length) {
				var f = u.struct.fields[i], o = u.offsets[i];
				line('\t' + (f.type == TMat4 ? "row_major " : "") + type(f.type) + ' u_${u.binding}_${f.name} : packoffset(c${o >> 4}' + (o & 15 == 0 ? "" : "." + "xyzw".charAt((o & 15) >> 2)) + ");");
			}
			line("};");
		}
		for (t in e.textures) {
			line('Texture2D tex_${t.slot} : register(t${t.slot});');
			line('SamplerState smp_${t.slot} : register(s${t.slot});');
		}
		var args = [
			for (r in e.resources)
				switch r {
					case RUniform(u): 'make_${u.struct.name}(' + [for (f in u.struct.fields) 'u_${u.binding}_${f.name}'].join(", ") + ")";
					case RTexture(t): 'tex_${t.slot}, smp_${t.slot}';
				}
		];
		var vs = Emit.varyings(p), pos = Emit.position(p);
		var input = 'make_${e.input.name}(' + [for (f in e.input.fields) 'i.${f.name}'].join(", ") + ")";
		if (e.stage == Vertex) {
			line("struct StageIn {");
			for (i in 0...e.input.fields.length) {
				var f = e.input.fields[i];
				line('\t${type(f.type)} ${f.name} : TEXCOORD$i;');
			}
			line("};");
			stageOut(p);
			line("StageOut main(StageIn i) {");
			line('\t${p.varyings.name} r = ${e.fn.name}(' + [input].concat(args).join(", ") + ");");
			line("\tStageOut o;");
			for (f in [pos].concat(vs))
				line('\to.${f.name} = r.${f.name};');
			line("\treturn o;");
			line("}");
		} else {
			stageOut(p);
			line("float4 main(StageOut i) : SV_Target {");
			line('\treturn ${e.fn.name}(' + [input].concat(args).join(", ") + ");");
			line("}");
		}
	}

	function stageOut(p:SProgram) {
		var vs = Emit.varyings(p), pos = Emit.position(p);
		line("struct StageOut {");
		line('\tfloat4 ${pos.name} : SV_Position;');
		for (i in 0...vs.length)
			line('\t${type(vs[i].type)} ${vs[i].name} : TEXCOORD$i;');
		line("};");
	}
}
