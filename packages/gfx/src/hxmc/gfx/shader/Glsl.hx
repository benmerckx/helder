package hxmc.gfx.shader;

import hxmc.gfx.shader.Ir;

// GLSL ES 3.00 (GL and WebGL2). Vertex attributes at
// `layout(location = n) in`, varyings matched by name (v_<field>), the
// colour out_color; a uniform block is `layout(std140) uniform
// <Struct>_block`, a texture `uniform sampler2D tex_<slot>` (highp), their
// slots set through the API by those names (ES 3.00 has no
// layout(binding): ShaderCode.bindings).
class Glsl extends Emit {
	override function header(e:SEntry) {
		line("#version 300 es");
		if (e.stage == Fragment) {
			line("precision highp float;");
			line("precision highp int;");
		}
		if (e.textures.length > 0) line("precision highp sampler2D;");
	}

	override function type(t:SType):String
		return switch t {
			case TVoid: "void";
			case TBool: "bool";
			case TInt: "int";
			case TFloat: "float";
			case TVec(n): 'vec$n';
			case TMat4: "mat4";
			case TTexture: "sampler2D";
			case TStruct(s): s.name;
		}

	override function builtin(name:String, args:Array<SExpr>, t:SType):String
		return name == "sample" ? "textureLod(" + expr(args[0]) + ", " + expr(args[1]) + ", 0.0)" : super.builtin(name, args, t);

	override function entry(p:SProgram, e:SEntry) {
		for (u in e.uniforms) {
			line('layout(std140) uniform ${u.struct.name}_block {');
			for (f in u.struct.fields)
				line('\t${type(f.type)} ${f.name};');
			line('} u_${u.binding};');
		}
		for (t in e.textures)
			line('uniform sampler2D tex_${t.slot};');
		var args = [
			for (r in e.resources)
				switch r {
					case RUniform(u): u.struct.name + "(" + [for (f in u.struct.fields) 'u_${u.binding}.${f.name}'].join(", ") + ")";
					case RTexture(t): 'tex_${t.slot}';
				}
		];
		if (e.stage == Vertex) {
			for (i in 0...e.input.fields.length) {
				var f = e.input.fields[i];
				line('layout(location = $i) in ${type(f.type)} in_${f.name};');
			}
			for (f in Emit.varyings(p))
				line('out ${type(f.type)} v_${f.name};');
			line("void main() {");
			args.unshift(e.input.name + "(" + [for (f in e.input.fields) 'in_${f.name}'].join(", ") + ")");
			line('\t${p.varyings.name} r = ${e.fn.name}(${args.join(", ")});');
			line('\tgl_Position = r.${Emit.position(p).name};');
			for (f in Emit.varyings(p))
				line('\tv_${f.name} = r.${f.name};');
			line("}");
		} else {
			for (f in Emit.varyings(p))
				line('in ${type(f.type)} v_${f.name};');
			line("out vec4 out_color;");
			line("void main() {");
			args.unshift(e.input.name + "(" + [for (f in e.input.fields) f.position ? "gl_FragCoord" : 'v_${f.name}'].join(", ") + ")");
			line('\tout_color = ${e.fn.name}(${args.join(", ")});');
			line("}");
		}
	}
}
