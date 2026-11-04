import helder.gfx.Device;
import helder.gfx.shader.Vec3;
import helder.scene.*;
import helder.scene.math.Aabb;
import helder.scene.render.*;

using helder.scene.math.MathTools;

// The showcase's scene, the example's (GltfShowcase) and the reference
// frames' (Shots): Khronos' sample models (fetched by fetch.mjs into
// models/, each one .glb) lit by prefiltered environments
// (environments/*.png, baked by envbake.py from Poly Haven's CC0 panoramas),
// in HDR through ACES, the camera fitted to the model's bounds.
class Showcase {
	// the models: name, its credit (each one's <name>.json has the whole of it)
	public static final MODELS:Array<{name:String, credit:String}> = [
		{name: "DamagedHelmet", credit: "CC BY 4.0 ctxwing, after theblueturtle_ (CC BY-NC 4.0)"},
		{name: "FlightHelmet", credit: "CC0 Gary Hsu"},
		{name: "SciFiHelmet", credit: "CC0 Michael Pavlovic, Norbert Nopper"},
		{name: "MetalRoughSpheres", credit: "CC BY 4.0 Ed Mackey"},
		{name: "TextureTransformTest", credit: "CC0 Microsoft"},
		{name: "EmissiveStrengthTest", credit: "CC BY 4.0 Ed Mackey"},
		{name: "ClearCoatTest", credit: "CC BY 4.0 Ed Mackey"},
		{name: "TransmissionTest", credit: "CC0 Adobe"}
	];
	// the environments: file, label, intensity (envbake.py's scale)
	public static final ENVIRONMENTS:Array<{file:String, label:String, intensity:Float}> = [
		{file: "studio_small_09", label: "Studio", intensity: 6.055},
		{file: "venice_sunset", label: "Sunset", intensity: 2.214},
		{file: "kloofendal_48d_partly_cloudy_puresky", label: "Sky", intensity: 5.131}
	];

	public final world = new World("showcase");
	public final camera:Camera;
	public final eye:Node;
	public var environments:Array<Environment> = [];
	// the model shown, its root and bounds
	public var root = Node.NONE;
	public var bounds = Aabb.empty();
	// the file's first camera, if it has one
	public var fileCamera:Null<Camera>;

	public function new() {
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.8, 0.01, 100));
	}

	// the renderer's features: normal maps, the environments (the first
	// shown), bloom and ACES; envs: each environment's atlas bytes
	public function setup(r:Renderer, envs:Array<haxe.io.Bytes>) {
		r.clearColor = new helder.gfx.Color(0.05, 0.05, 0.06, 1);
		r.use(new NormalMaps(r.device));
		environments = [];
		for (k in 0...envs.length) {
			var e = Environment.prefiltered(r.device, "image/png", envs[k], 6);
			if (e == null) continue;
			e.intensity = ENVIRONMENTS[k].intensity;
			r.use(e);
			environments.push(e);
		}
		r.sunColor = new Vec3(0, 0, 0);
		r.exposure = 1;
		environment(r, 0);
	}

	// the environment k lights and is drawn behind the scene
	public function environment(r:Renderer, k:Int) {
		for (i in 0...environments.length)
			environments[i].background = i == k;
		if (k < environments.length) @:privateAccess r.environment = environments[k];
	}

	// model in place of the one shown: its bounds measured
	public function show(model:Model<{}, {}, {}, {}>, device:Device) {
		if (!root.isNone) root.dispose();
		root = model.instantiate(world, device);
		bounds = Aabb.empty();
		var meshes = world.store(MeshRenderer.KIND);
		for (k in 0...meshes.length) {
			var n = meshes.nodeAt(k);
			if (world.inTree(n)) bounds = bounds.union(meshes.valueAt(k).bounds.transform(n.worldMatrix()));
		}
		fileCamera = null;
		var cameras = world.store(Camera.KIND);
		for (k in 0...cameras.length)
			if (cameras.nodeAt(k) != eye && world.inTree(cameras.nodeAt(k)) && fileCamera == null) fileCamera = cameras.valueAt(k);
	}

	// the model's centre and the distance that fits its bounds in the view
	public function centre():Vec3
		return bounds.isEmpty() ? new Vec3(0, 0, 0) : (bounds.min + bounds.max) * 0.5;

	// (the bounds' box seen from the front, along -z: its width and height
	// within the view at aspect, its depth's half in front)
	public function fitDistance(aspect = 1.0):Float {
		if (bounds.isEmpty()) return 3;
		var d = bounds.max - bounds.min, t = Math.tan(0.4);
		return Math.max(d.x * 0.5 / (t * aspect), d.y * 0.5 / t) * 1.1 + d.z * 0.5;
	}

	// the camera at yaw, pitch and the fitted distance about the centre
	public function look(yaw:Float, pitch:Float, aspect = 1.0) {
		var c = centre(), d = fitDistance(aspect);
		eye.position = c + new Vec3(Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), Math.cos(yaw) * Math.cos(pitch)) * d;
		eye.lookAt(c);
	}
}
