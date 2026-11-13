package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.Buffer;
import helder.gfx.Device;
import helder.gfx.shader.Mat4;
import helder.scene.Node;
import helder.scene.math.Aabb;

// One mesh drawn many times in one instanced draw a primitive, its
// instances' data in flat arrays the program writes (no node, no object
// an instance): a swarm of asteroids, a fleet of ships, a forest. Each
// instance is a world transform (a position, a unit quaternion and a
// uniform scale, or any affine matrix: uneven scales too, the normals
// turned by its inverse transpose), a colour (rgb times the material's base colour, white by default)
// and, for a program's own shader, `custom` floats of its own (a second
// buffer, `custom` floats an instance, a multiple of 4). Attached to a
// node (InstancedMesh.attach), drawn by the Renderer while the node is
// shown (culled whole by bounds when given, never one by one; casting
// into Shadows' map), with the standard material (PbrInstancedShader: its layout's
// instance buffer, LAYOUT's second). Nothing is allocated a frame: a write
// marks the instances changed and the renderer uploads count of them
// before its pass (one writeBuffer, two with custom data).
//
//   var rocks = new InstancedMesh(Shapes.sphere(device, rock, 1), 100000);
//   InstancedMesh.attach(world.node("belt"), rocks);
//   // each frame:
//   for (i in 0...rocks.count) rocks.setTransform(i, x, y, z, qx, qy, qz, qw, s);
//
// The data's layout is the instance buffer's (`data`, 16 floats an
// instance, the matrix by columns, each of the first three columns' w the
// colour's channel less 1, the last column's w 1), so a program can also
// write it directly (data.setFloat, then changed()).
class InstancedMesh {
	public static final KIND = new StoreKind<InstancedMesh>("instanced");
	// bytes an instance in data
	public static inline var STRIDE = 64;

	public final mesh:Mesh;
	// the instances there is room for; grow with resize
	public var capacity(default, null):Int;
	// the instances drawn (0 to capacity)
	public var count(default, set):Int;
	// custom floats an instance (custom's stride: 4 * custom bytes)
	public final custom:Int;
	// the instance buffer's data: STRIDE bytes an instance
	public var data(default, null):Bytes;
	// the custom data (custom floats an instance; empty without)
	public var customData(default, null):Bytes;
	// the GPU's copies, made by the renderer when first drawn (Buffer.NONE before)
	public var buffer(default, null):Buffer = Buffer.NONE;
	public var customBuffer(default, null):Buffer = Buffer.NONE;
	// the instances' bounds in the world, when the program knows them
	// (empty: unknown): the renderer culls the whole set by them and
	// Shadows fits its map to them; without, the set is always drawn and
	// casts into a map fitted to the other casters
	public var bounds:Aabb = Aabb.empty();
	// whether it casts shadows (Shadows; its materials' castShadows too)
	public var castShadows = true;
	var dirty = true;
	var gpuCapacity = 0;
	var device:Null<Device> = null;

	public function new(mesh:Mesh, capacity:Int, count = -1, custom = 0) {
		if (custom % 4 != 0) throw "helder.scene: InstancedMesh's custom floats a multiple of 4";
		this.mesh = mesh;
		this.custom = custom;
		this.capacity = capacity;
		data = Bytes.alloc(capacity * STRIDE);
		customData = Bytes.alloc(capacity * custom * 4);
		for (i in 0...capacity)
			identity(i);
		this.count = count < 0 ? capacity : count;
	}

	public static inline function attach(node:Node, instances:InstancedMesh):InstancedMesh
		return node.world.store(KIND).set(node, instances);

	public static inline function of(node:Node):Null<InstancedMesh>
		return node.world.store(KIND).get(node);

	public static inline function detach(node:Node)
		node.world.store(KIND).remove(node);

	function set_count(n:Int):Int {
		if (n < 0 || n > capacity) throw 'helder.scene: InstancedMesh count $n outside 0...$capacity';
		dirty = true;
		return count = n;
	}

	// room for capacity instances (the data kept, new ones at the origin, white)
	public function resize(capacity:Int) {
		if (capacity == this.capacity) return;
		var d = Bytes.alloc(capacity * STRIDE), c = Bytes.alloc(capacity * custom * 4);
		var keep = capacity < this.capacity ? capacity : this.capacity;
		d.blit(0, data, 0, keep * STRIDE);
		c.blit(0, customData, 0, keep * custom * 4);
		data = d;
		customData = c;
		var old = this.capacity;
		this.capacity = capacity;
		for (i in old...capacity)
			identity(i);
		if (count > capacity) count = capacity;
		dirty = true;
	}

	// marks the data written directly as changed (the setters do)
	public inline function changed()
		dirty = true;

	// instance i at x, y, z, turned by the unit quaternion (qx, qy, qz, qw)
	// and scaled by s, its colour kept
	public function setTransform(i:Int, x:Float, y:Float, z:Float, qx:Float, qy:Float, qz:Float, qw:Float, s = 1.0) {
		var o = i * STRIDE, d = data;
		var xx = qx * qx, yy = qy * qy, zz = qz * qz, xy = qx * qy, xz = qx * qz, yz = qy * qz, wx = qw * qx, wy = qw * qy, wz = qw * qz;
		d.setFloat(o, (1 - 2 * (yy + zz)) * s);
		d.setFloat(o + 4, 2 * (xy + wz) * s);
		d.setFloat(o + 8, 2 * (xz - wy) * s);
		d.setFloat(o + 16, 2 * (xy - wz) * s);
		d.setFloat(o + 20, (1 - 2 * (xx + zz)) * s);
		d.setFloat(o + 24, 2 * (yz + wx) * s);
		d.setFloat(o + 32, 2 * (xz + wy) * s);
		d.setFloat(o + 36, 2 * (yz - wx) * s);
		d.setFloat(o + 40, (1 - 2 * (xx + yy)) * s);
		d.setFloat(o + 48, x);
		d.setFloat(o + 52, y);
		d.setFloat(o + 56, z);
		dirty = true;
	}

	// instance i's position only (its turn, scale and colour kept)
	public function setPosition(i:Int, x:Float, y:Float, z:Float) {
		var o = i * STRIDE;
		data.setFloat(o + 48, x);
		data.setFloat(o + 52, y);
		data.setFloat(o + 56, z);
		dirty = true;
	}

	// instance i's world matrix (affine: any scale, uneven too), its colour kept
	public function setMatrix(i:Int, m:Mat4) {
		var o = i * STRIDE, d = data;
		d.setFloat(o, m.c0.x);
		d.setFloat(o + 4, m.c0.y);
		d.setFloat(o + 8, m.c0.z);
		d.setFloat(o + 16, m.c1.x);
		d.setFloat(o + 20, m.c1.y);
		d.setFloat(o + 24, m.c1.z);
		d.setFloat(o + 32, m.c2.x);
		d.setFloat(o + 36, m.c2.y);
		d.setFloat(o + 40, m.c2.z);
		d.setFloat(o + 48, m.c3.x);
		d.setFloat(o + 52, m.c3.y);
		d.setFloat(o + 56, m.c3.z);
		dirty = true;
	}

	// instance i's colour (linear rgb, times the material's base colour)
	public function setColor(i:Int, r:Float, g:Float, b:Float) {
		var o = i * STRIDE;
		data.setFloat(o + 12, r - 1);
		data.setFloat(o + 28, g - 1);
		data.setFloat(o + 44, b - 1);
		dirty = true;
	}

	// instance i's position (axis 0, 1, 2: x, y, z), as written
	public inline function position(i:Int, axis:Int):Float
		return data.getFloat(i * STRIDE + 48 + axis * 4);

	// instance i's colour channel (0, 1, 2: r, g, b)
	public inline function color(i:Int, channel:Int):Float
		return data.getFloat(i * STRIDE + 12 + channel * 16) + 1;

	// instance i's custom float k (0 to custom - 1)
	public inline function setCustom(i:Int, k:Int, v:Float) {
		customData.setFloat((i * custom + k) * 4, v);
		dirty = true;
	}

	public inline function getCustom(i:Int, k:Int):Float
		return customData.getFloat((i * custom + k) * 4);

	// (instance i at the origin, unturned, white)
	function identity(i:Int) {
		var o = i * STRIDE;
		for (k in 0...16)
			data.setFloat(o + k * 4, k == 0 || k == 5 || k == 10 || k == 15 ? 1 : 0);
	}

	// the changed instances to the GPU (the renderer's, before its pass; a
	// program drawing them with its own pipeline calls it too): count of
	// them, the buffers made or grown to the capacity
	public function upload(device:Device) {
		if (!dirty || count == 0) return;
		if (gpuCapacity < capacity || this.device != device) {
			if (gpuCapacity > 0 && this.device != null) {
				this.device.destroyBuffer(buffer);
				if (custom > 0) this.device.destroyBuffer(customBuffer);
			}
			this.device = device;
			gpuCapacity = capacity;
			buffer = device.createBuffer({size: capacity * STRIDE, usage: Vertex});
			if (custom > 0) customBuffer = device.createBuffer({size: capacity * custom * 4, usage: Vertex});
		}
		device.writeBuffer(buffer, 0, data, 0, count * STRIDE);
		if (custom > 0) device.writeBuffer(customBuffer, 0, customData, 0, count * custom * 4);
		dirty = false;
	}

	// the GPU's buffers freed (the mesh is the caller's)
	public function dispose() {
		if (gpuCapacity > 0 && device != null) {
			device.destroyBuffer(buffer);
			if (custom > 0) device.destroyBuffer(customBuffer);
		}
		gpuCapacity = 0;
		buffer = customBuffer = Buffer.NONE;
		dirty = true;
	}
}
