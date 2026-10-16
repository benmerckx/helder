package hxmc.gfx.shader;

import hxmc.gfx.shader.Ir;

// WGSL (WebGPU). Entry points named main: vertex attributes and varyings
// at @location(n), the position @builtin(position); a uniform block is
// `@group(0) @binding(n) var<uniform> u_<n>: <Struct>` (WGSL's uniform
// layout is std140's for these types); a texture is `@group(0)
// @binding(16 + 2 * slot) var tex_<slot>: texture_2d<f32>`, its sampler
// smp_<slot> at the next binding, sampled at level 0 (textureSampleLevel:
// no uniform control flow needed). Locals are let unless assigned; an
// assigned parameter is copied into a var.
class Wgsl extends Emit {
	override function type(t:SType):String
		return switch t {
			case TVoid: "";
			case TBool: "bool";
			case TInt: "i32";
			case TFloat: "f32";
			case TVec(n): 'vec${n}f';
			case TMat4: "mat4x4f";
			case TStruct(s): s.name;
			case TTexture: "texture_2d<f32>";
		}

	override function struct(s:SStruct) {
		line('struct ${s.name} {');
		for (f in s.fields)
			line('\t${f.name}: ${type(f.type)},');
		line("}");
	}

	override function func(f:SFunction) {
		var params = [
			for (p in f.params)
				p.type == TTexture ? p.name + ": texture_2d<f32>, " + p.sampler + ": sampler" : (p.assigned ? p.name + "_in" : p.name) + ": " + type(p.type)
		].join(", ");
		line('fn ${f.name}($params)' + (f.ret == TVoid ? "" : " -> " + type(f.ret)) + " {");
		for (p in f.params)
			if (p.assigned) line('\tvar ${p.name}: ${type(p.type)} = ${p.name}_in;');
		body(f.body);
		line("}");
	}

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
		return switch [name, args[0].e] {
			case ["texture", ELocal(v)]: "textureSampleLevel(" + v.name + ", " + v.sampler + ", " + expr(args[1]) + ", 0.0)";
			case _: super.builtin(name == "inversesqrt" ? "inverseSqrt" : name, args, t);
		}

	override function entry(p:SProgram, e:SEntry) {
		for (u in e.uniforms)
			line('@group(0) @binding(${u.binding}) var<uniform> u_${u.binding}: ${u.struct.name};');
		for (i in 0...e.textures) {
			line('@group(0) @binding(${16 + 2 * i}) var tex_$i: texture_2d<f32>;');
			line('@group(0) @binding(${17 + 2 * i}) var smp_$i: sampler;');
		}
		var uniforms = extraArgs(e, u -> 'u_${u.binding}');
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
