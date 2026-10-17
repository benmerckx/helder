package hxmc.gfx.shader;

import hxmc.gfx.shader.Ir;

// GLSL ES 3.00 (GL and WebGL2). Vertex attributes at
// `layout(location = n) in`, varyings matched by name (v_<field>), the
// colour out_color; a uniform block is `layout(std140) uniform
// <Struct>_block`, a texture `uniform sampler2D tex_<slot>` (highp), their
// slots set through the API by those names (ES 3.00 has no
// layout(binding): ShaderCode.bindings). The conventions are the other
// languages' (Shaders): clip z from 0 to w (GL's from -w: the vertex stage
// maps it), the fragment position from the top left (GL's gl_FragCoord.y
// is from the bottom: flipped with the frame's height) and a texture's
// first row its top (in a pass into a texture, the position's y is
// flipped instead): u_target, which the back end sets, is (height, -1) in
// the frame, (0, 1) in a texture.
class Glsl extends Emit {
	// structs made through make_<Struct> functions instead of their
	// constructors (as Hlsl): the shader compiler of Android's emulator
	// (its GLES translator) rejects a struct constructor whose argument is a
	// constructor call ("Structure constructor arguments do not match
	// structure fields"); for the Android targets
	final makers:Bool;

	public function new(makers = false) {
		super();
		this.makers = makers;
	}

	override function struct(s:SStruct) {
		super.struct(s);
		if (!makers) return;
		line('${s.name} make_${s.name}(' + [for (i in 0...s.fields.length) type(s.fields[i].type) + " f" + i].join(", ") + ") {");
		line('	${s.name} s;');
		for (i in 0...s.fields.length)
			line('	s.${s.fields[i].name} = f$i;');
		line("\treturn s;");
		line("}");
	}

	override function construct(t:SType, args:Array<SExpr>):String
		return switch t {
			case TStruct(s) if (makers): 'make_${s.name}(' + [for (a in args) expr(a)].join(", ") + ")";
			case _: super.construct(t, args);
		}

	// a struct's constructor in the entry point
	inline function make(name:String):String
		return makers ? "make_" + name : name;

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
		return switch name {
			case "sample" if (fragment): super.builtin("texture", args, t);
			case "sample": "textureLod(" + expr(args[0]) + ", " + expr(args[1]) + ", 0.0)";
			case "sampleLevel": super.builtin("textureLod", args, t);
			case _: super.builtin(name, args, t);
		}

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
					case RUniform(u): make(u.struct.name) + "(" + [for (f in u.struct.fields) 'u_${u.binding}.${f.name}'].join(", ") + ")";
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
			line("uniform vec2 u_target;");
			line("void main() {");
			args.unshift(make(e.input.name) + "(" + [for (f in e.input.fields) 'in_${f.name}'].join(", ") + ")");
			line('\t${p.varyings.name} r = ${e.fn.name}(${args.join(", ")});');
			// (clip z from 0..w to GL's -w..w; y upside down into a texture)
			var pos = 'r.${Emit.position(p).name}';
			line('\tgl_Position = vec4($pos.x, -u_target.y * $pos.y, 2.0 * $pos.z - $pos.w, $pos.w);');
			for (f in Emit.varyings(p))
				line('\tv_${f.name} = r.${f.name};');
			line("}");
		} else {
			for (f in Emit.varyings(p))
				line('in ${type(f.type)} v_${f.name};');
			line("uniform vec2 u_target;");
			line("out vec4 out_color;");
			line("void main() {");
			args.unshift(make(e.input.name) + "(" + [for (f in e.input.fields) f.position ? "vec4(gl_FragCoord.x, u_target.x + u_target.y * gl_FragCoord.y, gl_FragCoord.zw)" : 'v_${f.name}'].join(", ") + ")");
			line('\tout_color = ${e.fn.name}(${args.join(", ")});');
			line("}");
		}
	}
}
