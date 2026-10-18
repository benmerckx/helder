package hxmc.scene.render;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import hxmc.gfx.Device;
import hxmc.gfx.shader.Vec3;
import hxmc.gfx.shader.Vec4;
import hxmc.scene.Camera;
import hxmc.scene.Node;
import hxmc.scene.World;
import hxmc.scene.math.Aabb;
import hxmc.scene.math.Quat;

// A model packed at build time (hxmc.scene.gltf.Pack): read without JSON,
// its vertex data handed to the GPU as it is, instantiated into worlds as
// GltfScene's are:
//
//   var level = PackedModel.read(Asset.embed("level.hxm3d"), device);
//   level.instantiate(world);
class PackedModel {
	public final meshes:Array<Mesh> = [];
	public final materials:Array<Material> = [];
	final cameras:Array<{perspective:Bool, size:Float, near:Float, far:Float}> = [];
	final nodes:Array<{name:String, parent:Int, mesh:Int, camera:Int, trs:Array<Float>}> = [];
	var sceneName = "";

	function new() {}

	public static function read(bytes:Bytes, device:Device):PackedModel {
		var m = new PackedModel();
		var i = new BytesInput(bytes);
		i.bigEndian = false;
		function str():String
			return i.readString(i.readUInt16());
		if (i.readInt32() != 0x334D5848) throw "PackedModel: not a packed model";
		if (i.readInt32() != 1) throw "PackedModel: another version";
		for (_ in 0...i.readInt32()) {
			var name = str();
			var f = [for (_ in 0...9) i.readFloat()];
			m.materials.push(new Material(name, new Vec4(f[0], f[1], f[2], f[3]), f[4], f[5], new Vec3(f[6], f[7], f[8]), i.readByte() == 1));
		}
		var datas:Array<VertexData> = [];
		for (_ in 0...i.readInt32()) {
			var flags = i.readByte(), count = i.readInt32();
			var vertices = i.read(i.readInt32()), indices = i.read(i.readInt32());
			var b = [for (_ in 0...6) i.readFloat()];
			datas.push(new VertexData(vertices, indices, flags & 2 != 0, count, false, new Aabb(new Vec3(b[0], b[1], b[2]), new Vec3(b[3], b[4], b[5]))));
		}
		var fallback:Null<Material> = null;
		for (_ in 0...i.readInt32()) {
			str();
			var mesh = new Mesh();
			for (_ in 0...i.readInt32()) {
				var material = i.readInt32(), data = i.readInt32();
				var mat = if (material >= 0) m.materials[material] else {
					if (fallback == null) fallback = new Material("default");
					fallback;
				}
				mesh.addData(device, datas[data], mat);
			}
			m.meshes.push(mesh);
		}
		for (_ in 0...i.readInt32()) {
			var perspective = i.readByte() == 1;
			m.cameras.push({perspective: perspective, size: i.readFloat(), near: i.readFloat(), far: i.readFloat()});
		}
		for (_ in 0...i.readInt32()) {
			var name = str(), parent = i.readInt32(), mesh = i.readInt32(), camera = i.readInt32();
			m.nodes.push({name: name, parent: parent, mesh: mesh, camera: camera, trs: [for (_ in 0...10) i.readFloat()]});
		}
		m.sceneName = str();
		return m;
	}

	// the model's nodes in world, under one new node (under parent)
	public function instantiate(world:World, ?parent:Node):Node {
		var top = world.node(sceneName, parent);
		var made:Array<Node> = [];
		for (k in 0...nodes.length) {
			var g = nodes[k], t = g.trs;
			var n = world.node(g.name, g.parent >= 0 ? made[g.parent] : top);
			n.position = new Vec3(t[0], t[1], t[2]);
			n.rotation = new Quat(t[3], t[4], t[5], t[6]);
			n.scale = new Vec3(t[7], t[8], t[9]);
			if (g.mesh >= 0) MeshRenderer.attach(n, meshes[g.mesh]);
			if (g.camera >= 0) {
				var c = cameras[g.camera];
				Camera.attach(n, c.perspective ? Camera.perspective(c.size, c.near, c.far) : Camera.orthographic(c.size, c.near, c.far));
			}
			made.push(n);
		}
		return top;
	}
}
