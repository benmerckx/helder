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
import helder.view.Reactive;
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
class SceneTags {
	// (the box a scene's markup is drawn in, for <Ui>)
	public static final BOX = new helder.view.Context<Null<SceneBox>>(null);

	// a box (ui's: grow, width, height, style...) of world as camera sees it
	public static function Scene(props:{
		?world:World,
		?camera:Camera,
		?grow:Float,
		?width:Dynamic,
		?height:Dynamic,
		?style:Dynamic,
		?children:SceneView
	}):helder.ui.Node {
		var box = new SceneBox(props.world ?? new World("scene"), props.camera);
		if (props.grow != null) NodeRenderer.setProperty(box, "grow", props.grow);
		if (props.width != null) bind(box, "width", props.width);
		if (props.height != null) bind(box, "height", props.height);
		if (props.style != null) NodeRenderer.setStyle(box, props.style);
		// (in this owner: what is above the boundary, contexts, seen below it)
		Reactive.provide(SceneRenderer.WORLD, box.world, () -> Reactive.provide(BOX, box, () -> Render.insert(props.children, box.root, null)));
		Reactive.onCleanup(box.dispose);
		return box;
	}

	static function bind(n:helder.ui.Node, name:String, v:Dynamic)
		Render.isReactive(v) ? Reactive.effect(() -> NodeRenderer.setProperty(n, name, Render.read(v))) : NodeRenderer.setProperty(n, name, v);

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
		Reactive.onCleanup(() -> props.bind.changed = null);
		return n;
	}

	// ui inside a scene: its children ui's markup, over the <Scene>'s box at
	// its node's place (centred; position, as any node's)
	public static function Ui(props:{?position:Vec3, ?children:UiView}):SceneNode {
		var box = Reactive.use(BOX);
		if (box == null) throw "helder.scene: <Ui> is in a <Scene>'s markup";
		var n = SceneRenderer.createElement("ui");
		if (props.position != null) n.node.position = props.position;
		var overlay = new helder.ui.Node("ui");
		overlay.style.position = Absolute;
		box.append(overlay);
		box.overlays.push({node: n, ui: overlay, x: Math.NaN, y: Math.NaN});
		Render.insert(props.children, overlay, null);
		Reactive.onCleanup(() -> {
			box.remove(overlay);
			box.overlays = box.overlays.filter(o -> o.ui != overlay);
		});
		return n;
	}
}
