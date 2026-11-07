import Reel.*;
import Reel.SceneDef;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.*;
import helder.scene.math.*;
import helder.scene.render.*;
import helder.scene.render.PbrShader;
import helder.scene.view.SceneTags.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

// The knot's light: its colour, the pulse's place along the knot and the time
typedef KnotGlow = {
	var color:Vec4; // rgb: the light's colour, w: its strength
	var pulse:Vec4; // x: seconds, y: pulses along the knot, z: their width
}

// helder.scene's standard material with its emissive slot replaced: pulses
// of light running along the knot (its uv's u is the way along it), bright
// past 1 so the HDR frame's bloom spreads them; the colour slot darkens
// the base into a smoked metal. Compiled at build time into the variants
// the renderer draws with (MaterialShader.material over pbr.with).
final KnotShader = MaterialShader.material(pbr.with({
	emissive: function(s:PbrSurface, p:{knot:KnotGlow}):Vec3 {
		var u = fract(s.uv.x * p.knot.pulse.y - p.knot.pulse.x * 0.35);
		var band = smoothstep(0.0, p.knot.pulse.z, u) * (1.0 - smoothstep(p.knot.pulse.z, p.knot.pulse.z * 2.6, u));
		var rim = 0.025 + 0.02 * sin(s.uv.y * 6.2831);
		return p.knot.color.xyz * (band * p.knot.color.w + rim);
	},
	color: function(s:PbrSurface, p:{}):Vec3 return s.baseColor.xyz * 0.6
}));

// A 3D scene in the reel: a torus knot of smoked metal with light running
// along it (KnotShader: the emissive slot), orbs ringed around it, a floor
// catching their glow, the camera circling; drawn by helder.scene in a
// <Scene hdr> box under the reel's type.
class Knot implements Markup {
	public static final scene:SceneDef = {name: "material", title: "A material slot, glowing", duration: 7.0, view: view};

	static var world:Null<World> = null;
	static var camera:Null<Camera> = null;
	static var eye:Null<helder.scene.Node> = null;
	static var built = false;
	static final knotBytes = haxe.io.Bytes.alloc(32);

	// a torus knot (p, q) around radius r, its tube of radius tube; u along it, v around the tube
	static function knot(device:helder.gfx.Device, material:helder.scene.render.Material, p = 2, q = 3, r = 0.82, tube = 0.085, segments = 480,
			sides = 20):Mesh {
		var pos:Array<Float> = [], nor:Array<Float> = [], uv:Array<Float> = [], idx:Array<Int> = [];
		inline function at(a:Float):Vec3 {
			var rr = r + r * 0.42 * Math.cos(q * a);
			return new Vec3(rr * Math.cos(p * a), r * 0.42 * Math.sin(q * a) + rr * Math.sin(p * a) * 0.0, rr * Math.sin(p * a));
		}
		for (i in 0...segments + 1) {
			var a = i / segments * Math.PI * 2;
			var c = at(a), n = at(a + 0.001);
			var tx = n.x - c.x, ty = n.y - c.y, tz = n.z - c.z;
			var tl = Math.sqrt(tx * tx + ty * ty + tz * tz);
			tx /= tl;
			ty /= tl;
			tz /= tl;
			// (a frame around the tangent: b = t x c, nn = b x t)
			var bx = ty * c.z - tz * c.y, by = tz * c.x - tx * c.z, bz = tx * c.y - ty * c.x;
			var bl = Math.sqrt(bx * bx + by * by + bz * bz);
			bx /= bl;
			by /= bl;
			bz /= bl;
			var nx = by * tz - bz * ty, ny = bz * tx - bx * tz, nz = bx * ty - by * tx;
			for (j in 0...sides + 1) {
				var b = j / sides * Math.PI * 2, cs = Math.cos(b), sn = Math.sin(b);
				var ox = nx * cs + bx * sn, oy = ny * cs + by * sn, oz = nz * cs + bz * sn;
				pos.push(c.x + ox * tube);
				pos.push(c.y + oy * tube);
				pos.push(c.z + oz * tube);
				nor.push(ox);
				nor.push(oy);
				nor.push(oz);
				uv.push(i / segments);
				uv.push(j / sides);
			}
		}
		for (i in 0...segments)
			for (j in 0...sides) {
				var a = i * (sides + 1) + j, b = a + sides + 1;
				for (k in [a, a + 1, b, a + 1, b + 1, b])
					idx.push(k);
			}
		var m = new Mesh();
		m.add(device, pos, nor, uv, idx, material);
		return m;
	}

	static function make() {
		if (world != null) return;
		world = new World("material");
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.75, 0.1, 100));
		look(0);
	}

	// the camera at t: circling, a little above
	static function look(t:Float) {
		var a = 0.6 + t * 0.32;
		eye.position = new Vec3(Math.sin(a) * 3.4, 1.5 + 0.3 * Math.sin(t * 0.5), Math.cos(a) * 3.4);
		eye.lookAt(new Vec3(0, 0.05, 0));
		if (renderer != null && renderer.post != null) {
			renderer.post.bloom = 0.16;
			renderer.post.vignette = 0.45;
		}
		KnotShader.params.knot.write({color: new Vec4(0.25, 0.5, 1.0, 6.0), pulse: new Vec4(t, 4, 0.035, 0)}, knotBytes);
	}

	static var renderer:Null<Renderer> = null;

	static function setup(r:Renderer) {
		renderer = r;
		r.clearColor = new helder.gfx.Color(0.027, 0.031, 0.05, 1);
		r.sky = new Vec3(0.015, 0.018, 0.03);
		r.ground = new Vec3(0.004, 0.004, 0.006);
		r.sunColor = new Vec3(0.55, 0.55, 0.75);
		r.sunDirection = new Vec3(-0.35, 0.8, 0.4);
		r.rim = new Vec3(0.25, 0.32, 0.6);
		r.exposure = 1.0;
		var w = world;
		if (built) return;
		built = true;
		var d = r.device;
		var floor = w.node("floor");
		floor.position = new Vec3(0, -0.75, 0);
		MeshRenderer.attach(floor, Shapes.plane(d, new helder.scene.render.Material("floor", new Vec4(0.03, 0.033, 0.045, 1), 0, 0.92), 60));
		var metal = new helder.scene.render.Material("knot", new Vec4(0.12, 0.12, 0.14, 1), 1, 0.28);
		metal.shader = KnotShader;
		metal.uniforms = ["knot" => knotBytes];
		var k = w.node("knot");
		k.position = new Vec3(0, 0.05, 0);
		MeshRenderer.attach(k, knot(d, metal));
		var colors = [new Vec4(0.43, 0.55, 1, 1), new Vec4(0.66, 0.55, 1, 1), new Vec4(0.24, 0.88, 0.66, 1), new Vec4(1, 0.75, 0.28, 1), new Vec4(1, 0.44, 0.57, 1)];
		for (i in 0...10) {
			var c = colors[i % colors.length];
			var m = new helder.scene.render.Material("orb" + i, new Vec4(c.x * 0.1, c.y * 0.1, c.z * 0.1, 1), 0, 0.3);
			m.emissive = new Vec3(c.x * c.x * 1.6, c.y * c.y * 1.6, c.z * c.z * 1.6);
			var o = w.node("orb" + i), a = i / 10 * Math.PI * 2;
			o.position = new Vec3(Math.cos(a) * 1.9, -0.55 + 0.12 * Math.sin(a * 3), Math.sin(a) * 1.9);
			MeshRenderer.attach(o, Shapes.sphere(d, m, 0.1, 24, 12));
		}
	}

	static final CODE = ["final KnotShader = MaterialShader.material(", "  pbr.with({emissive: (s, p) ->", "    p.knot.color.xyz * pulse(s.uv.x)})", ");"];

	public static function view(t:Read<Float>):View {
		make();
		effect(() -> t(), x -> look(x));
		return <view grow={1} background={NIGHT} color={INK} font-family="Inter">
			<Scene grow={1} world={world} camera={camera} hdr animate setup={setup}/>
			<view position="absolute" left={56} bottom={48} row-gap={10} width={520}>
				<Show when={() -> at(t(), 0.5)}>
					<view row-gap={10} transition="fade slide-up(20)">
						<text font-size={14} color={MUTED} font-weight={600} letter-spacing={1.6}>HELDER.SCENE · HDR · BLOOM</text>
						<text font-family="Inter Display" font-size={44} font-weight={700} letter-spacing={-1} line-height={1.05}>Light along a knot</text>
					</view>
				</Show>
				<Show when={() -> at(t(), 1.4)}>
					<view padding="14 16" radius={12} background="#0b0d16cc" border-width={1} border-color={LINE} transition="fade slide-up(20)">
						<For each={CODE} keyed={false}>{line -> <text font-family="JetBrains Mono" font-size={13} line-height={1.55} color="#c9d1f5" text-wrap="nowrap">{line()}</text>}</For>
					</view>
				</Show>
			</view>
		</view>;
	}
}
