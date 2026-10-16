package hxmc.gfx.shader;

import hxmc.gfx.shader.Ir;

// WGSL (WebGPU). Entry points named main: vertex attributes and varyings
// at @location(n), the position @builtin(position); a uniform block is
// `@group(0) @binding(n) var<uniform> u_<n>: <Struct>` (WGSL's uniform
// layout is std140's for these types), a texture at slot n `tex_<n>:
// texture_2d<f32>` at binding n and its `smp_<n>: sampler` at 16 + n. Locals are let unless assigned;
// an assigned parameter is copied into a var.
class Wgsl extends Emit {
	override function type(t:SType):String
		return switch t {
			case TVoid: "";
			case TBool: "bool";
			case TInt: "i32";
			case TFloat: "f32";
			case TVec(n): 'vec${n}f';
			case TMat4: "mat4x4f";
			case TTexture: "texture_2d<f32>";
			case TStruct(s): s.name;
		}

	override function struct(s:SStruct) {
		line('struct ${s.name} {');
		for (f in s.fields)
			line('\t${f.name}: ${type(f.type)},');
		line("}");
	}

	override function func(f:SFunction) {
		var params = [for (p in f.params) p.assigned ? p.name + "_in: " + type(p.type) : param(p)].join(", ");
		line('fn ${f.name}($params)' + (f.ret == TVoid ? "" : " -> " + type(f.ret)) + " {");
		for (p in f.params)
			if (p.assigned) line('\tvar ${p.name}: ${type(p.type)} = ${p.name}_in;');
		body(f.body);
		line("}");
	}

	override function param(v:SVar):String
		return v.name + ": " + type(v.type) + (v.type == TTexture ? ", " + v.name + "_smp: sampler" : "");

	override function arg(e:SExpr):String
		return e.t == TTexture ? expr(e) + ", " + expr(e) + "_smp" : expr(e);

	override function declare(v:SVar, init:Null<SExpr>):String
		return (v.assigned || init == null ? "var " : "let ") + v.name + ": " + type(v.type) + (init == null ? "" : " = " + expr(init)) + ";";

	override function expr(e:SExpr):String
		return switch e.e {
			case EConvert(x): type(e.t) + "(" + expr(x) + ")";
			case _: super.expr(e);
		}

	override function binary(op:SBinop, a:SExpr, b:SExpr):String
		return switch op {
			// (a shift's amount is a u32)
			case Shl | Shr: operand(a) + " " + Emit.binop(op) + " u32(" + expr(b) + ")";
			case _: super.binary(op, a, b);
		}

	override function cond(c:SExpr, a:SExpr, b:SExpr):String
		return "select(" + expr(b) + ", " + expr(a) + ", " + expr(c) + ")";

	override function builtin(name:String, args:Array<SExpr>, t:SType):String
		return name == "sample" ? "textureSampleLevel(" + arg(args[0]) + ", " + expr(args[1]) + ", 0.0)" : super.builtin(name == "inversesqrt" ? "inverseSqrt" : name, args, t);

	override function entry(p:SProgram, e:SEntry) {
		for (u in e.uniforms)
			line('@group(0) @binding(${u.binding}) var<uniform> u_${u.binding}: ${u.struct.name};');
		for (t in e.textures) {
			line('@group(0) @binding(${t.slot}) var tex_${t.slot}: texture_2d<f32>;');
			line('@group(0) @binding(${16 + t.slot}) var smp_${t.slot}: sampler;');
		}
		var uniforms = [
			for (r in e.resources)
				switch r {
					case RUniform(u): 'u_${u.binding}';
					case RTexture(t): 'tex_${t.slot}, smp_${t.slot}';
				}
		];
		var vs = Emit.varyings(p), pos = Emit.position(p);
		function io(prefix:String, f:SField, loc:Int):String
			return (f.position ? "@builtin(position) " : '@location($loc) ') + prefix + f.name + ": " + type(f.type);
		if (e.stage == Vertex) {
			line("struct StageOut {");
			line('\t' + io("", pos, 0) + ",");
			for (i in 0...vs.length)
				line('\t' + io("", vs[i], i) + ",");
			line("}");
			var params = [for (i in 0...e.input.fields.length) io("in_", e.input.fields[i], i)];
			line('@vertex fn main(${params.join(", ")}) -> StageOut {');
			var args = [e.input.name + "(" + [for (f in e.input.fields) 'in_${f.name}'].join(", ") + ")"].concat(uniforms);
			line('\tlet r = ${e.fn.name}(${args.join(", ")});');
			line('\treturn StageOut(' + [for (f in [pos].concat(vs)) 'r.${f.name}'].join(", ") + ");");
			line("}");
		} else {
			var params = [io("in_", pos, 0)].concat([for (i in 0...vs.length) io("in_", vs[i], i)]);
			line('@fragment fn main(${params.join(", ")}) -> @location(0) vec4f {');
			var args = [e.input.name + "(" + [for (f in e.input.fields) 'in_${f.name}'].join(", ") + ")"].concat(uniforms);
			line('\treturn ${e.fn.name}(${args.join(", ")});');
			line("}");
		}
	}
}
