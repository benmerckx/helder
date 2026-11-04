package helder.scene.render;

import helder.gfx.shader.Vec3;
import helder.scene.math.MathTools;
import helder.scene.math.Quat;
import helder.test.Test;

// InstancedMesh's flat data, on the CPU: a transform written as the
// matrix MathTools.compose makes (the instance buffer's columns), the
// colour in the columns' w, resize keeping what was written, count
// bounded by the capacity, nothing allocated by a frame's writes
// (natively and as wasm32-wasi). The renderer drawing one: the 3d lane's
// "instancedmesh" frame (tests/3d/Scenes.hx).
function tests() {
	describe("InstancedMesh", () -> {
		test("a transform is compose's matrix, the colour in its w", () -> {
			var set = new InstancedMesh(new Mesh(), 4);
			var q = Quat.axisAngle(new Vec3(0.6, 0.8, 0), 0.7);
			set.setTransform(2, 1, -2, 3, q.x, q.y, q.z, q.w, 1.5);
			set.setColor(2, 0.25, 0.5, 2);
			var m = MathTools.compose(new Vec3(1, -2, 3), q, new Vec3(1.5, 1.5, 1.5));
			for (c in 0...4) {
				var col = MathTools.col(m, c);
				approx(set.data.getFloat(2 * 64 + c * 16), col.x, 1e-5);
				approx(set.data.getFloat(2 * 64 + c * 16 + 4), col.y, 1e-5);
				approx(set.data.getFloat(2 * 64 + c * 16 + 8), col.z, 1e-5);
			}
			approx(set.data.getFloat(2 * 64 + 60), 1);
			approx(set.color(2, 0), 0.25);
			approx(set.color(2, 2), 2);
			approx(set.position(2, 1), -2);
			// (the others: at the origin, white)
			approx(set.data.getFloat(0), 1);
			approx(set.color(1, 1), 1);
		});
		test("setMatrix and setPosition keep the colour", () -> {
			var set = new InstancedMesh(new Mesh(), 2);
			set.setColor(0, 0.1, 0.2, 0.3);
			set.setMatrix(0, MathTools.compose(new Vec3(4, 5, 6), Quat.identity(), new Vec3(2, 2, 2)));
			set.setPosition(0, 7, 8, 9);
			approx(set.color(0, 2), 0.3, 1e-6);
			approx(set.data.getFloat(0), 2);
			approx(set.position(0, 0), 7);
		});
		test("resize keeps the instances, count within the capacity", () -> {
			var set = new InstancedMesh(new Mesh(), 2, 1, 4);
			set.setPosition(1, 3, 3, 3);
			set.setCustom(1, 3, 42);
			set.resize(8);
			equals(set.capacity, 8);
			approx(set.position(1, 0), 3);
			approx(set.getCustom(1, 3), 42);
			approx(set.color(7, 0), 1);
			set.count = 8;
			throws(() -> set.count = 9);
			set.resize(4);
			equals(set.count, 4);
			throws(() -> new InstancedMesh(new Mesh(), 1, 1, 3));
		});
		test("a frame's writes allocate nothing", () -> {
			var set = new InstancedMesh(new Mesh(), 1000, -1, 4);
			function frame(t:Float) {
				for (i in 0...set.count) {
					var a = t + i * 0.01, s = Math.sin(a * 0.5), c = Math.cos(a * 0.5);
					set.setTransform(i, i, a, -i, 0, s, 0, c, 1);
					set.setColor(i, s, c, 1);
					set.setCustom(i, 0, a);
				}
			}
			frame(0);
			var before = hxmc.GcStats.bytesAllocated();
			for (k in 1...20)
				frame(k);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
		});
	});
}
