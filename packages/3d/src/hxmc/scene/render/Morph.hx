package hxmc.scene.render;

import haxe.io.Bytes;
import hxmc.gfx.Buffer;
import hxmc.gfx.Device;
import hxmc.scene.Node;
import hxmc.scene.StoreKind;
import hxmc.scene.World;

// Morph targets (glTF's): a component of the node whose mesh they bend,
// its MorphWeights (set by a program or played by an Animator's weights
// tracks) blending each target's displacements of positions and normals
// into the node's own copy of the mesh's vertices, on the CPU, when the
// weights change (the renderer asks before it draws: Morph.update), then
// written to the GPU. Its mesh is the node's own (instances bend apart).
class Morph {
	public static final KIND = new StoreKind<Morph>("morph");

	final device:Device;
	final prims:Array<MorphPrimitive>;
	final applied:Array<Float>;

	// (made by the first morph: what the renderer calls before drawing a
	// world, so that a program without morphs links none of this)
	@:allow(hxmc.scene.render.Renderer) static var updateWorld:Null<World->Void>;

	public function new(device:Device, targets:Int, prims:Array<MorphPrimitive>) {
		this.device = device;
		this.prims = prims;
		applied = [for (_ in 0...targets) Math.NaN];
		if (updateWorld == null) updateWorld = updateAll;
	}

	public static inline function attach(node:Node, morph:Morph):Morph
		return node.world.store(KIND).set(node, morph);

	public static inline function of(node:Node):Null<Morph>
		return node.world.store(KIND).get(node);

	static function updateAll(world:World) {
		var s = world.store(KIND);
		for (k in 0...s.length) {
			var w = hxmc.scene.anim.MorphWeights.of(s.nodeAt(k));
			if (w != null) s.valueAt(k).update(w.weights);
		}
	}

	// the vertices blended again where the weights changed since
	public function update(weights:Array<Float>) {
		var same = true;
		for (t in 0...weights.length)
			if (weights[t] != applied[t]) same = false;
		if (same) return;
		for (t in 0...weights.length)
			applied[t] = weights[t];
		for (p in prims) {
			var out = p.out, n = p.count;
			out.blit(0, p.base, 0, p.base.length);
			for (t in 0...weights.length) {
				var w = weights[t];
				if (w == 0) continue;
				var dp = p.positions[t], dn = p.normals[t];
				for (v in 0...n) {
					var o = v * p.stride;
					for (c in 0...3) {
						if (dp != null) out.setFloat(o + 4 * c, out.getFloat(o + 4 * c) + w * dp[3 * v + c]);
						if (dn != null) out.setFloat(o + 12 + 4 * c, out.getFloat(o + 12 + 4 * c) + w * dn[3 * v + c]);
					}
				}
			}
			device.writeBuffer(p.buffer, 0, out, 0, out.length);
		}
	}
}

// a primitive's part of a morph: its own vertex buffer, the vertices at
// rest (the renderer's layout: stride bytes a vertex, position then
// normal), each target's displacements (null: none of that kind)
class MorphPrimitive {
	public final buffer:Buffer;
	public final base:Bytes;
	public final out:Bytes;
	public final stride:Int;
	public final count:Int;
	public final positions:Array<Null<Array<Float>>>;
	public final normals:Array<Null<Array<Float>>>;

	public function new(buffer:Buffer, base:Bytes, stride:Int, positions:Array<Null<Array<Float>>>, normals:Array<Null<Array<Float>>>) {
		this.buffer = buffer;
		this.base = base;
		this.stride = stride;
		count = Std.int(base.length / stride);
		out = Bytes.alloc(base.length);
		this.positions = positions;
		this.normals = normals;
	}
}
