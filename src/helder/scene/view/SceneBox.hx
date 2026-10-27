package helder.scene.view;

import helder.gfx.Texture;
import helder.gfx.shader.Vec3;
import helder.scene.Camera;
import helder.scene.Node as SceneGraphNode;
import helder.scene.World;
import helder.scene.math.MathTools;
import helder.scene.render.Pick;
import helder.scene.render.Renderer;
import helder.scene.view.SceneRenderer.SceneNode;
import helder.ui.Event;

// <Scene>'s box: a ui node drawing its world into a texture of its size
// (an offscreen scene Renderer, on the ui's GPU device: drawn before the
// ui's pass), picking for the pointer events over it. Drawn again when a
// scene node of the markup changes, or each frame while animate is set.
class SceneBox extends helder.ui.Node {
	public final world:World;
	public final root:SceneNode;
	public var camera:Null<Camera>;
	// a frame each tick (an animation outside the markup's signals)
	public var animate = false;
	@:allow(helder.scene.view.SceneTags) var overlays:Array<{node:SceneNode, ui:helder.ui.Node, x:Float, y:Float}> = [];
	var renderer:Null<Renderer>;
	var device:Null<helder.gfx.Device>;
	var color:Null<Texture>;
	var depth:Null<Texture>;
	var tw = 0;
	var th = 0;
	var fallback:Null<Camera>;
	var under = SceneGraphNode.NONE;
	// (its texture's id for ui's renderer: negative, one per box)
	final id = -(++ids);

	static var ids = 0;
	static final boxes:Array<SceneBox> = [];

	public function new(world:World, ?camera:Camera) {
		super("scene");
		this.world = world;
		this.camera = camera;
		root = SceneRenderer.root(world);
		boxes.push(this);
		SceneRenderer.changed = redraw;
		onPointerDown = e -> pick(e, "onPointerDown");
		onPointerUp = e -> pick(e, "onPointerUp");
		onClick = e -> pick(e, "onClick");
		onPointerMove = e -> {
			var hit = pick(e, "onPointerMove");
			var now = hit == null ? SceneGraphNode.NONE : hit.node;
			if (now != under) {
				if (!under.isNone && under.valid) dispatch(new SceneEvent(under, new Vec3(0, 0, 0), 0, e), "onPointerLeave");
				if (hit != null) dispatch(new SceneEvent(hit.node, hit.point, hit.distance, e), "onPointerEnter");
				under = now;
			}
		};
		onPointerLeave = e -> {
			if (!under.isNone && under.valid) dispatch(new SceneEvent(under, new Vec3(0, 0, 0), 0, e), "onPointerLeave");
			under = SceneGraphNode.NONE;
		};
	}

	// (every box drawn again: a scene node changed)
	static function redraw()
		for (b in boxes)
			if (b.ui != null) b.ui.requestFrame();

	public function dispose() {
		boxes.remove(this);
		if (device != null) {
			if (color != null) device.destroyTexture(color);
			if (depth != null) device.destroyTexture(depth);
			renderer.dispose();
		}
		color = depth = null;
		renderer = null;
	}

	// the camera drawn with: camera, the world's first, else a default
	public function view():Camera {
		if (camera != null) return camera;
		var c = Camera.first(world);
		if (c != null) return c;
		if (fallback == null) {
			var eye = world.node("camera");
			fallback = Camera.attach(eye, Camera.perspective(0.9, 0.1, 100));
			eye.position = new Vec3(0, 2, 6);
			eye.lookAt(new Vec3(0, 0, 0));
		}
		return fallback;
	}

	// the node under a pointer event (window points), its listener (name) called, then its ancestors'
	function pick(e:Event, name:String):Null<{node:SceneGraphNode, distance:Float, point:Vec3}> {
		var r = windowBounds();
		if (r.width <= 0 || r.height <= 0) return null;
		var lx = localX(e.x, e.y), ly = localY(e.x, e.y);
		var ray = view().ray(lx / r.width * 2 - 1, 1 - ly / r.height * 2, r.width / r.height);
		var hit = Pick.ray(world, ray.origin, ray.dir);
		if (hit != null) dispatch(new SceneEvent(hit.node, hit.point, hit.distance, e), name);
		return hit;
	}

	static function dispatch(se:SceneEvent, name:String) {
		var n = se.node;
		while (!n.isNone && !se.stopped) {
			var s = SceneRenderer.of(n);
			if (s != null) {
				var h:Null<SceneEvent->Void> = s.props.get(name);
				if (h != null) {
					@:privateAccess se.current = n;
					h(se);
				}
			}
			n = n.parent;
		}
	}

	override public function hasContent():Bool
		return true;

	override public function paintContent(canvas:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		// (on the GPU only: a canvas recording, a test's, draws nothing)
		var r = Std.downcast(canvas, helder.ui.draw.Renderer);
		if (r == null) return;
		if (animate && ui != null) ui.requestFrame();
		var pw = Std.int(Math.max(1, Math.round(width * r.scale))), ph = Std.int(Math.max(1, Math.round(height * r.scale)));
		if (renderer == null) {
			device = r.device;
			renderer = new Renderer(r.device, true);
			if (SceneRenderer.device == null) SceneRenderer.device = r.device;
		}
		if (pw != tw || ph != th) {
			if (color != null) device.destroyTexture(color);
			if (depth != null) device.destroyTexture(depth);
			color = device.createTexture({width: pw, height: ph, renderTarget: true});
			depth = device.createTexture({width: pw, height: ph, format: Depth32F});
			tw = pw;
			th = ph;
		}
		var cam = view(), sr = renderer, c = color, d = depth;
		r.beforePass(enc -> sr.drawInto(enc, world, cam, c, d, pw, ph));
		r.gpuTexture(color, id, x, y, width, height);
		place(cam, width, height);
	}

	// the <Ui>s at their nodes' places (from this frame's view: laid out by the next)
	function place(cam:Camera, width:Float, height:Float) {
		if (overlays.length == 0) return;
		var vp = cam.viewProjection(width / Math.max(1, height));
		for (o in overlays) {
			var p = MathTools.transformPoint(vp, o.node.node.worldPosition());
			var x = (p.x + 1) / 2 * width - o.ui.rect().width / 2, y = (1 - p.y) / 2 * height - o.ui.rect().height / 2;
			if (x != o.x || y != o.y) {
				o.ui.style.left = o.x = x;
				o.ui.style.top = o.y = y;
			}
			var shown:helder.ui.Visibility = p.z >= -1 && p.z <= 1 ? Visible : Hidden;
			if (o.ui.style.visibility != shown) o.ui.style.visibility = shown;
		}
	}
}
