package helder.gfx.shader;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.definition.HaxeAdapter;
import helder.gfx.shader.Ir;
import helder.gfx.shader.ShaderDefinition;

using haxe.macro.Tools;

// shader({...}) in Haxe (ShaderMath.shader forwards here): the argument's
// kernel tree (HaxeAdapter), the handler (ShaderDefinition) with Lower as
// its adapter, and the handler's output as the expression of a Shader: the
// text and layouts as literals, the writers as code storing each field,
// the stage functions as they are (CPU code).
class ShaderMacro {
	public static function shader(def:Expr):Expr {
		var arg = new HaxeAdapter("shader").node(def);
		var lower = new Lower();
		var out = new ShaderDefinition().generate(arg, lower);
		var stages = switch def.expr {
			case EObjectDecl(fs): fs;
			case _: [];
		}
		function stage(name:String):Expr {
			var e = Lambda.find(stages, f -> f.field == name).expr;
			// (the fragment function's varyings when not written)
			return switch e.expr {
				case EFunction(k, f) if (name == "fragment" && f.args.length > 0 && f.args[0].type == null):
					var g = Reflect.copy(f);
					g.args = [Reflect.copy(f.args[0])].concat(f.args.slice(1));
					g.args[0].type = lower.haxeType(out.program.varyings).toComplexType();
					{expr: EFunction(k, g), pos: e.pos};
				case _: e;
			}
		}
		return build(out, lower, {
			vertex: stage("vertex"),
			fragment: stage("fragment"),
			vertexType: lower.stageTypes.get("vs").toComplexType(),
			fragmentType: lower.stageTypes.get("fs").toComplexType()
		});
	}

	// the expression of a Shader: the handler's output as literals and
	// writers, the stages' CPU code as given (with their types)
	public static function build(out:ShaderOutput, lower:Lower, stages:{vertex:Expr, fragment:Expr, vertexType:ComplexType, fragmentType:ComplexType}):Expr {
		var p = out.program;
		var pos = Context.currentPos();
		function code(s:StageCode):Expr {
			var fields:Array<ObjectField> = [for (c in s.code) {field: c.language, expr: macro $v{c.text}}];
			var bindings = [
				for (b in s.bindings)
					b.uniform ? macro {name: $v{b.name}, slot: $v{b.slot}, kind: helder.gfx.ShaderBinding.BindingKind.Uniform, size: $v{b.size}} : macro {
						name: $v{b.name},
						slot: $v{b.slot},
						kind: helder.gfx.ShaderBinding.BindingKind.Texture
					}
			];
			fields.push({field: "bindings", expr: macro [$a{bindings}]});
			return {expr: EObjectDecl(fields), pos: pos};
		}
		var attrs = [
			for (i in 0...out.attributes.length) {
				var a = out.attributes[i], fmt = "Float" + a.components;
				macro {location: $v{i}, format: helder.gfx.VertexFormat.$fmt, offset: $v{a.offset}};
			}
		];
		var layout = macro ([{stride: $v{out.stride}, attributes: [$a{attrs}]}] : Array<helder.gfx.VertexBufferLayout>);
		var uniforms = macro ([$a{[for (u in p.uniforms) macro {name: $v{u.struct.name}, binding: $v{u.binding}, size: $v{u.size}}]}] : Array<helder.gfx.shader.Shader.UniformBlock>);
		var textures = macro ([$a{[for (t in p.textures) macro {name: $v{t.name}, binding: $v{t.slot}}]}] : Array<helder.gfx.shader.Shader.TextureBinding>);
		// the vertices, packed as layout says (Float32 each)
		var vt = lower.haxeType(p.vertex.input).toComplexType(), stores = [];
		for (a in out.attributes) {
			var n = a.field;
			var v = macro v.$n;
			for (k in components(a.components)) {
				var x = k == null ? v : macro $v.$k;
				stores.push(macro bytes.setFloat(o + $v{a.offset + 4 * (k == null ? 0 : "xyzw".indexOf(k))}, $x));
			}
		}
		var writeVertices = macro function(vs:Array<$vt>):haxe.io.Bytes {
			var bytes = haxe.io.Bytes.alloc($v{out.stride} * vs.length);
			for (i in 0...vs.length) {
				var v = vs[i], o = i * $v{out.stride};
				$b{stores};
			}
			return bytes;
		};
		// the parameters: a writer per uniform block, a slot per texture
		var params:Array<ObjectField> = [];
		for (b in out.params) {
			var u = switch b.resource {
				case RUniform(u): u;
				case RTexture(t):
					params.push({field: b.name, expr: macro new helder.gfx.shader.Shader.TextureSlot($v{t.name}, $v{t.slot})});
					continue;
			}
			var ut = lower.haxeType(u.struct).toComplexType(), stores = [];
			for (i in 0...u.struct.fields.length) {
				var f = u.struct.fields[i], off = u.offsets[i];
				var n = f.field;
				var v = macro u.$n;
				switch f.type {
					case TArray(t, len):
						// (its elements, as many as it has up to its length; zeros after)
						var size = t == TMat4 ? 64 : 16;
						var each = t == TMat4 ? [
							for (c in 0...4) for (k in 0...4) {
								var col = "c" + c, comp = "xyzw".charAt(k);
								macro b.setFloat(at + $v{16 * c + 4 * k}, x.$col.$comp);
							}
						] : [for (k in 0...4) {
							var comp = "xyzw".charAt(k);
							macro b.setFloat(at + $v{4 * k}, x.$comp);
						}];
						stores.push(macro {
							var a = $v, m = 0;
							if (a != null) m = a.length < $v{len} ? a.length : $v{len};
							for (j in 0...m) {
								var x = a[j], at = o + $v{off} + $v{size} * j;
								$b{each};
							}
							b.fill(o + $v{off} + $v{size} * m, $v{size} * ($v{len} - m), 0);
						});
					case TInt: stores.push(macro b.setInt32(o + $v{off}, $v));
					case TMat4:
						for (c in 0...4)
							for (k in 0...4) {
								var col = "c" + c, comp = "xyzw".charAt(k);
								stores.push(macro b.setFloat(o + $v{off + 16 * c + 4 * k}, $v.$col.$comp));
							}
					case t:
						var k = 0;
						for (c in components(switch t {
							case TVec(n): n;
							case _: 1;
						}))
							stores.push(macro b.setFloat(o + $v{off + 4 * k++}, ${c == null ? v : macro $v.$c}));
				}
			}
			var block = macro {name: $v{u.struct.name}, binding: $v{u.binding}, size: $v{u.size}};
			params.push({
				field: b.name,
				expr: macro new helder.gfx.shader.Shader.UniformWriter<$ut>($block, function(u:$ut, b:haxe.io.Bytes, o:Int):Void {
					$b{stores};
				})
			});
		}
		// the shader's own class (its stages' exact types: hxmc calls a function
		// of struct values only as such), named after its module, its field and
		// a hash of its content: a compilation server's cached one is the same
		var module = Context.getLocalModule(), field = Context.getLocalMethod() ?? "shader";
		var pack = module.split(".");
		var base = pack.pop() + "_" + field;
		var vt = stages.vertexType, ft = stages.fragmentType;
		var vti = lower.haxeType(p.vertex.input).toComplexType();
		var paramsExpr:Expr = {expr: EObjectDecl(params), pos: pos};
		var pt = Context.toComplexType(Context.typeof(paramsExpr));
		var cls = macro class Shader extends helder.gfx.shader.Shader<$vti, $pt> {
			public final vertex:$vt;
			public final fragment:$ft;

			public function new(vertex:$vt, fragment:$ft) {
				super(${code(out.vertex)}, ${code(out.fragment)}, $layout, $uniforms, $textures, $writeVertices, $paramsExpr);
				this.vertex = vertex;
				this.fragment = fragment;
			}
		};
		// (the uniform(...)s' block: written from their values now, bound at its slot)
		if (out.uniforms != null) {
			var u = out.uniforms;
			var values:Expr = {expr: EObjectDecl([for (r in lower.uniformRefs) {field: r.field, expr: macro ${r.expr}.value}]), pos: pos};
			cls.fields = cls.fields.concat((macro class {
				final uniformValues = haxe.io.Bytes.alloc($v{u.size});

				override public function uniformBytes():Null<haxe.io.Bytes> {
					params.uniforms.write($values, uniformValues);
					return uniformValues;
				}
			}).fields);
			for (f in cls.fields)
				if (f.name == "new") switch f.kind {
					case FFun(fn): fn.expr = macro {${fn.expr}; uniformBinding = $v{u.binding};};
					case _:
				}
			// (bind: a GPU's target's, helder.gfx's Encoder)
			if (Context.definedValue("target.name") == "hxmc") cls.fields = cls.fields.concat((macro class {
				public function bind(encoder:helder.gfx.Encoder)
					encoder.setUniforms(uniformBinding, uniformBytes());
			}).fields);
		}
		var name = base + "_" + haxe.crypto.Md5.encode(new haxe.macro.Printer().printTypeDefinition(cls)).substr(0, 8);
		cls.name = name;
		cls.pack = pack;
		cls.pos = pos;
		cls.meta = [{name: ":noCompletion", pos: pos}];
		var exists = try Context.getType(pack.concat([name]).join(".")) != null catch (_:Dynamic) false;
		if (!exists) Context.defineType(cls, module);
		var tp:TypePath = {pack: pack, name: name};
		return macro new $tp(${stages.vertex}, ${stages.fragment});
	}

	static function components(n:Int):Array<Null<String>>
		return n == 1 ? [null] : [for (i in 0...n) "xyzw".charAt(i)];
}
#end
