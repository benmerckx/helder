package helder.scene.view;

import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.Quat;
import helder.scene.render.Light;
import helder.scene.render.Material;
import helder.scene.render.MeshRenderer;
import helder.scene.render.Shapes;

// helder.view's renderer for helder.scene: markup makes nodes of a World,
// and a property bound to a signal sets the node's value when the signal
// changes (no reconciliation, no re-render). Its markup is a <Scene>'s
// children (SceneTags: a box in ui's layout), or mounted into a world's root:
//
//   Render.render(<node name="spinner" position={pos} rotation={turn}>
//     <mesh shape="box" color={new Vec4(1, 0.5, 0.1, 1)}/>
//   </node>, SceneRenderer.root(world));
//
// Elements: node (position, rotation, scale: Vec3, Quat, Vec3; name,
// visible), mesh (a node with a shape made in code: shape box | sphere |
// plane, size, color, metallic, roughness; SceneRenderer.device must be
// set), light (kind directional | point, color, intensity, range), camera
// (fov, near, far); listeners (onClick, onPointerDown, onPointerUp,
// onPointerMove, onPointerCancel, onPointerEnter, onPointerLeave, onTap: a
// SceneEvent) on any, called by a <Scene>'s picking (at a pointer's press:
// the node hit then owns it until it lifts), the nearest node hit and then
// its ancestors.
// Other names are an error (@:elements). Texts and markers are hidden nodes.
// <Ui> (SceneTags) goes back to ui inside a scene. A prototype of the
// reactive layer for scenes (see the README's roadmap): properties go through
// setProperty by name here; typed constructors per tag come next.
@:elements("node", "mesh", "light", "camera")
@:events(helder.scene.view.SceneEvents)
class SceneRenderer implements helder.view.Renders<SceneNode> {
	// the device meshes are made on (a <Scene> sets it when first drawn: the meshes made before it, then)
	public static var device(default, set):Null<helder.gfx.Device>;
	// the world elements are made in: a <Scene>'s (WORLD, provided to its children), else root's
	public static var world:Null<World>;
	public static final WORLD = new helder.view.graph.Context<Null<World>>(null, true);
	// (the markup's nodes by their scene nodes' ids: picking's; the meshes waiting for a device)
	static final nodes = new Map<Int, SceneNode>();
	static final pending:Array<SceneNode> = [];

	static function set_device(d:Null<helder.gfx.Device>) {
		device = d;
		if (d != null) {
			for (n in pending)
				if (n.node.valid) n.remesh();
			pending.resize(0);
		}
		return d;
	}

	// the markup's node of a scene node (null: none, or not made by markup)
	public static function of(n:Node):Null<SceneNode>
		return nodes.get(n.id());

	// the node of world's root, to render into
	public static function root(w:World):SceneNode {
		world = w;
		return new SceneNode(w.root, "root");
	}

	public static function createElement(tag:String):SceneNode {
		var w = (helder.view.graph.Graph.getOwner() == null ? null : helder.view.graph.Graph.use(WORLD)) ?? world;
		if (w == null) throw "SceneRenderer: no world (a <Scene>'s children, or rendered into SceneRenderer.root(world))";
		var n = new SceneNode(w.node(tag), tag);
		n.node.detach();
		nodes.set(n.node.id(), n);
		return n;
	}

	public static function createText(text:String):SceneNode
		return createMarker("#text");

	public static function createMarker(name:String):SceneNode {
		var n = createElement(name);
		n.node.visible = false;
		return n;
	}

	public static function setText(node:SceneNode, text:String) {}

	public static function holdsText(el:SceneNode):Bool
		return false;

	public static function setProperty(el:SceneNode, name:String, value:Dynamic) {
		var n = el.node;
		changed();
		switch name {
			case "name": n.name = value;
			case "position": n.position = (value : Vec3);
			case "rotation": n.rotation = (value : Quat);
			case "scale": n.scale = (value : Vec3);
			case "visible": n.visible = value;
			case _:
				// (a component's property: the component made again from them)
				el.props.set(name, value);
				switch el.tag {
					case "mesh": el.remesh();
					case "light": el.relight();
					case "camera": el.recamera();
					case _:
				}
		}
	}

	public static function setStyle(el:SceneNode, value:Dynamic) {}

	// (a listener kept by its kind, found by index at each event: SceneBox's dispatch)
	public static function listen(el:SceneNode, name:String, handler:Dynamic) {
		var k = LISTENERS.indexOf(name);
		if (k < 0) throw 'SceneRenderer: no event $name (${LISTENERS.join(", ")})';
		if (el.handlers == null) el.handlers = [for (_ in LISTENERS) null];
		el.handlers[k] = handler;
	}

	// the listeners a scene node takes, SceneNode.handlers' order (SceneBox's kinds)
	public static final LISTENERS = ["onPointerDown", "onPointerUp", "onPointerMove", "onPointerEnter", "onPointerLeave", "onClick", "onPointerCancel", "onTap"];

	public static function insert(parent:SceneNode, node:SceneNode, before:Null<SceneNode>) {
		parent.node.add(node.node);
		nodes.set(node.node.id(), node);
		changed();
		if (before != null) {
			// (the scene graph appends: move the ones from before on after it)
			var after = false, move = [];
			for (c in parent.node.children()) {
				if (c == before.node) after = true;
				if (after && c != node.node) move.push(c);
			}
			for (c in move)
				parent.node.add(c);
		}
		node.parent = parent;
	}

	public static function remove(parent:SceneNode, node:SceneNode) {
		node.node.detach();
		node.parent = null;
		nodes.remove(node.node.id());
		changed();
	}

	// (a node's property or place changed: the <Scene>s drawn again)
	public static var changed:Void->Void = () -> {};

	public static function parentOf(node:SceneNode):Null<SceneNode>
		return node.parent;

	public static function arrange(parent:SceneNode, nodes:Array<SceneNode>, before:SceneNode)
		for (n in nodes)
			insert(parent, n, before);

	public static function isNode(v:Dynamic):Bool
		return Std.isOfType(v, SceneNode);
}

// a node of the scene as markup sees it: the World's node, its tag, the
// properties that make its components
@:rendered(helder.scene.view.SceneRenderer)
class SceneNode {
	public final node:Node;
	public final tag:String;
	public var parent:Null<SceneNode>;
	public final props = new Map<String, Dynamic>();
	// its listeners by kind (SceneRenderer.LISTENERS; null: none)
	public var handlers:Null<Array<Null<SceneEvent->Void>>> = null;

	public function new(node:Node, tag:String) {
		this.node = node;
		this.tag = tag;
		if (tag == "light") relight();
		if (tag == "camera") recamera();
	}

	function get(name:String, def:Dynamic):Dynamic
		return props.exists(name) ? props.get(name) : def;

	@:allow(helder.scene.view) function remesh() {
		var device = SceneRenderer.device;
		if (device == null) {
			@:privateAccess if (SceneRenderer.pending.indexOf(this) < 0) SceneRenderer.pending.push(this);
			return;
		}
		var c:Vec4 = get("color", new Vec4(0.8, 0.8, 0.8, 1));
		var m = new Material(tag, c, get("metallic", 0.0), get("roughness", 0.5));
		var size:Float = get("size", 1.0);
		MeshRenderer.attach(node, switch (get("shape", "box") : String) {
			case "sphere": Shapes.sphere(device, m, size / 2);
			case "plane": Shapes.plane(device, m, size);
			case _: Shapes.box(device, m, size, size, size);
		});
	}

	@:allow(helder.scene.view.SceneRenderer) function relight() {
		var c:Vec3 = get("color", new Vec3(1, 1, 1));
		var i:Float = get("intensity", 1.0);
		Light.attach(node, get("kind", "directional") == "point" ? Light.pointLight(c, i, get("range", 10.0)) : Light.directional(c, i));
	}

	@:allow(helder.scene.view.SceneRenderer) function recamera() {
		var cam = Camera.of(node);
		if (cam == null) cam = Camera.attach(node, Camera.perspective(get("fov", 1.0), get("near", 0.1), get("far", 100.0)));
		else {
			cam.fovY = get("fov", 1.0);
			cam.near = get("near", 0.1);
			cam.far = get("far", 100.0);
		}
	}
}
