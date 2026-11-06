package helder.scene.render;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import helder.definition.HaxeAdapter;
import helder.definition.Kernel;
import helder.gfx.shader.Ir;
import helder.gfx.shader.ShaderDefinition;
import helder.gfx.shader.SlotsMacro;
#end

// A material's own shader (DESIGN.md 3 in src/helder/compiler): pbr (the
// standard material, PbrShader) with some of its slots replaced, compiled
// at build time into the variants the renderer draws with (plain, normal
// mapped, skinned, instanced, instanced and normal mapped), set on a
// Material (material.shader) as the shader its primitives are drawn with:
//
//   final Glow = MaterialShader.material(pbr.with({
//     emissive: function(s, p:{glow:GlowParams}):Vec3 return p.glow.color.xyz * (0.5 + 0.5 * sin(p.glow.time.x)),
//     color: function(s, p:{}):Vec3 return s.baseColor.xyz * 1.5
//   }));
//   material.shader = Glow;
//   material.uniforms = ["glow" => bytes];   // its own block: Glow.params.glow.write(...)
//
// A slot's parameters are the stage's of the same names (the material's
// block and textures, the frame's); the others are uniform blocks of the
// material's own, bound from material.uniforms by their parameter's name
// (params: the plain variant's writers, typed; the class is the material's
// own, made beside its module).
class MaterialShader {
	public final plain:AnyShader;
	public final normalMapped:AnyShader;
	public final skinned:AnyShader;
	public final instanced:AnyShader;
	public final instancedNormalMapped:AnyShader;
	// the blocks of the material's own: its parameter's name, its slot, in each variant (in the order above)
	public final blocks:Array<{name:String, bindings:Array<Int>}>;

	public function new(plain, normalMapped, skinned, instanced, instancedNormalMapped, blocks) {
		this.plain = plain;
		this.normalMapped = normalMapped;
		this.skinned = skinned;
		this.instanced = instanced;
		this.instancedNormalMapped = instancedNormalMapped;
		this.blocks = blocks;
	}

	// the material's variants of a slot object made from pbr (pbr.with({...}))
	public static macro function material(def:Expr):Expr {
		var pos = Context.currentPos();
		var a = new HaxeAdapter("material");
		var typed = Context.typeExpr(def);
		var kinds:Array<Array<String>> = [[], ["normalMap"], ["skinned"], ["instanced"], ["instanced", "normalMap"]];
		var standard = ["PbrFrame", "PbrObject", "PbrMaterial", "PbrSkinInfo"];
		var textures = [
			"baseColorTexture", "metallicRoughnessTexture", "emissiveTexture", "occlusionTexture", "shadowMap", "shadowMapFar", "environmentMap", "normalTexture",
			"jointMatrices"
		];
		var shaders = [], blocks = new Map<String, Array<Int>>(), order = [];
		for (k in 0...kinds.length) {
			var lower = new helder.gfx.shader.Lower();
			var r = SlotsMacro.resolve(typed, lower, a);
			var given = new KNode(KObject([for (o in kinds[k]) {name: o, node: new KNode(KBool(true), pos)}]), pos);
			var out = new ShaderDefinition().variant(r.def, given, lower, pos);
			for (p in out.params)
				switch p.resource {
					case RUniform(u) if (!standard.contains(u.struct.name)):
						if (!blocks.exists(p.name)) {
							blocks.set(p.name, [for (_ in 0...kinds.length) -1]);
							order.push(p.name);
						}
						blocks.get(p.name)[k] = u.binding;
					case RTexture(t) if (!textures.contains(p.name)):
						Context.error('material: the texture ${p.name} is not one the renderer binds (a slot\'s textures are the material\'s: ' + textures.join(", ") + ")", pos);
					case _:
				}
			shaders.push(SlotsMacro.build(r, r.def.values(given, a), out, lower));
		}
		var bs = [for (n in order) macro {name: $v{n}, bindings: $v{blocks.get(n)}}];
		// (its own class: params, the plain variant's, typed)
		var pt = Context.toComplexType(Context.typeof(macro ${shaders[0]}.params));
		var module = Context.getLocalModule(), field = Context.getLocalMethod() ?? "material";
		var pack = module.split(".");
		var base = pack.pop() + "_" + field + "_material";
		var cls = macro class Material extends helder.scene.render.MaterialShader {
			public final params:$pt;

			public function new(params:$pt, plain, normalMapped, skinned, instanced, instancedNormalMapped, blocks) {
				super(plain, normalMapped, skinned, instanced, instancedNormalMapped, blocks);
				this.params = params;
			}
		};
		var name = base + "_" + haxe.crypto.Md5.encode(new haxe.macro.Printer().printTypeDefinition(cls)).substr(0, 8);
		cls.name = name;
		cls.pack = pack;
		cls.pos = pos;
		cls.meta = [{name: ":noCompletion", pos: pos}];
		var exists = try Context.getType(pack.concat([name]).join(".")) != null catch (_:Dynamic) false;
		if (!exists) Context.defineType(cls, module);
		var tp:TypePath = {pack: pack, name: name};
		var any = [for (i in 1...shaders.length) macro(cast ${shaders[i]} : helder.scene.render.MaterialShader.AnyShader)];
		var made:Expr = {
			expr: ENew(tp, [macro plain.params, macro(cast plain : helder.scene.render.MaterialShader.AnyShader)].concat(any).concat([macro [$a{bs}]])),
			pos: pos
		};
		return macro {
			var plain = ${shaders[0]};
			$made;
		};
	}
}

typedef AnyShader = helder.gfx.shader.Shader<Dynamic, Dynamic>;
