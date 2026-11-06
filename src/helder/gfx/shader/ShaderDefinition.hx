package helder.gfx.shader;

import helder.definition.Kernel;
import helder.gfx.shader.Ir;

// What a shader's adapter does for the handler: a stage's function lowered
// to the IR with everything it calls (its name in the code when it has none
// of its own: vs, fs), and the locals renamed away from the globals at the
// end (Names.unhide). Lower is Haxe's; helder.typescript's lowering
// TypeScript's.
interface ShaderAdapter extends Adapter {
	function lowerStage(f:KFunction, name:String):SFunction;
	function finish():Void;
	// (a slot object's variant: the stages' third parameter the object,
	// m.options.<name> its options' values, m.<slot>(s, p) its slots'
	// functions; tests of constants folded, loops over them unrolled)
	function useSlots(use:SlotsUse):Void;
}

// shader({vertex, fragment}) (DESIGN.md 3), the handler both languages run:
// the stages' interface checked (a vertex of attributes in, the varyings
// out with exactly one position(...), the same varyings into the fragment
// stage, a colour out), the fields of each stage's object of parameters
// (the adapter flattens it: SFunction.fields) made uniform blocks (std140)
// and textures at slots in order of appearance, the stages' text printed in
// the build's languages, and what the CPU's writers store where. The
// adapter turns the output into the generated value (ShaderMacro: Haxe's
// expression of a Shader).
class ShaderDefinition implements Definition<ShaderAdapter, ShaderOutput> {
	public static inline var MAX_SLOTS = 16;

	public final name = "shader";

	public function new() {}

	public function generate(arg:KNode, a:ShaderAdapter):ShaderOutput {
		var r = new KObjectReader(arg, a, "the argument", ["vertex", "fragment"]);
		var vk = r.func("vertex"), fk = r.func("fragment");
		if (vk == null) a.error(fk == null ? "a shader needs a vertex and a fragment function" : "a shader with a fragment function needs a vertex function", arg.pos);
		if (fk == null) a.error("a shader with a vertex function needs a fragment function", arg.pos);
		return output(a, vk, fk, arg.pos, false);
	}

	// a slot object's variant (Slots): its stages with its slots' functions
	// and its options' values inlined, what they never read of the optional
	// fields (attributes, varyings, parameters) dropped
	public function variant(def:SlotsDef, options:Null<KNode>, a:ShaderAdapter, pos:KPos):ShaderOutput {
		a.useSlots({options: def.values(options, a), slots: def.slots});
		return output(a, def.vertex, def.fragment, pos, true);
	}

	function output(a:ShaderAdapter, vk:KFunction, fk:KFunction, pos:KPos, variant:Bool):ShaderOutput {
		var p = program(a, vk, fk, variant);
		var android = StringTools.startsWith(a.defined("hxmc.target") ?? "", "android");
		function stage(e:SEntry):StageCode
			return {
				code: [
					for (l in languages(a, pos))
						{
							language: l,
							text: switch l {
								// (Android: structs through make_ functions, Glsl.makers)
								case "glsl": new Glsl(android).stage(p, e);
								case "wgsl": new Wgsl().stage(p, e);
								case "msl": new Msl().stage(p, e);
								case _: new Hlsl().stage(p, e);
							}
						}
				],
				// (GL binds them by their GLSL names, WebGPU makes its bind group layout of them)
				bindings: [for (u in e.uniforms) {name: u.struct.name + "_block", slot: u.binding, uniform: true, size: u.size}].concat([
					for (t in e.textures)
						{name: "tex_" + t.slot, slot: t.slot, uniform: false, size: 0}
				])
			};
		var attributes:Array<{field:String, components:Int, offset:Int}> = [], off = 0;
		for (f in p.vertex.input.fields) {
			var n = switch f.type {
				case TVec(n): n;
				case _: 1;
			}
			attributes.push({field: f.field, components: n, offset: off});
			off += 4 * n;
		}
		// the parameters by name (a writer per uniform block, a slot per
		// texture), the vertex stage's first; a name both stages take is one
		// resource
		var params:Array<ShaderParam> = [];
		for (s in [{e: p.vertex, k: vk}, {e: p.fragment, k: fk}])
			for (i in 0...s.e.resources.length) {
				var name = s.e.fn.fields[i], r = s.e.resources[i];
				var other = Lambda.find(params, x -> x.name == name);
				if (other == null) params.push({name: name, resource: r}) else if (!same(other.resource, r))
					a.error('the parameter $name is two resources (each stage\'s $name the same uniform block or texture)', s.k.pos);
			}
		return {
			program: p,
			vertex: stage(p.vertex),
			fragment: stage(p.fragment),
			attributes: attributes,
			stride: off,
			params: params
		};
	}

	static function same(a:SResource, b:SResource):Bool
		return switch [a, b] {
			case [RUniform(x), RUniform(y)]: x == y;
			case [RTexture(x), RTexture(y)]: x == y;
			case _: false;
		}

	function program(a:ShaderAdapter, vk:KFunction, fk:KFunction, variant:Bool):SProgram {
		var vf = a.lowerStage(vk, vk.name ?? "vs"), ff = a.lowerStage(fk, fk.name ?? "fs");
		var vpos = vk.pos, fpos = fk.pos;
		if (variant) Prune.program(vf, ff);
		if (vf.params.length == 0) a.error("the vertex function takes no vertex", vpos);
		var input = switch vf.params[0].type {
			case TStruct(s): s;
			case t: a.error('the vertex function\'s vertex is a ${Names.typeName(t)}, not a struct', vpos);
		}
		for (f in input.fields)
			switch f.type {
				case TFloat | TVec(_):
				case t: a.error('the vertex function: ${input.path}.${f.field} is a ${Names.typeName(t)}: vertex attributes are Float, Vec2, Vec3 or Vec4', vpos);
			}
		var varyings = switch vf.ret {
			case TStruct(s): s;
			case t: a.error('the vertex function returns a ${Names.typeName(t)}, not a struct of varyings', vpos);
		}
		var positions = 0;
		for (f in varyings.fields)
			switch f.type {
				case TVec(4) if (f.position): positions++;
				case t if (f.position): a.error('the vertex function: the position(...) ${varyings.path}.${f.field} is a ${Names.typeName(t)}, not a Vec4', vpos);
				case TFloat | TVec(_):
				case t: a.error('the vertex function: the varying ${varyings.path}.${f.field} is a ${Names.typeName(t)}: varyings are Float, Vec2, Vec3 or Vec4', vpos);
			}
		if (positions != 1)
			a.error('the vertex function: exactly one field of ${varyings.path} is the clip-space position, marked by position(...) where it is built (it has $positions)',
				vpos);
		if (ff.params.length == 0 || !Names.same(ff.params[0].type, vf.ret))
			a.error('stage interface mismatch: the fragment function takes ' + (ff.params.length == 0 ? "nothing" : Names.typeName(ff.params[0].type))
				+ ', but the vertex function returns ${Names.typeName(vf.ret)}', fpos);
		if (!Names.same(ff.ret, TVec(4))) a.error('the fragment function returns a ${Names.typeName(ff.ret)}, not a Vec4 (the colour)', fpos);
		// resources: the further parameters, uniform blocks (a slot per struct)
		// and textures (a slot per name), slots in order of appearance
		var uniforms:Array<SUniform> = [], textures:Array<STexture> = [];
		function resources(f:SFunction, k:KFunction):Array<SResource>
			return [
				for (i in 1...f.params.length) {
					var p = f.params[i], name = f.fields[i - 1] ?? p.name;
					var slot = uniforms.length + textures.length;
					switch p.type {
						case TStruct(s):
							var u = Lambda.find(uniforms, u -> u.struct == s);
							if (u == null) {
								u = std140(a, s, slot, k.pos);
								uniforms.push(u);
							}
							RUniform(u);
						case TTexture:
							var t = Lambda.find(textures, t -> t.name == p.name);
							if (t == null) {
								t = new STexture(p.name, slot);
								textures.push(t);
							}
							RTexture(t);
						case t: a.error('the parameter $name is a ${Names.typeName(t)}, not a uniform block (a struct) or a Texture2D', k.pos);
					}
				}
			];
		var vr = resources(vf, vk), fr = resources(ff, fk);
		if (uniforms.length + textures.length > MAX_SLOTS) a.error('more than $MAX_SLOTS uniform blocks and textures', vpos);
		a.finish();
		return new SProgram(entry(Vertex, vf, input, vr), entry(Fragment, ff, varyings, fr), uniforms, textures);
	}

	// the stage's function and what it reaches, in declaration order
	static function entry(stage:SStage, f:SFunction, input:SStruct, resources:Array<SResource>):SEntry {
		var fs:Array<SFunction> = [], ss:Array<SStruct> = [];
		function ty(t:SType)
			switch t {
				case TStruct(s) if (!ss.contains(s)):
					for (f in s.fields)
						ty(f.type);
					ss.push(s);
				case _:
			}
		function visit(f:SFunction) {
			if (fs.contains(f)) return;
			for (p in f.params)
				ty(p.type);
			ty(f.ret);
			function e(x:SExpr) {
				ty(x.t);
				switch x.e {
					case EField(a, _) | ESwizzle(a, _) | EColumn(a, _) | EUnop(_, a) | EConvert(a): e(a);
					case EBinop(_, a, b):
						e(a);
						e(b);
					case ECond(c, a, b):
						e(c);
						e(a);
						e(b);
					case ENew(args) | EBuiltin(_, args): for (a in args) e(a);
					case ECall(g, args):
						for (a in args)
							e(a);
						visit(g);
					case EFloat(_) | EInt(_) | EBool(_) | ELocal(_):
				}
			}
			function s(st:SStmt)
				switch st {
					case SDecl(v, init):
						ty(v.type);
						if (init != null) e(init);
					case SAssign(_, _, x) | SEval(x): e(x);
					case SIf(c, a, b):
						e(c);
						for (x in a)
							s(x);
						if (b != null) for (x in b)
							s(x);
					case SWhile(c, body):
						e(c);
						for (x in body)
							s(x);
					case SReturn(x): if (x != null) e(x);
					case SBreak | SContinue:
				}
			for (st in f.body)
				s(st);
			fs.push(f);
		}
		visit(f);
		for (r in resources)
			switch r {
				case RUniform(u): ty(TStruct(u.struct));
				case RTexture(_):
			}
		return new SEntry(stage, f, input, resources, ss, fs);
	}

	// std140 (and WGSL's uniform layout, the same for these types)
	static function std140(a:Adapter, s:SStruct, binding:Int, pos:KPos):SUniform {
		var off = 0, offsets = [];
		for (f in s.fields) {
			var size = 0, align = 0;
			switch f.type {
				case TFloat | TInt:
					size = align = 4;
				case TVec(n):
					size = 4 * n;
					align = n == 2 ? 8 : 16;
				case TMat4:
					size = 64;
					align = 16;
				case t: a.error('the uniform ${s.path}.${f.field} is a ${Names.typeName(t)}: uniforms are Float, Int, vectors and Mat4', pos);
			}
			off = (off + align - 1) & ~(align - 1);
			offsets.push(off);
			off += size;
		}
		return new SUniform(s, binding, offsets, (off + 15) & ~15);
	}

	// the build's shader languages: -D helder.gfx.shaders=glsl,wgsl,msl,hlsl (or
	// all); else the target's (hxmc: -D hxmc.target or the host: GLSL on Linux,
	// MSL on macOS, HLSL on Windows, GLSL and WGSL on wasm32-wasi), and all
	// four on other targets (Eval: the tests)
	public static function languages(a:Adapter, pos:KPos):Array<String> {
		var all = ["glsl", "wgsl", "msl", "hlsl"];
		var d = a.defined("helder.gfx.shaders");
		if (d != null) {
			if (d == "all" || d == "1") return all;
			var ls = d.split(",");
			for (l in ls)
				if (!all.contains(l)) a.error('-D helder.gfx.shaders: no shader language $l (glsl, wgsl, msl, hlsl, all)', pos);
			return ls;
		}
		if (a.defined("target.name") != "hxmc") return all;
		var t = a.defined("hxmc.target");
		if (t == null) t = switch Sys.systemName() {
			case "Mac": "macos";
			case "Windows": "windows";
			case _: "linux";
		}
		return t == "wasm32-wasi" ? ["glsl", "wgsl"] : StringTools.startsWith(t, "macos")
			|| StringTools.startsWith(t, "ios") ? ["msl"] : StringTools.startsWith(t, "windows") ? ["hlsl"] : ["glsl"];
	}
}

// What the handler makes of a shader: the program, each stage's text and
// bindings, the vertex buffer's attributes (each a field of the vertex,
// Float32 components packed in order) and the parameters (the fields of
// the stages' objects of parameters: a uniform block's writer each, Ir's
// SUniform has the std140 offsets, or a texture's slot).
typedef ShaderOutput = {
	program:SProgram,
	vertex:StageCode,
	fragment:StageCode,
	attributes:Array<{field:String, components:Int, offset:Int}>,
	stride:Int,
	params:Array<ShaderParam>
}

typedef ShaderParam = {
	name:String,
	resource:SResource
}

// what a slot object's variant lowers its stages with (ShaderAdapter.useSlots)
typedef SlotsUse = {
	options:Map<String, KValue>,
	slots:Map<String, KNode>
}

// A slot object's definition (Slots: slots({vertex, fragment, options,
// <slot>: ...})): its stages, which take the object as their third
// parameter, its options' defaults (literals) and its slots (functions,
// module-level ones by name); with(...) the same with some slots replaced.
class SlotsDef {
	public final vertex:KFunction;
	public final fragment:KFunction;
	public final options:Map<String, KNode>;
	public final optionOrder:Array<String>;
	public final slots:Map<String, KNode>;
	public final slotOrder:Array<String>;

	function new(vertex, fragment, options, optionOrder, slots, slotOrder) {
		this.vertex = vertex;
		this.fragment = fragment;
		this.options = options;
		this.optionOrder = optionOrder;
		this.slots = slots;
		this.slotOrder = slotOrder;
	}

	public static function read(arg:KNode, a:Adapter):SlotsDef {
		var fields = switch arg.value {
			case KObject(fs): fs;
			case _: a.error('a slot object is an object literal ({vertex, fragment, options, <slot>: ...}), not ${arg.describe()}', arg.pos);
		}
		var vertex:Null<KFunction> = null, fragment:Null<KFunction> = null;
		var options = new Map<String, KNode>(), optionOrder = [], slots = new Map<String, KNode>(), slotOrder = [];
		for (f in fields)
			switch [f.name, f.node.value] {
				case ["vertex", KFunction(k)]: vertex = k;
				case ["fragment", KFunction(k)]: fragment = k;
				case ["vertex" | "fragment", _]: a.error('${f.name} is a function, not ${f.node.describe()}', f.node.pos);
				case ["options", KObject(os)]:
					for (o in os) {
						switch o.node.value {
							case KBool(_) | KInt(_) | KFloat(_):
							case _: a.error('the option ${o.name} is a boolean or a number, not ${o.node.describe()}', o.node.pos);
						}
						options.set(o.name, o.node);
						optionOrder.push(o.name);
					}
				case ["options", _]: a.error('options is an object of booleans and numbers, not ${f.node.describe()}', f.node.pos);
				case [_, KFunction(_) | KRef(_)]:
					slots.set(f.name, f.node);
					slotOrder.push(f.name);
				case [_, _]: a.error('the slot ${f.name} is a function, not ${f.node.describe()}', f.node.pos);
			}
		if (vertex == null || fragment == null) a.error("a slot object has a vertex and a fragment function", arg.pos);
		return new SlotsDef(vertex, fragment, options, optionOrder, slots, slotOrder);
	}

	// the same with some slots' functions replaced (an object of them)
	public function with(overrides:KNode, a:Adapter):SlotsDef {
		var fields = switch overrides.value {
			case KObject(fs): fs;
			case _: a.error('with takes an object of slots\' functions, not ${overrides.describe()}', overrides.pos);
		}
		var next = new Map<String, KNode>();
		for (k => v in slots)
			next.set(k, v);
		for (f in fields) {
			if (!slots.exists(f.name)) a.error('the slot object has no slot ${f.name} (it has ' + slotOrder.join(", ") + ")", f.node.pos);
			switch f.node.value {
				case KFunction(_) | KRef(_):
				case _: a.error('the slot ${f.name} is a function, not ${f.node.describe()}', f.node.pos);
			}
			next.set(f.name, f.node);
		}
		return new SlotsDef(vertex, fragment, options, optionOrder, next, slotOrder);
	}

	// the options' values: the defaults, those given replaced
	public function values(given:Null<KNode>, a:Adapter):Map<String, KValue> {
		var out = new Map<String, KValue>();
		for (k => v in options)
			out.set(k, v.value);
		if (given == null) return out;
		var fields = switch given.value {
			case KObject(fs): fs;
			case _: a.error('a variant\'s options are an object literal, not ${given.describe()}', given.pos);
		}
		for (f in fields) {
			var d = options.get(f.name);
			if (d == null) a.error('the slot object has no option ${f.name} (it has ' + optionOrder.join(", ") + ")", f.node.pos);
			switch [d.value, f.node.value] {
				case [KBool(_), KBool(_)] | [KInt(_) | KFloat(_), KInt(_) | KFloat(_)]:
				case _: a.error('the option ${f.name} is ${d.describe()}, not ${f.node.describe()}', f.node.pos);
			}
			out.set(f.name, f.node.value);
		}
		return out;
	}
}

typedef StageCode = {
	code:Array<{language:String, text:String}>,
	bindings:Array<{name:String, slot:Int, uniform:Bool, size:Int}>
}
