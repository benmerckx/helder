package helder.scene.render;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#else
import haxe.io.Bytes;
import helder.gfx.Device;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.gltf.Gltf;
import helder.scene.gltf.GltfDoc;
import helder.scene.gltf.GltfScene;
#end

// A glTF model referenced where it is used: Model.of("models/hero.glb") is
// a macro that checks the file exists (an asset's path: helder.asset's
// AssetPath), reads its structure when compiling and types the result from
// it: model.nodes, model.meshes, model.materials and model.animations have
// a field per name in the file (its value the name, for World.find; a name
// that is no identifier made one: "Left Hand" is Left_Hand), so a typo is a
// compile error. The file goes with the build as every asset does
// (helder.asset's Bundle: the executable's data, the APK's or the app's
// assets/, beside the page), and Model.of reads it before anything runs
// (on the web os's browser.mjs fetches it before main):
//
//   var hero = Model.of("models/hero.glb");
//   var root = hero.instantiate(world, device);
//   var hand = root.find(hero.nodes.LeftHand);
//
// helder.asset's Asset.model(path) (or Model.of(path, Lazy)) is an Asset
// of the model instead, loaded in the background (big games, loading
// screens: `var hero = Asset.model(path).load();` in a coroutine), its
// names typed the same, reloaded under helder dev (its meshes and
// materials swapped in the instances: replace); Model.load(path) loads a
// path known only at run time (an Asset, names unknown, not bundled).
//
// Its GPU meshes are made by the first instantiate with a device and
// shared by every instance.
class Model<N, M, A, C> {
	#if !macro
	public var doc(default, null):GltfDoc;
	public final nodes:N;
	public final meshes:M;
	public final materials:A;
	public final animations:C;

	var scene:Null<GltfScene>;
	var device:Null<Device>;

	@:noCompletion public function new(bytes:Bytes, nodes:N, meshes:M, materials:A, animations:C) {
		doc = Gltf.parse(bytes);
		this.nodes = nodes;
		this.meshes = meshes;
		this.materials = materials;
		this.animations = animations;
	}

	// the model's scene as nodes of world (under parent, by default the root)
	public function instantiate(world:World, device:Device, ?parent:Node, ?made:Array<Node>):Node {
		if (scene == null || this.device != device) {
			scene = new GltfScene(doc, device);
			this.device = device;
		}
		return scene.instantiate(world, parent, null, made);
	}

	// an animation of the model by name (model.animations.Run), for an Animator
	public function clip(name:String):helder.scene.anim.AnimationClip {
		for (k in 0...doc.animations.length)
			if (doc.animations[k].name == name) return helder.scene.anim.AnimationClip.fromGltf(doc, k);
		throw 'Model: no animation $name';
	}

	// the model's GPU meshes released
	public function dispose() {
		if (scene != null) scene.dispose(device);
		scene = null;
	}

	// fresh (the file loaded again) in this model: its document, and its
	// meshes' primitives and materials in the meshes this model's instances
	// draw (GltfScene.handOver), so they show it from the next frame
	public function replace(fresh:Model<N, M, A, C>) {
		doc = fresh.doc;
		if (scene == null) return;
		var next = new GltfScene(doc, device);
		scene.handOver(next);
		scene = next;
	}

	// (Asset.model's and Model.of(path, Lazy)'s loader)
	@:noCompletion public static function asset<N, M, A, C>(key:String, file:Null<String>, nodes:N, meshes:M, materials:A,
			animations:C):helder.asset.Asset<Model<N, M, A, C>>
		return helder.asset.Assets.handle("model", key, _ -> new Model(helder.asset.Files.read(key, file), nodes, meshes, materials, animations), (old, fresh) -> {
			old.replace(fresh);
			old;
		});

	// a model whose path is known only at run time: loaded in the background
	// (in the browser fetched, relative to the page; natively read at once),
	// its names unknown when compiling (find nodes by name: model.doc)
	public static function load(path:String):helder.asset.Asset<Model<{}, {}, {}, {}>> {
		var asset = new helder.asset.Asset<Model<{}, {}, {}, {}>>(path);
		var f = helder.os.Fetch.start(path);
		helder.asset.Assets.track(() -> {
			if (f.poll()) {
				try
					asset.resolve(new Model(f.bytes, {}, {}, {}, {}))
				catch (e:String)
					asset.fail(e);
				return true;
			}
			if (f.failed) {
				asset.fail('Model: $path not found');
				return true;
			}
			return false;
		});
		return asset;
	}
	#end

	public static macro function of(path:String, ?mode:Expr):Expr {
		var lazy = switch mode {
			case null | {expr: EConst(CIdent("null"))}: false;
			case {expr: EConst(CIdent("Lazy"))}: true;
			case _: Context.error("Model.of: the mode is Lazy", mode.pos);
		}
		if (lazy) return helder.asset.AssetMacro.model(path);
		var file = helder.asset.AssetMacro.find(path, "model");
		helder.asset.AssetMacro.bundle(path, file, true);
		Context.registerModuleDependency(Context.getLocalModule(), file);
		var n = names(sys.io.File.getBytes(file), path, Context.currentPos());
		var read = macro helder.asset.Files.readNow(${helder.asset.AssetMacro.key(path, true)}, $v{helder.asset.AssetMacro.devPath(file)});
		return macro new helder.scene.render.Model($read, ${n.nodes}, ${n.meshes}, ${n.materials}, ${n.animations});
	}

	#if macro
	// a glTF file's names as objects of fields (nodes, meshes, materials,
	// animations), read with the runtime's file splitting (its reader checks
	// the rest when the model is made)
	public static function names(bytes:haxe.io.Bytes, path:String, pos:Position):{nodes:Expr, meshes:Expr, materials:Expr, animations:Expr} {
		var root:Dynamic = try haxe.Json.parse(helder.scene.gltf.GltfFile.split(bytes).json) catch (e:Dynamic) Context.error('Model.of: $path: $e', pos);
		function list(f:String):Array<Dynamic> {
			var v:Dynamic = Reflect.field(root, f);
			return Std.isOfType(v, Array) ? v : [];
		}
		function nameOf(o:Dynamic):String {
			var v:Dynamic = Reflect.field(o, "name");
			return Std.isOfType(v, String) ? v : "";
		}
		var buffers = list("buffers");
		var outside = [for (im in list("images")) if (Reflect.hasField(im, "uri") && !StringTools.startsWith(Reflect.field(im, "uri"), "data:")) im];
		if (buffers.length > 1 || outside.length > 0 || buffers.length == 1 && Reflect.hasField(buffers[0], "uri")
			&& !StringTools.startsWith(Reflect.field(buffers[0], "uri"), "data:"))
			Context.error('Model.of: $path: only self-contained files (one embedded buffer, images inside it) yet', pos);
		function names(list:Array<String>):Expr {
			var seen = new Map<String, Bool>(), fields:Array<ObjectField> = [];
			for (n in list) {
				if (n == null || n == "") continue;
				var id = ~/[^A-Za-z0-9_]/g.replace(n, "_");
				if (~/^[0-9]/.match(id)) id = "_" + id;
				if (seen.exists(id)) continue;
				seen.set(id, true);
				fields.push({field: id, expr: macro $v{n}});
			}
			return {expr: EObjectDecl(fields), pos: pos};
		}
		return {
			nodes: names([for (x in list("nodes")) nameOf(x)]),
			meshes: names([for (x in list("meshes")) nameOf(x)]),
			materials: names([for (x in list("materials")) nameOf(x)]),
			animations: names([for (x in list("animations")) nameOf(x)])
		};
	}
	#end
}
