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
// ui's pass), picking for the pointer events over it: at each pointer's
// press (the node hit owns the pointer until it lifts: its moves, its
// release, its cancel, its click), and as a hovering mouse or pen moves
// (enter, leave). Its pointers are the game's (ownsPointer: false). Drawn
// again when a scene node of the markup changes, or each frame while
// animate is set.
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

	// (per pointer, 0 the mouse: the node its press picked, where, how far;
	// the one its release left, for its click)
	final picked:Array<SceneGraphNode> = [for (_ in 0...helder.ui.Ui.POINTERS) SceneGraphNode.NONE];
	final lifted:Array<SceneGraphNode> = [for (_ in 0...helder.ui.Ui.POINTERS) SceneGraphNode.NONE];
	final points:Array<Vec3> = [for (_ in 0...helder.ui.Ui.POINTERS) new Vec3(0, 0, 0)];
	final distances:Array<Float> = [for (_ in 0...helder.ui.Ui.POINTERS) 0.0];
	// (the one event refilled for each dispatch)
	final event = new SceneEvent();
	// the controls moving its camera (OrbitControls), stepped before each frame it draws
	@:allow(helder.scene.view) final controls:Array<OrbitControls> = [];
	var steppedAt = -1.0;
	// its scene nodes' taps (onTap): a recogniser of its own, in the arena with the controls'
	final tap = new helder.ui.gesture.Tap();

	public function new(world:World, ?camera:Camera) {
		super("scene");
		this.world = world;
		this.camera = camera;
		root = SceneRenderer.root(world);
		boxes.push(this);
		SceneRenderer.changed = redraw;
		// (picked at a press only: the node hit owns the pointer until it lifts;
		// a hovering mouse or pen picks as it moves, for enter and leave)
		onPointerDown = e -> {
			var id = pointerOf(e), hit = pick(e);
			picked[id] = hit == null ? SceneGraphNode.NONE : hit.node;
			if (hit != null) {
				points[id] = hit.point;
				distances[id] = hit.distance;
			}
			send(id, DOWN, e);
		};
		onPointerMove = e -> {
			var id = pointerOf(e);
			if (!picked[id].isNone) return send(id, MOVE, e);
			if (e.pointerType == Touch || ui != null && ui.captureOf(id) != null) return;
			var hit = pick(e);
			var now = hit == null ? SceneGraphNode.NONE : hit.node;
			if (now != under) {
				if (!under.isNone && under.valid) dispatch(event.set(under, new Vec3(0, 0, 0), 0, e, null, id), LEAVE);
				if (hit != null) dispatch(event.set(hit.node, hit.point, hit.distance, e, null, id), ENTER);
				under = now;
			}
			if (hit != null) dispatch(event.set(hit.node, hit.point, hit.distance, e, null, id), MOVE);
		};
		onPointerUp = e -> {
			var id = pointerOf(e);
			send(id, UP, e);
			lifted[id] = picked[id];
			picked[id] = SceneGraphNode.NONE;
		};
		onPointerCancel = e -> {
			var id = pointerOf(e);
			send(id, CANCEL, e);
			picked[id] = lifted[id] = SceneGraphNode.NONE;
		};
		onClick = e -> {
			var id = pointerOf(e);
			send(id, CLICK, e, lifted[id]);
			lifted[id] = SceneGraphNode.NONE;
		};
		addGesture(tap).onGesture = g -> {
			var id = g.pointerAt(0);
			if (id >= 0 && id < helder.ui.Ui.POINTERS) send(id, TAP, null, lifted[id], g);
		};
		onPointerLeave = e -> {
			if (!under.isNone && under.valid) dispatch(event.set(under, new Vec3(0, 0, 0), 0, e, null, 0), LEAVE);
			under = SceneGraphNode.NONE;
		};
	}

	// (the listeners' kinds: SceneRenderer.LISTENERS's order)
	static inline var DOWN = 0;
	static inline var UP = 1;
	static inline var MOVE = 2;
	static inline var ENTER = 3;
	static inline var LEAVE = 4;
	static inline var CLICK = 5;
	static inline var CANCEL = 6;
	static inline var TAP = 7;

	static inline function pointerOf(e:Event):Int
		return e.pointerId >= 0 && e.pointerId < helder.ui.Ui.POINTERS ? e.pointerId : 0;

	// (to the node pointer id's press picked, or n)
	function send(id:Int, kind:Int, e:Null<Event>, ?n:SceneGraphNode, ?g:helder.ui.gesture.Gesture) {
		var node = n ?? picked[id];
		if (node.isNone || !node.valid) return;
		dispatch(event.set(node, points[id], distances[id], e, g, id), kind);
	}

	// a world drawn under the ui: its pointers are the game's (Pointer.owner)
	override public function ownsPointer():Bool
		return false;

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

	// the node under a pointer event (window points)
	function pick(e:Event):Null<{node:SceneGraphNode, distance:Float, point:Vec3}> {
		var r = windowBounds();
		if (r.width <= 0 || r.height <= 0) return null;
		var lx = localX(e.x, e.y), ly = localY(e.x, e.y);
		var ray = view().ray(lx / r.width * 2 - 1, 1 - ly / r.height * 2, r.width / r.height);
		return Pick.ray(world, ray.origin, ray.dir);
	}

	// se's node's listener of that kind called, then its ancestors'
	static function dispatch(se:SceneEvent, kind:Int) {
		var n = se.node;
		while (!n.isNone && !se.stopped) {
			var s = SceneRenderer.of(n);
			if (s != null && s.handlers != null) {
				var h = s.handlers[kind];
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
		// (its controls' glides, by the time since the last frame drawn)
		var now = helder.ui.Ui.now(), dt = steppedAt < 0 ? 0 : Math.min(0.1, now - steppedAt);
		steppedAt = now;
		for (c in controls)
			if (c.update(dt) && ui != null) ui.requestFrame();
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
