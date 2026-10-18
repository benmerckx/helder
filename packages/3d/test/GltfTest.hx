import haxe.io.Bytes;
import hxmc.gfx.shader.Vec3;
import hxmc.scene.*;
import hxmc.scene.gltf.*;
import hxmc.scene.math.*;

using hxmc.scene.math.MathTools;

// packages/3d's step 2 (make 3d-check: on Eval and natively): the glTF
// reader on the sample scene (SampleModel.hx; examples/sample.glb checked
// in, the same bytes as the generator's on Eval), both forms (.glb and
// .gltf with a data: URI) read alike, its accessors against the generated
// values, the hierarchy as scene nodes, and files it must reject.
class GltfTest {
	static var checks = 0;
	static var failed = 0;

	static function check(what:String, ok:Bool) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('GltfTest: FAIL: $what');
		}
	}

	static function near(a:Float, b:Float, eps = 1e-6):Bool
		return Math.abs(a - b) <= eps;

	static function nearV(a:Vec3, b:Vec3, eps = 1e-6):Bool
		return near(a.x, b.x, eps) && near(a.y, b.y, eps) && near(a.z, b.z, eps);

	static function main() {
		var file = Sys.args()[0] != null ? Sys.args()[0] : "packages/3d/examples/sample.glb";
		var glb = sys.io.File.getBytes(file);
		var made = SampleModel.glb();
		#if eval
		// (the generator's floats come from libm: the bytes are compared where the file was made)
		check("sample.glb is the generator's (bless: run SampleModel)", made.compare(glb) == 0);
		#end
		check("isGlb", Gltf.isGlb(glb) && !Gltf.isGlb(SampleModel.gltf()));
		var doc = Gltf.parse(glb), text = Gltf.parse(SampleModel.gltf());
		for (d in [doc, text])
			sample(d);
		check("both forms: the same buffer", doc.buffers[0].compare(text.buffers[0]) == 0);
		nodes(doc);
		rejects(glb);
		Sys.println('GltfTest: $checks checks, ' + (failed == 0 ? "ok" : '$failed FAILED'));
		if (failed > 0) Sys.exit(1);
	}

	static function sample(doc:GltfDoc) {
		check("generator", doc.generator == "hxmc packages/3d/test/SampleModel.hx");
		check("counts", doc.meshes.length == 5 && doc.materials.length == 4 && doc.nodes.length == 7 && doc.scenes.length == 1 && doc.cameras.length == 1);
		check("names", [for (n in doc.nodes) n.name].join(",") == "ground,pedestal,ball,orbit,moon,satellite,camera");
		check("roots", doc.roots().join(",") == "0,1,3,5,6");
		check("children", doc.nodes[1].children.join(",") == "2" && doc.nodes[3].children.join(",") == "4");
		var ground = doc.meshes[0].primitives[0], cube = doc.meshes[1].primitives[0], sphere = doc.meshes[2].primitives[0];
		check("8-bit indices", doc.indices(ground.indices).join(",") == "0,1,2,0,2,3");
		check("ground positions", same(doc.floats(ground.position), SampleModel.groundPositions));
		check("interleaved positions (byteStride)", same(doc.floats(cube.position), SampleModel.cubePositions));
		var n = doc.floats(cube.normal);
		check("interleaved normals", n.length == 72 && n[0] == 0 && n[1] == 0 && n[2] == 1 && n[69] == 0 && n[70] == -1);
		check("16-bit indices", doc.indices(cube.indices).length == 36 && doc.indices(cube.indices)[35] == 23);
		check("32-bit indices", doc.indices(sphere.indices).join(",") == SampleModel.sphereIndices.join(","));
		check("sphere positions", same(doc.floats(sphere.position), SampleModel.spherePositions));
		var uv = doc.floats(sphere.texcoord);
		check("normalized 16-bit UVs", near(uv[0], 0) && near(uv[2], 1 / 24, 1e-4) && near(uv[uv.length - 1], 1) && near(uv[uv.length - 2], 1));
		var a = doc.accessors[cube.position];
		check("min and max", a.min != null && a.min.join(",") == "-0.5,-0.5,-0.5" && a.max.join(",") == "0.5,0.5,0.5");
		var gold = doc.materials[2];
		check("material", gold.name == "gold" && near(gold.baseColor.y, 0.77) && gold.metallic == 1 && near(gold.roughness, 0.3)
			&& gold.alphaMode == "OPAQUE" && !gold.doubleSided && gold.baseColorTexture == -1);
		check("primitive's material", doc.meshes[3].primitives[0].material == 3 && sphere.material == 2);
		check("absent attributes", cube.texcoord == -1 && cube.tangent == -1 && ground.color == -1);
		var cam = doc.cameras[0];
		check("camera", cam.perspective && near(cam.yfov, 0.7) && near(cam.znear, 0.1) && cam.zfar == 100);
		check("matrix node", doc.nodes[3].matrix != null && doc.nodes[3].matrix.length == 16);
	}

	static function same(a:Array<Float>, b:Array<Float>):Bool {
		if (a.length != b.length) return false;
		for (i in 0...a.length)
			if (!near(a[i], b[i])) return false;
		return true;
	}

	static function nodes(doc:GltfDoc) {
		var meshes = [];
		var root = GltfNodes.build(doc, 0, k -> {
			meshes.push(k);
			"mesh " + k;
		});
		check("root", root.name == "sample" && root.children.length == 5);
		var ball = root.find("ball"), pedestal = root.find("pedestal");
		check("hierarchy", ball.parent == pedestal && root.find("moon").parent == root.find("orbit"));
		check("meshes made once each", meshes.length == 5 && ball.mesh == "mesh 2" && root.find("satellite").mesh == "mesh 4");
		check("ball's world", nearV(ball.worldPosition(), new Vec3(0, 1.6, 0), 1e-6));
		check("ball's scale", near(ball.world().c0.x * ball.world().c0.x + ball.world().c0.z * ball.world().c0.z, 0.36, 1e-5));
		// (the orbit's matrix: a turn of 0.9 about y and a lift of 0.2)
		var moon = root.find("moon").worldPosition();
		check("matrix node: decomposed", nearV(moon, new Vec3(2.3 * Math.cos(0.9), 0.65, -2.3 * Math.sin(0.9)), 1e-5));
		var cam = root.find("camera").camera;
		check("camera node", cam != null && near(cam.fovY, 0.7));
		// (the camera looks at the pedestal's middle, as made)
		var c = cam.viewProjection(4 / 3).transformPoint(new Vec3(0, 0.7, 0));
		check("camera looks at the scene", near(c.x, 0, 1e-5) && near(c.y, 0, 1e-5));
	}

	static function rejects(glb:Bytes) {
		function fails(what:String, f:Void->Void) {
			var msg = try {
				f();
				null;
			} catch (e:String) e;
			check('rejects $what' + (msg != null ? "" : " (accepted)"), msg != null && StringTools.startsWith(msg, "glTF: "));
		}
		fails("a truncated .glb", () -> Gltf.parse(glb.sub(0, 100)));
		var json = SampleModel.gltf().toString();
		function edited(from:String, to:String):Bytes {
			if (json.indexOf(from) < 0) throw 'GltfTest: no $from';
			return Bytes.ofString(StringTools.replace(json, from, to));
		}
		fails("version 1", () -> Gltf.parse(edited('"version":"2.0"', '"version":"1.0"')));
		fails("a node out of range", () -> Gltf.parse(edited('"children":[2]', '"children":[9]')));
		fails("a cycle", () -> Gltf.parse(edited('"children":[4]', '"children":[3]')));
		fails("two parents", () -> Gltf.parse(edited('"children":[4]', '"children":[4,2]')));
		fails("an accessor out of its view", () -> Gltf.parse(edited('"count":36', '"count":3600')));
		fails("a material out of range", () -> Gltf.parse(edited('"material":3}', '"material":30}')));
		fails("a missing buffer file", () -> Gltf.parse(edited('"uri":"data:', '"uri":"x.bin","x":"')));
		var resolved = false;
		var doc = Gltf.parse(edited('"uri":"data:application/octet-stream;base64,', '"uri":"sample.bin","x":"'), uri -> {
			resolved = uri == "sample.bin";
			return Gltf.parse(glb).buffers[0];
		});
		check("a buffer from resolve", resolved && doc.meshes.length == 5);
	}
}
