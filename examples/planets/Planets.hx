// title: Planets
// summary: A scene in ui's layout, all markup: <Scene> beside a panel, nodes turned by signals, a planet picked by a click, its name over it (<Ui>)
// tags: 3d, ui, view, scene markup
// demo: canvas 640x400
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.World;
import helder.scene.math.Quat;
import helder.scene.view.SceneTags.*;
import helder.scene.view.SceneView;
import helder.ui.Clock;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.Reactive.*;

// helder.view's markup across three renderers' boundaries: the window
// (<Surface>), ui's layout in it, a <Scene> box whose children are scene
// nodes, and <Ui> back to ui over a picked planet. Each orbit is a node
// whose rotation is a signal the ui's clock turns; a click on a planet
// (ui's pointer event, picked in the scene) selects it, the panel and the
// label follow the signal. No define names a renderer: each subtree is
// compiled for the tag that owns it.
class Planets implements Markup {
	static final planets = [
		{name: "Mercury", r: 1.6, size: 0.3, speed: 1.2, color: new Vec4(0.6, 0.6, 0.62, 1)},
		{name: "Venus", r: 2.5, size: 0.45, speed: 0.8, color: new Vec4(0.95, 0.75, 0.4, 1)},
		{name: "Earth", r: 3.5, size: 0.5, speed: 0.55, color: new Vec4(0.2, 0.45, 0.95, 1)},
		{name: "Mars", r: 4.5, size: 0.4, speed: 0.4, color: new Vec4(0.9, 0.35, 0.2, 1)}
	];

	static function main() {
		var picked = signal("none");
		var world = new World("planets"), eye = world.node("eye");
		eye.position = new Vec3(0, 5, 8);
		eye.lookAt(new Vec3(0, 0, 0));
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		UiWindow.run(<Surface title="Planets" width={640} height={400}>
			<view direction="row" grow={1}>
				<Scene world={world} camera={camera} grow={1}>
					<mesh shape="sphere" size={1.2} color={new Vec4(1, 0.8, 0.3, 1)} onClick={_ -> picked.value = "the Sun"}/>
					<light kind="point" intensity={10.0} range={30.0}/>
					{[for (p in planets) <Planet name={p.name} r={p.r} size={p.size} speed={p.speed} color={p.color} picked={picked}/>]}
				</Scene>
				<view width={160} padding={16} row-gap={8} background="#18181b" color="#fafafa">
					<text font-size={16}>Planets</text>
					<text font-size={13}>Picked: {picked}</text>
				</view>
			</view>
		</Surface>);
	}

	// an orbit (a node the clock turns) and its planet, its name over it once picked
	static function Planet(props:{name:String, r:Float, size:Float, speed:Float, color:Vec4, picked:Signal<String>}):SceneView {
		var turn = signal(Quat.identity());
		Clock.add(t -> {
			turn.value = Quat.axisAngle(new Vec3(0, 1, 0), t * props.speed);
			true;
		});
		return <node rotation={turn}>
			<node position={new Vec3(props.r, 0, 0)}>
				<mesh shape="sphere" size={props.size} color={props.color} onClick={_ -> props.picked.value = props.name}/>
				<Show when={() -> props.picked.value == props.name}>
					<Ui position={new Vec3(0, props.size, 0)}>
						<text font-size={12} color="#fafafa" padding="2 6" radius={4} background="#000000a0">{props.name}</text>
					</Ui>
				</Show>
			</node>
		</node>;
	}
}
