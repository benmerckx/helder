import hxmc.gfx.*;
import hxmc.gfx.shader.Vec3;
import hxmc.scene.*;
import hxmc.scene.gltf.*;
import hxmc.scene.render.*;

// packages/3d's test scenes (RenderTest natively, SceneWebTest in the
// browser), each a frame against packages/3d/test/<name>.png:
//   gltf   the sample glTF scene (examples/sample.glb) from its camera,
//          lit by the renderer's sun and sky
class Scenes {
	public static final NAMES = ["gltf"];

	public static function make(name:String, device:Device):Encoder->Void {
		return switch name {
			case "gltf":
				var renderer = new Renderer(device);
				var scene = new Scene();
				scene.add(GltfScene.build(Gltf.parse(Asset.embed("sample.glb")), device));
				var camera = scene.firstCamera();
				enc -> renderer.draw(enc, scene, camera);
			case n: throw 'Scenes: no scene $n';
		}
	}
}
