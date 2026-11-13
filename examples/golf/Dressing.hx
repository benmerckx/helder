import Course.Hole;
import helder.gfx.shader.Vec3;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.Quat;
import helder.scene.render.Mesh;
import helder.scene.render.MeshRenderer;

// The diorama's dressing round a hole, scenery the ball never touches (the
// cloud sea below it is Clouds'):
//
//   contact shadows  a soft dark skirt along the foot of each rail and
//                    block where it stands on green, a soft disc under
//                    the posts, bumpers, hubs and lanterns (one mesh made
//                    for the hole, two see-through draws), a disc under
//                    the ball fading as it flies; the island's cool shade,
//                    about a quarter darker at the contact line, never black
//   lantern glow     at dusk a halo facing the camera round each lantern
//                    (added light: bloom takes it), a little toward the
//                    camera so the lantern's own light is behind it; the
//                    pool on the green is the lantern's light (Game)
//
// Driven by the view's clock only (Game.realTime): nothing here reads or
// writes the simulation but where the ball is.
class Dressing {
	final world:World;
	final kit:Kit;
	// (the hole's contact shadows: its mesh, made again for each hole)
	var contact:Null<Mesh> = null;
	var contactNode = Node.NONE;
	final ballBlob:Node;
	var groundY = 0.0;
	// (the lanterns' halos, and where each lantern's head is: x, y, z)
	final halos:Array<Node> = [];
	final heads:Array<Float> = [];
	// (the mesh's arrays, kept between holes)
	final skirtP:Array<Float> = [];
	final skirtUv:Array<Float> = [];
	final blobP:Array<Float> = [];
	final blobUv:Array<Float> = [];

	public function new(world:World, kit:Kit) {
		this.world = world;
		this.kit = kit;
		ballBlob = world.node("ballShadow");
		MeshRenderer.attach(ballBlob, kit.blob);
	}

	// the hole's dressing: the contact shadows from its pieces, the lanterns' glow
	public function build(hole:Hole, course:Node, minX:Float, maxX:Float, minZ:Float, maxZ:Float, lanterns:Array<Float>, night:Bool) {
		var device = kit.device;
		if (contact != null) contact.dispose(device);
		contact = null;
		skirtP.resize(0);
		skirtUv.resize(0);
		blobP.resize(0);
		blobUv.resize(0);
		for (piece in hole.pieces)
			switch piece {
				case Wall(x0, z0, x1, z1, y):
					skirts(hole, Math.min(x0, x1), Math.min(z0, z1), Math.max(x0, x1), Math.max(z0, z1), y);
				case Block(x0, z0, x1, z1, y0, _):
					skirts(hole, Math.min(x0, x1), Math.min(z0, z1), Math.max(x0, x1), Math.max(z0, z1), y0);
				case Post(x, z, r, y):
					disc(x, z, y, r * 3.2);
				case Bumper(x, z, r, y):
					disc(x, z, y, r * 3.0);
				case Spinner(x, z, _, y, _, _):
					disc(x, z, y, 0.42);
				case _:
			}
		var c = hole.cup;
		disc(c.x, c.z, c.y, 0.3);
		var i = 0;
		while (i < lanterns.length) {
			disc(lanterns[i], lanterns[i + 2], lanterns[i + 1], 0.5);
			i += 3;
		}
		if (skirtP.length > 0 || blobP.length > 0) {
			var m = new Mesh();
			if (skirtP.length > 0) m.add(device, skirtP, normals(skirtP.length), skirtUv, null, kit.skirtMat);
			if (blobP.length > 0) m.add(device, blobP, normals(blobP.length), blobUv, null, kit.blobMat);
			contact = m;
			contactNode = world.node("contact", course);
			MeshRenderer.attach(contactNode, m);
		}
		// (the lanterns' glow)
		halos.resize(0);
		heads.resize(0);
		var i = 0;
		while (night && i < lanterns.length) {
			var x = lanterns[i], y = lanterns[i + 1], z = lanterns[i + 2];
			var h = world.node("halo", course);
			MeshRenderer.attach(h, kit.glow);
			halos.push(h);
			for (v in [x, y + 0.6, z])
				heads.push(v);
			i += 3;
		}
	}

	static function normals(n:Int):Array<Float>
		return [for (i in 0...n) i % 3 == 1 ? 1.0 : 0.0];

	// whether x, z at height y is on the hole's green (a flat slab or a ramp)
	static function onGreen(hole:Hole, x:Float, z:Float, y:Float):Bool {
		for (p in hole.pieces)
			switch p {
				case Flat(fx, fz, w, d, fy):
					if (Math.abs(x - fx) <= w / 2 && Math.abs(z - fz) <= d / 2 && Math.abs(y - fy) < 0.05) return true;
				case Crumble(fx, fz, w, d, fy):
					if (Math.abs(x - fx) <= w / 2 && Math.abs(z - fz) <= d / 2 && Math.abs(y - fy) < 0.05) return true;
				case RampZ(rx, z0, z1, w, y0, y1):
					if (Math.abs(x - rx) <= w / 2 && z >= Math.min(z0, z1) && z <= Math.max(z0, z1)) {
						var t = (z - z0) / (z1 - z0);
						if (Math.abs(y - (y0 + (y1 - y0) * t)) < 0.08) return true;
					}
				case RampX(rz, x0, x1, d, y0, y1):
					if (Math.abs(z - rz) <= d / 2 && x >= Math.min(x0, x1) && x <= Math.max(x0, x1)) {
						var t = (x - x0) / (x1 - x0);
						if (Math.abs(y - (y0 + (y1 - y0) * t)) < 0.08) return true;
					}
				case _:
			}
		return false;
	}

	// (a skirt along each side of the box lx..hx, lz..hz standing on y, where green is beside it)
	function skirts(hole:Hole, lx:Float, lz:Float, hx:Float, hz:Float, y:Float) {
		var w = 0.22, at = y + 0.003;
		// (each side: its two ends, outward)
		inline function side(ax:Float, az:Float, bx:Float, bz:Float, ox:Float, oz:Float) {
			var px = (ax + bx) / 2 + ox * 0.08, pz = (az + bz) / 2 + oz * 0.08;
			if (onGreen(hole, px, pz, y)) {
				// (two triangles: the wall's edge at v = 0, out to v = 1)
				for (v in [ax, at, az, bx, at, bz, bx + ox * w, at, bz + oz * w, ax, at, az, bx + ox * w, at, bz + oz * w, ax + ox * w, at, az + oz * w])
					skirtP.push(v);
				for (v in [0.5, 0, 0.5, 0, 0.5, 1, 0.5, 0, 0.5, 1, 0.5, 1])
					skirtUv.push(v);
			}
		}
		side(lx, lz, hx, lz, 0, -1);
		side(hx, hz, lx, hz, 0, 1);
		side(lx, hz, lx, lz, -1, 0);
		side(hx, lz, hx, hz, 1, 0);
	}

	// (a soft disc of shade at x, z on y)
	function disc(x:Float, z:Float, y:Float, size:Float) {
		var h = size / 2, at = y + 0.004;
		for (v in [x - h, at, z + h, x + h, at, z + h, x + h, at, z - h, x - h, at, z + h, x + h, at, z - h, x - h, at, z - h])
			blobP.push(v);
		for (v in [0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0])
			blobUv.push(v);
	}

	// the frame: the ball's shade, the lanterns' halos facing the camera (from: the camera)
	public function update(time:Float, ball:Vec3, grounded:Bool, sunk:Bool, eye:Quat, from:Vec3) {
		// (the ball's shade: on the green it rests or rolls on; in the air, on the green it left, fainter and wider)
		if (grounded) groundY = ball.y - Sim.BALL;
		var up = Math.max(0, ball.y - Sim.BALL - groundY);
		ballBlob.visible = !sunk && up < 1.2;
		var s = Sim.BALL * 3.6 * (1 + up * 0.8);
		ballBlob.position = new Vec3(ball.x, groundY + 0.005, ball.z);
		ballBlob.scale = new Vec3(s, 1, s);
		for (i in 0...halos.length) {
			var h = halos[i];
			h.rotation = eye;
			// (toward the camera: the lantern's light behind the halo, not glaring off it)
			var hx = heads[i * 3], hy = heads[i * 3 + 1], hz = heads[i * 3 + 2];
			var tx = from.x - hx, ty = from.y - hy, tz = from.z - hz, tl = Math.sqrt(tx * tx + ty * ty + tz * tz);
			var k = tl > 1e-4 ? 0.2 / tl : 0;
			h.position = new Vec3(hx + tx * k, hy + ty * k, hz + tz * k);
			var f = 0.85 + 0.06 * Math.sin(time * 7.3 + i * 2) + 0.04 * Math.sin(time * 13.1 + i);
			var s = 1.5 * f;
			h.scale = new Vec3(s, s, s);
		}
	}
}
