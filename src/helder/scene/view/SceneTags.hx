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
import helder.ui.view.NodeRenderer;
import helder.ui.view.UiView;
import helder.view.graph.Graph;
import helder.view.Render;

// The boundary tags between helder.ui and helder.scene (react-three-fiber's
// <Canvas>, drei's <Html>), imported with import helder.scene.view.SceneTags.*:
//
//   <view direction="row" grow={1}>
//     <Scene grow={1} camera={camera}>
//       <node position={pos}><mesh shape="box" onClick={e -> picked.value = e.node.name}/></node>
//       <light kind="point" intensity={6.0}/>
//       <Ui><text>Hello</text></Ui>
//     </Scene>
//   </view>
//
// <Scene> is a box in ui's layout drawing a world (its own, or world)
// as camera sees it (else the world's first camera, else one at (0, 2, 6)
// looking at the origin), its children scene nodes; ui's pointer events
// over it go to the scene node under the pointer (Pick: bounds, not
// triangles), then its ancestors. <Ui> goes back to ui inside a scene: its
// children drawn by the <Scene>'s ui over the box, at its node's place.
// <OrbitControls> moves its camera from the pointers over it; <Stick>
// draws an on-screen stick (helder.scene.input.VirtualStick) over the ui.
class SceneTags {
	// (the box a scene's markup is drawn in, for <Ui>)
	public static final BOX = new helder.view.graph.Context<Null<SceneBox>>(null, true);

	// a box (ui's: grow, width, height, style...) of world as camera sees it
	public static function Scene(props:{
		?world:World,
		?camera:Camera,
		?grow:Float,
		?width:helder.view.graph.Read<Dynamic>,
		?height:helder.view.graph.Read<Dynamic>,
		?style:Dynamic,
		?animate:Bool,
		?setup:Renderer->Void,
		?ref:SceneBox->Void,
		?children:SceneView
	}):helder.ui.Node {
		var box = new SceneBox(props.world ?? new World("scene"), props.camera);
		if (props.animate != null) box.animate = props.animate;
		if (props.setup != null) box.onRenderer = props.setup;
		if (props.grow != null) NodeRenderer.setProperty(box, "grow", props.grow);
		if (props.width != null) bind(box, "width", props.width);
		if (props.height != null) bind(box, "height", props.height);
		if (props.style != null) NodeRenderer.setStyle(box, props.style);
		// (in this owner: what is above the boundary, contexts, seen below it)
		Graph.provide(SceneRenderer.WORLD, box.world, () -> Graph.provide(BOX, box, () -> Render.insert(props.children, box.root, null)));
		Graph.onCleanup(box.dispose);
		if (props.ref != null) props.ref(box);
		return box;
	}

	static function bind(n:helder.ui.Node, name:String, v:Dynamic)
		Render.isReactive(v) ? Graph.renderEffect(() -> Render.read(v), x -> NodeRenderer.setProperty(n, name, x)) : NodeRenderer.setProperty(n, name, Render.read(v));

	// the <Scene>'s camera orbiting target, driven by the pointers over its
	// box (OrbitControls: one finger or the left button turns it, two
	// pinch and move it, the right button moves it, the wheel zooms); its
	// props are OrbitControls' (a target bound to a signal follows it)
	public static function OrbitControls(props:{
		?camera:Camera,
		?target:Dynamic,
		?minDistance:Float,
		?maxDistance:Float,
		?minPitch:Float,
		?maxPitch:Float,
		?rotateSpeed:Float,
		?zoomSpeed:Float,
		?panSpeed:Float,
		?damping:Float,
		?enableRotate:Bool,
		?enableZoom:Bool,
		?enablePan:Bool,
		?enableTwist:Bool,
		?ref:helder.scene.view.OrbitControls->Void
	}):SceneNode {
		var box = Graph.use(BOX);
		if (box == null) throw "helder.scene: <OrbitControls> is in a <Scene>'s markup";
		var o = new helder.scene.view.OrbitControls(box, props.camera);
		if (props.minDistance != null) o.minDistance = props.minDistance;
		if (props.maxDistance != null) o.maxDistance = props.maxDistance;
		if (props.minPitch != null) o.minPitch = props.minPitch;
		if (props.maxPitch != null) o.maxPitch = props.maxPitch;
		if (props.rotateSpeed != null) o.rotateSpeed = props.rotateSpeed;
		if (props.zoomSpeed != null) o.zoomSpeed = props.zoomSpeed;
		if (props.panSpeed != null) o.panSpeed = props.panSpeed;
		if (props.damping != null) o.damping = props.damping;
		if (props.enableRotate != null) o.enableRotate = props.enableRotate;
		if (props.enableZoom != null) o.enableZoom = props.enableZoom;
		if (props.enablePan != null) o.enablePan = props.enablePan;
		if (props.enableTwist != null) o.enableTwist = props.enableTwist;
		if (props.target != null) {
			// (its value Dynamic: hxmc passes no function of a struct (Vec3) as one of another type)
			if (Render.isReactive(props.target)) Graph.renderEffect(() -> (Render.read(props.target) : Dynamic), (t:Dynamic) -> {
				o.target = t;
				o.look();
			}) else {
				o.target = Render.read(props.target);
				o.look();
			}
		}
		if (props.ref != null) props.ref(o);
		Graph.onCleanup(o.dispose);
		return SceneRenderer.createMarker("orbit-controls");
	}

	// an on-screen stick drawn over the ui (helder.scene.input.VirtualStick,
	// which Actions bind): at rest at left, bottom (points from the lower
	// left), where the thumb holds it once it does; the pointer goes through
	// it (StickNode)
	public static function Stick(props:{bind:helder.scene.input.VirtualStick, ?left:Float, ?bottom:Float, ?color:helder.ui.Color, ?knob:helder.ui.Color}):helder.ui.Node {
		var n = new StickNode(props.bind);
		if (props.left != null) n.restLeft = props.left;
		if (props.bottom != null) n.restBottom = props.bottom;
		if (props.color != null) n.color = props.color;
		if (props.knob != null) n.knobColor = props.knob;
		Graph.onCleanup(() -> props.bind.changed = null);
		return n;
	}

	// ui inside a scene: its children ui's markup, over the <Scene>'s box at
	// its node's place (centred; position, as any node's)
	public static function Ui(props:{?position:Vec3, ?children:UiView}):SceneNode {
		var box = Graph.use(BOX);
		if (box == null) throw "helder.scene: <Ui> is in a <Scene>'s markup";
		var n = SceneRenderer.createElement("ui");
		if (props.position != null) n.node.position = props.position;
		var overlay = new helder.ui.Node("ui");
		overlay.style.position = Absolute;
		box.append(overlay);
		box.overlays.push({node: n, ui: overlay, x: Math.NaN, y: Math.NaN});
		Render.insert(props.children, overlay, null);
		Graph.onCleanup(() -> {
			box.remove(overlay);
			box.overlays = box.overlays.filter(o -> o.ui != overlay);
		});
		return n;
	}
}
