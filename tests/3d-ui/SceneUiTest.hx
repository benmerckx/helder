import helder.gfx.shader.Vec3;
import helder.scene.*;
import helder.scene.render.Light;
import helder.scene.view.SceneRenderer;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;

// helder.scene.view (npm test -- 3d: natively): markup making a
// world's nodes, lights and cameras; properties bound to signals following
// them (a struct value, Vec3, bound through a Signal: hxmc does not yet
// pass a closure returning one where a function of another type is
// expected, memo's or a bare function's); Show adding and removing a
// subtree; For keyed rows.
class SceneUiTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	static function check(what:String, ok:Bool) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('SceneUiTest: FAIL: $what');
		}
	}

	static function main() {
		var world = new World();
		var x = signal(1.0);
		var pos = signal(new Vec3(1, 0, 0));
		var shown = signal(true);
		var moons = signal(["io", "europa"]);
		Render.render(<node name="planet" position={pos}>
			<node name="ring" scale={new Vec3(2, 0.1, 2)}/>
			<light kind="point" intensity={() -> x() * 2} range={8.0}/>
			<Show when={shown}><node name="flag"/></Show>
			<For each={moons}>{m -> <node name={m()}/>}</For>
		</node>, SceneRenderer.root(world));
		var planet = world.root.find("planet");
		check("made", !planet.isNone && planet.parent == world.root && !world.root.find("ring").isNone);
		check("a static property", world.root.find("ring").scale.x == 2);
		check("a bound property", planet.position.x == 1);
		x(3);
		flush();
		pos(new Vec3(3, 0, 0));
		flush();
		check("follows its signal", planet.position.x == 3);
		var light:Null<Light> = null;
		for (c in planet.children())
			if (Light.of(c) != null) light = Light.of(c);
		check("a light, its bound intensity", light != null && light.point && light.intensity == 6 && light.range == 8);
		check("Show: there", !world.root.find("flag").isNone && world.inTree(world.root.find("flag")));
		var flag = world.root.find("flag");
		shown(false);
		flush();
		check("Show: taken out", world.root.find("flag").isNone && !world.inTree(flag));
		shown(true);
		flush();
		check("Show: back", !world.root.find("flag").isNone);
		check("For: rows", !world.root.find("io").isNone && !world.root.find("europa").isNone);
		moons(["europa", "ganymede"]);
		flush();
		check("For: a row removed, one added", world.root.find("io").isNone || !world.inTree(world.root.find("io")));
		check("For: the new row", !world.root.find("ganymede").isNone && world.inTree(world.root.find("ganymede")));
		Sys.println('SceneUiTest: $checks checks, ' + (failed == 0 ? "ok" : '$failed FAILED'));
		if (failed > 0) Sys.exit(1);
	}
}
