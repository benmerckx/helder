package helder.gfx.shader;

import helder.gfx.shader.Ir;

// MSL (Metal). Entry points named main0: vertex attributes at
// [[attribute(n)]] of a [[stage_in]] struct, the varyings a struct both
// stages share ([[position]], the others matched by name); a uniform block
// is `constant <Struct>_buffer& u_<n> [[buffer(n)]]` (vertex buffers are at
// 16 and up), a struct laid out as std140 (packed_float3 and padding),
// converted to the program's struct for the stage's function; a texture
// at slot n `texture2d<float> tex_<n> [[texture(n)]]` and its `sampler
// smp_<n> [[sampler(n)]]`.
class Msl extends Emit {
	override function header(e:SEntry) {
		line("#include <metal_stdlib>");
		line("using namespace metal;");
	}

	override function type(t:SType):String
		return switch t {
			case TVoid: "void";
			case TBool: "bool";
			case TInt: "int";
			case TFloat: "float";
			case TVec(n): 'float$n';
			case TMat4: "float4x4";
			case TTexture: "texture2d<float>";
			case TStruct(s): s.name;
		}

	override function param(v:SVar):String
		return type(v.type) + " " + v.name + (v.type == TTexture ? ", sampler " + v.name + "_smp" : "");

	override function arg(e:SExpr):String
		return e.t == TTexture ? expr(e) + ", " + expr(e) + "_smp" : expr(e);

	override function construct(t:SType, args:Array<SExpr>):String
		return switch t {
			case TStruct(s): s.name + "{" + [for (a in args) expr(a)].join(", ") + "}";
			case _: super.construct(t, args);
		}

	override function builtin(name:String, args:Array<SExpr>, t:SType):String
		return switch name {
			case "sample" if (fragment): operand(args[0]) + ".sample(" + expr(args[0]) + "_smp, " + expr(args[1]) + ")";
			case "sample": operand(args[0]) + ".sample(" + expr(args[0]) + "_smp, " + expr(args[1]) + ", level(0.0))";
			case "sampleLevel": operand(args[0]) + ".sample(" + expr(args[0]) + "_smp, " + expr(args[1]) + ", level(" + expr(args[2]) + "))";
			case _: super.builtin(name == "inversesqrt" ? "rsqrt" : name, args, t);
		}

	override function entry(p:SProgram, e:SEntry) {
		for (u in e.uniforms) {
			line('struct ${u.struct.name}_buffer {');
			var off = 0, pad = 0;
			for (i in 0...u.struct.fields.length) {
				var f = u.struct.fields[i];
				if (u.offsets[i] > off) line('\tfloat pad${pad++}[${(u.offsets[i] - off) >> 2}];');
				line('\t' + (f.type.match(TVec(3)) ? "packed_float3" : type(f.type)) + ' ${f.name};');
				off = u.offsets[i] + switch f.type {
					case TVec(n): 4 * n;
					case TMat4: 64;
					case _: 4;
				}
			}
			line("};");
		}
		var params = [
			for (r in e.resources)
				switch r {
					case RUniform(u): 'constant ${u.struct.name}_buffer& u_${u.binding} [[buffer(${u.binding})]]';
					case RTexture(t): 'texture2d<float> tex_${t.slot} [[texture(${t.slot})]], sampler smp_${t.slot} [[sampler(${t.slot})]]';
				}
		];
		var args = [
			for (r in e.resources)
				switch r {
					case RUniform(u):
						u.struct.name + "{" + [
							for (f in u.struct.fields)
								f.type.match(TVec(3)) ? 'float3(u_${u.binding}.${f.name})' : 'u_${u.binding}.${f.name}'
						].join(", ") + "}";
					case RTexture(t): 'tex_${t.slot}, smp_${t.slot}';
				}
		];
		var vs = Emit.varyings(p), pos = Emit.position(p);
		var input = e.input.name + "{" + [for (f in e.input.fields) 'i.${f.name}'].join(", ") + "}";
		if (e.stage == Vertex) {
			line("struct StageIn {");
			for (i in 0...e.input.fields.length) {
				var f = e.input.fields[i];
				line('\t${type(f.type)} ${f.name} [[attribute($i)]];');
			}
			line("};");
			stageOut(p);
			line('vertex StageOut main0(' + ["StageIn i [[stage_in]]"].concat(params).join(", ") + ") {");
			line('\t${p.varyings.name} r = ${e.fn.name}(' + [input].concat(args).join(", ") + ");");
			line('\treturn StageOut{' + [for (f in [pos].concat(vs)) 'r.${f.name}'].join(", ") + "};");
			line("}");
		} else {
			stageOut(p);
			line('fragment float4 main0(' + ["StageOut i [[stage_in]]"].concat(params).join(", ") + ") {");
			var input = e.input.name + "{" + [for (f in e.input.fields) 'i.${f.name}'].join(", ") + "}";
			line('\treturn ${e.fn.name}(' + [input].concat(args).join(", ") + ");");
			line("}");
		}
	}

	function stageOut(p:SProgram) {
		var vs = Emit.varyings(p), pos = Emit.position(p);
		line("struct StageOut {");
		line('\tfloat4 ${pos.name} [[position]];');
		for (i in 0...vs.length)
			line('\t${type(vs[i].type)} ${vs[i].name} [[user(locn$i)]];');
		line("};");
	}
}
