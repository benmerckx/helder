import hxmc.gfx.*;
import hxmc.gfx.shader.Vec3;
import hxmc.scene.*;
import hxmc.scene.gltf.*;
import hxmc.scene.render.*;

// packages/3d's test scenes (RenderTest natively, SceneWebTest in the
// browser), each a frame against packages/3d/test/<name>.png:
//   gltf   the sample glTF scene (examples/sample.glb) from its camera,
//          lit by the renderer's sun and sky
//   shadows the same with a shadow map (Shadows, 512x512)
//   orbits the Orbits example (shapes made in code on a scene graph, a
//          directional Light) at TIME seconds
class Scenes {
	public static final NAMES = ["gltf", "orbits", "shadows"];
	public static inline var TIME = 2.0;

	public static function make(name:String, device:Device):Encoder->Void {
		return switch name {
			case "gltf" | "shadows":
				var renderer = new Renderer(device);
				if (name == "shadows") renderer.use(new Shadows(device, 512));
				var world = new World();
				var model = Model.of("sample.glb");
				model.instantiate(world, device);
				// (typed from the file when compiling)
				if (world.root.find(model.nodes.camera).isNone) throw "Scenes: no camera node";
				var camera = Camera.first(world);
				enc -> renderer.draw(enc, world, camera);
			case "orbits":
				var orbits = new Orbits(device);
				orbits.at(TIME);
				enc -> orbits.draw(enc);
			case n: throw 'Scenes: no scene $n';
		}
	}
}
