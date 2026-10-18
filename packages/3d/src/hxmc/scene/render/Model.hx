package hxmc.scene.render;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#else
import haxe.io.Bytes;
import hxmc.gfx.Device;
import hxmc.scene.Node;
import hxmc.scene.World;
import hxmc.scene.gltf.Gltf;
import hxmc.scene.gltf.GltfDoc;
import hxmc.scene.gltf.GltfScene;
#end

// A glTF model referenced where it is used: Model.of("models/hero.glb") is
// a macro that checks the file exists, reads its structure when compiling
// and types the result from it: model.nodes, model.meshes and
// model.materials have a field per name in the file (its value the name,
// for World.find; a name that is no identifier made one: "Left Hand" is
// Left_Hand), so a typo is a compile error. The file is registered with the
// build (today: built into the program; the asset packing and the
// browser's prefetch before main are docs/plans/3d.md's next steps), so
// the model is ready at once:
//
//   var hero = Model.of("models/hero.glb");
//   var root = hero.instantiate(world, device);
//   var hand = root.find(hero.nodes.LeftHand);
//
// Its GPU meshes are made by the first instantiate with a device and
// shared by every instance.
class Model<N, M, A> {
	#if !macro
	public final doc:GltfDoc;
	public final nodes:N;
	public final meshes:M;
	public final materials:A;

	var scene:Null<GltfScene>;
	var device:Null<Device>;

	@:noCompletion public function new(bytes:Bytes, nodes:N, meshes:M, materials:A) {
		doc = Gltf.parse(bytes);
		this.nodes = nodes;
		this.meshes = meshes;
		this.materials = materials;
	}

	// the model's scene as nodes of world (under parent, by default the root)
	public function instantiate(world:World, device:Device, ?parent:Node):Node {
		if (scene == null || this.device != device) {
			scene = new GltfScene(doc, device);
			this.device = device;
		}
		return scene.instantiate(world, parent);
	}

	// the model's GPU meshes released
	public function dispose() {
		if (scene != null) scene.dispose(device);
		scene = null;
	}
	#end

	public static macro function of(path:String):Expr {
		var pos = Context.currentPos();
		var file = try Context.resolvePath(path) catch (_:Dynamic) path;
		if (!sys.FileSystem.exists(file)) Context.error('Model.of: $path not found', pos);
		Context.registerModuleDependency(Context.getLocalModule(), file);
		var bytes = sys.io.File.getBytes(file);
		// (the structure read with the runtime's file splitting; the runtime's
		// reader checks the rest when the model is made)
		var root:Dynamic = try haxe.Json.parse(hxmc.scene.gltf.GltfFile.split(bytes).json) catch (e:Dynamic) Context.error('Model.of: $path: $e', pos);
		function list(f:String):Array<Dynamic> {
			var v:Dynamic = Reflect.field(root, f);
			return Std.isOfType(v, Array) ? v : [];
		}
		function nameOf(o:Dynamic):String {
			var v:Dynamic = Reflect.field(o, "name");
			return Std.isOfType(v, String) ? v : "";
		}
		var buffers = list("buffers");
		if (buffers.length > 1 || list("images").length > 0 || buffers.length == 1 && Reflect.hasField(buffers[0], "uri")
			&& !StringTools.startsWith(Reflect.field(buffers[0], "uri"), "data:"))
			Context.error('Model.of: $path: only self-contained files (one embedded buffer, no images) yet', pos);
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
		var n = names([for (x in list("nodes")) nameOf(x)]), m = names([for (x in list("meshes")) nameOf(x)]), a = names([for (x in list("materials")) nameOf(x)]);
		var data = haxe.crypto.Base64.encode(bytes);
		return macro new hxmc.scene.render.Model(haxe.crypto.Base64.decode($v{data}), $n, $m, $a);
	}
}
