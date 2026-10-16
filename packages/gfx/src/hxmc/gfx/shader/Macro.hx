package hxmc.gfx.shader;

import haxe.macro.Expr;
#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import hxmc.gfx.shader.Ir;
#end

// The shader macro (Shaders): at build time, a shader class's static
// functions are recorded as written and the generated members added; their
// values are expression macros, run when the class is typed:
//
//   typeClass()   (__shaders, every shader class) types the class's
//                 functions again without inlining (Context.withOptions),
//                 in the class's own context (its imports), so that calls
//                 to the math types and ShaderMath stay calls
//   code(stage)   the stage's ShaderCode: Lower makes the IR of the stages
//                 and the functions they reach (in any shader class: their
//                 __shaders forced first), the emitters print it in the
//                 target's languages; once per class
//   layout(), uniforms(), writeVertices(vs), writeUniforms(u, bytes, offset)
//                 the vertex layout, the uniform blocks and the CPU writers,
//                 from the same IR
//
// The languages: -D hxmc.gfx.shaders=glsl,wgsl,msl,hlsl (or all); else the
// target's (hxmc: -D hxmc.target or the host: GLSL on Linux, MSL on macOS,
// HLSL on Windows, GLSL and WGSL on wasm32-wasi), and all four on other
// targets (Eval: the tests).
class Macro {
	public static macro function typeClass():Expr {
		var c = Context.getLocalClass().get();
		var key = path(c);
		for (s in sources.get(key)) {
			var e = Context.withOptions({allowInlining: false}, () -> Context.typeExpr({expr: EFunction(FAnonymous, s.fn), pos: s.pos}));
			typed.set(key + "." + s.name, e);
		}
		done.set(key, true);
		return macro false;
	}

	public static macro function code(stage:Int):Expr {
		var p = compile();
		if (p == null) return macro cast null;
		var e = stage == 0 ? p.vertex : p.fragment;
		var fields:Array<ObjectField> = [];
		for (l in languages()) {
			var src = switch l {
				case "glsl": new Glsl().stage(p, e);
				case "wgsl": new Wgsl().stage(p, e);
				case "msl": new Msl().stage(p, e);
				case _: new Hlsl().stage(p, e);
			}
			fields.push({field: l, expr: macro $v{src}});
		}
		// (the slots of the stage's uniform blocks: GL binds them by name)
		var bindings = [
			for (u in e.uniforms)
				macro {name: $v{u.struct.name + "_block"}, slot: $v{u.binding}, kind: hxmc.gfx.ShaderBinding.BindingKind.Uniform, size: $v{u.size}}
		];
		fields.push({field: "bindings", expr: macro [$a{bindings}]});
		return {expr: EObjectDecl(fields), pos: Context.currentPos()};
	}

	public static macro function layout():Expr {
		var p = compile(), off = 0;
		if (p == null) return macro cast null;
		var attrs = [
			for (i in 0...p.vertex.input.fields.length) {
				var f = p.vertex.input.fields[i];
				var n = switch f.type {
					case TVec(n): n;
					case _: 1;
				}
				var fmt = "Float" + n;
				var a = macro {location: $v{i}, format: hxmc.gfx.VertexFormat.$fmt, offset: $v{off}};
				off += 4 * n;
				a;
			}
		];
		return macro ([{stride: $v{off}, attributes: [$a{attrs}]}] : Array<hxmc.gfx.VertexBufferLayout>);
	}

	public static macro function uniforms():Expr {
		var p = compile();
		if (p == null) return macro cast null;
		var us = [
			for (u in p.uniforms)
				macro {name: $v{u.struct.name}, binding: $v{u.binding}, size: $v{u.size}}
		];
		return macro ([$a{us}] : Array<hxmc.gfx.shader.Shaders.UniformBlock>);
	}

	// the vertices, packed as layout() says (Float32 each)
	public static macro function writeVertices(vertices:Expr):Expr {
		var p = compile(), stride = 0;
		if (p == null) return macro cast null;
		var stores = [];
		for (f in p.vertex.input.fields) {
			var n = f.field;
			var v = macro v.$n;
			for (k in components(f.type)) {
				var x = k == null ? v : macro $v.$k;
				stores.push(macro bytes.setFloat(o + $v{stride}, $x));
				stride += 4;
			}
		}
		return macro {
			var vs = $vertices;
			var bytes = haxe.io.Bytes.alloc($v{stride} * vs.length);
			for (i in 0...vs.length) {
				var v = vs[i], o = i * $v{stride};
				$b{stores};
			}
			bytes;
		};
	}

	// a uniform block's struct at offset (std140: bytes.length >= offset + size)
	public static macro function writeUniforms(u:Expr, bytes:Expr, offset:Expr):Expr {
		var p = compile();
		if (p == null) return macro cast null;
		var t = Context.typeof(u);
		var block = Lambda.find(p.uniforms, b -> switch t {
			case TInst(c, _): b.struct.path == path(c.get());
			case _: false;
		});
		if (block == null) Context.error("shader: not a uniform block of this class", u.pos);
		var stores = [];
		for (i in 0...block.struct.fields.length) {
			var f = block.struct.fields[i], off = block.offsets[i];
			var n = f.field;
			var v = macro u.$n;
			switch f.type {
				case TInt: stores.push(macro b.setInt32(o + $v{off}, $v));
				case TMat4:
					for (c in 0...4)
						for (k in 0...4) {
							var col = "c" + c, comp = "xyzw".charAt(k);
							stores.push(macro b.setFloat(o + $v{off + 16 * c + 4 * k}, $v.$col.$comp));
						}
				case t:
					var k = 0;
					for (c in components(t))
						stores.push(macro b.setFloat(o + $v{off + 4 * k++}, ${c == null ? v : macro $v.$c}));
			}
		}
		return macro {
			var u = $u, b:haxe.io.Bytes = $bytes, o:Int = $offset;
			$b{stores};
		};
	}

	#if macro
	// the static functions of each shader class (by path), as written
	static var sources = new Map<String, Array<{name:String, fn:Function, pos:Position}>>();
	// typed without inlining: "<class path>.<name>"
	static var typed = new Map<String, TypedExpr>();
	static var done = new Map<String, Bool>();
	static var programs = new Map<String, SProgram>();
	static var failed = new Map<String, Bool>();

	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var c = Context.getLocalClass().get();
		var pos = Context.currentPos();
		var src = [];
		var vertex:Function = null, fragment:Function = null;
		for (f in fields) {
			var stage = Lambda.exists(f.meta, m -> m.name == ":vertex") ? 0 : Lambda.exists(f.meta, m -> m.name == ":fragment") ? 1 : -1;
			switch f.kind {
				case FFun(fn) if (f.access.contains(AStatic) && !f.access.contains(AMacro)):
					src.push({name: f.name, fn: fn, pos: f.pos});
					if (stage == 0) vertex = fn;
					if (stage == 1) fragment = fn;
				case _ if (stage >= 0):
					Context.error("shader: a @:vertex or @:fragment stage is a static function", f.pos);
				case _:
			}
		}
		sources.set(path(c), src);
		fields.push({
			name: "__shaders",
			access: [AStatic, AInline],
			meta: [{name: ":noCompletion", pos: pos}],
			kind: FVar(macro :Bool, macro hxmc.gfx.shader.Macro.typeClass()),
			pos: pos
		});
		if (vertex == null && fragment == null) return fields;
		if (vertex == null || fragment == null) Context.error('shader: ${c.name} has a ' + (vertex == null ? "@:fragment but no @:vertex" : "@:vertex but no @:fragment")
			+ " function", c.pos);
		if (vertex.args.length == 0 || vertex.args[0].type == null) Context.error("shader: the @:vertex function takes a vertex (with its type)", c.pos);
		var vt = vertex.args[0].type;
		var generated = (macro class {
			public static final vertexCode:hxmc.gfx.ShaderCode = hxmc.gfx.shader.Macro.code(0);
			public static final fragmentCode:hxmc.gfx.ShaderCode = hxmc.gfx.shader.Macro.code(1);
			public static final layout:Array<hxmc.gfx.VertexBufferLayout> = hxmc.gfx.shader.Macro.layout();
			public static final uniforms:Array<hxmc.gfx.shader.Shaders.UniformBlock> = hxmc.gfx.shader.Macro.uniforms();

			// the pipeline of both stages and the vertex layout (Device.createPipeline compiles the code)
			public static function pipeline(?options:{?topology:hxmc.gfx.Topology, ?cull:hxmc.gfx.Cull}):hxmc.gfx.PipelineDesc
				return {
					program: {vertex: vertexCode, fragment: fragmentCode},
					layout: layout,
					topology: options == null ? null : options.topology,
					cull: options == null ? null : options.cull
				};

			// the vertex buffer's contents
			public static function vertexBytes(vertices:Array<$vt>):haxe.io.Bytes
				return hxmc.gfx.shader.Macro.writeVertices(vertices);
		}).fields;
		// a writer per uniform block type
		var seen = new Map<String, Bool>();
		for (fn in [vertex, fragment])
			for (a in fn.args.slice(1)) {
				var name = switch a.type {
					case TPath(p): p.sub != null ? p.sub : p.name;
					case _: null;
				}
				if (name == null || seen.exists(name)) continue;
				seen.set(name, true);
				var t = a.type;
				generated.push({
					name: "write" + name,
					access: [APublic, AStatic],
					kind: FFun({
						args: [{name: "u", type: t}, {name: "bytes", type: macro :haxe.io.Bytes}, {name: "offset", type: macro :Int, value: macro 0}],
						ret: macro :Void,
						expr: macro hxmc.gfx.shader.Macro.writeUniforms(u, bytes, offset)
					}),
					pos: pos
				});
			}
		for (g in generated)
			g.pos = pos;
		return fields.concat(generated);
	}

	// the typed function of a shader class (null: not one), typing the class first
	public static function typedFunction(c:ClassType, name:String):Null<TypedExpr> {
		var key = path(c);
		if (!sources.exists(key)) return null;
		if (!done.exists(key))
			for (f in c.statics.get())
				if (f.name == "__shaders") f.expr();
		return typed.get(key + "." + name);
	}

	// the class's program, once (null: it failed, and the error is reported)
	static function compile():SProgram {
		var c = Context.getLocalClass().get();
		var key = path(c);
		if (failed.exists(key)) return null;
		var p = programs.get(key);
		if (p == null) {
			// (an error is reported once, not by each generated member)
			failed.set(key, true);
			p = new Lower().program(c);
			failed.remove(key);
			programs.set(key, p);
		}
		return p;
	}

	static function components(t:SType):Array<Null<String>>
		return switch t {
			case TVec(n): [for (i in 0...n) "xyzw".charAt(i)];
			case _: [null];
		}

	static function languages():Array<String> {
		var all = ["glsl", "wgsl", "msl", "hlsl"];
		var d = Context.definedValue("hxmc.gfx.shaders");
		if (d != null) {
			if (d == "all" || d == "1") return all;
			var ls = d.split(",");
			for (l in ls)
				if (!all.contains(l)) Context.error('-D hxmc.gfx.shaders: no shader language $l (glsl, wgsl, msl, hlsl, all)', Context.currentPos());
			return ls;
		}
		if (Context.definedValue("target.name") != "hxmc") return all;
		var t = Context.definedValue("hxmc.target");
		if (t == null) t = switch Sys.systemName() {
			case "Mac": "macos";
			case "Windows": "windows";
			case _: "linux";
		}
		return t == "wasm32-wasi" ? ["glsl", "wgsl"] : StringTools.startsWith(t, "macos") ? ["msl"] : StringTools.startsWith(t, "windows") ? ["hlsl"] : ["glsl"];
	}

	static function path(c:ClassType):String
		return c.pack.concat([c.name]).join(".");
	#end
}
