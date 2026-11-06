// The scenes of examples/ts-scene, a module of their own so that tests/3d's
// frames draw them headless (tests/3d/ts/frames.ts).
import {
	World, Camera, Light, Renderer, Material, MeshRenderer, Shapes, material, pbr, type Device, type Encoder, type Model, type PbrSurface,
} from "helder/scene";
import { sin, vec3, vec4, type Vec3, type Vec4 } from "helder/gfx";

// The standard material with two of its slots replaced, as examples/glow's
// (helder/scene's material: compiled with the program into the variants
// the renderer draws with): the emissive slot a pulse of a colour of its
// own (a block the material carries: glow, written by params.glow), the
// colour slot lifting the base colour.
type GlowParams = {
	color: Vec4, // rgb: the light's colour
	time: Vec4, // x: seconds
};

export const GlowMaterial = material(pbr.with({
	emissive: (s: PbrSurface, p: {glow: GlowParams}): Vec3 => p.glow.color.xyz.mul(0.6 + 0.4 * sin(p.glow.time.x * 3 + s.world.x)),
	color: (s: PbrSurface, p: {}): Vec3 => s.baseColor.xyz.mul(1.4),
}));

// a glowing orb's material, its block's bytes (at(t) writes them)
function orb(bytes: Uint8Array): Material {
	const m = new Material("orb", vec4(0.35, 0.3, 0.5, 1), 0, 0.4);
	GlowMaterial.apply(m, {glow: bytes});
	return m;
}

function glowAt(t: number, bytes: Uint8Array) {
	GlowMaterial.params.glow.write({color: vec4(1, 0.55, 0.2, 1), time: vec4(t, 0, 0, 0)}, bytes);
}

// examples/glow's scene in TypeScript, node for node: a floor and five orbs
// of one mesh (instanced) under the renderer's sun (tests/3d's ts-glow
// frame is glow.png, Haxe's)
export class Glow {
	readonly world = new World("glow");
	readonly bytes = new Uint8Array(32);
	readonly camera: Camera;
	readonly renderer: Renderer;

	constructor(device: Device) {
		this.renderer = new Renderer(device);
		this.renderer.sky = vec3(0.12, 0.14, 0.2);
		this.renderer.ground = vec3(0.04, 0.04, 0.05);
		const floor = this.world.node("floor");
		floor.position = vec3(0, -0.6, 0);
		MeshRenderer.attach(floor, Shapes.plane(device, new Material("floor", vec4(0.4, 0.42, 0.45, 1), 0, 0.85), 8));
		const mesh = Shapes.sphere(device, orb(this.bytes), 0.35);
		for (let k = 0; k < 5; k++) {
			const n = this.world.node("orb" + k);
			n.position = vec3((k - 2) * 0.85, -0.25, 0);
			MeshRenderer.attach(n, mesh);
		}
		const eye = this.world.node("eye");
		this.camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		eye.position = vec3(0, 1.1, 3.6);
		eye.lookAt(vec3(0, -0.3, 0));
		this.at(0);
	}

	// the glow at time t (seconds)
	at(t: number) {
		glowAt(t, this.bytes);
	}

	draw(enc: Encoder) {
		this.renderer.draw(enc, this.world, this.camera);
	}
}

// examples/gltf-viewer's sample model (a pedestal and its ball, a moon, a
// satellite, its camera) lit by the sun and a warm point light, three
// glowing orbs round it (tests/3d's tsscene frame; Scenes.hx draws the same
// in Haxe against the same golden)
export class Showcase {
	readonly world = new World("showcase");
	readonly bytes = new Uint8Array(32);
	readonly camera: Camera;
	readonly renderer: Renderer;

	constructor(device: Device, sample: Model<any, any, any, any>) {
		this.renderer = new Renderer(device);
		sample.instantiate(this.world, device);
		this.camera = Camera.first(this.world)!;
		const lamp = this.world.node("lamp");
		lamp.position = vec3(0.6, 1.6, 1.8);
		Light.attach(lamp, Light.pointLight(vec3(1, 0.6, 0.3), 5, 5));
		const mesh = Shapes.sphere(device, orb(this.bytes), 0.3);
		const at = [vec3(1.7, 0.3, 1.4), vec3(-0.3, 0.3, 2.3), vec3(-2.1, 0.3, -0.6)];
		for (let k = 0; k < at.length; k++) {
			const n = this.world.node("orb" + k);
			n.position = at[k];
			MeshRenderer.attach(n, mesh);
		}
		this.at(0);
	}

	at(t: number) {
		glowAt(t, this.bytes);
	}

	draw(enc: Encoder) {
		this.renderer.draw(enc, this.world, this.camera);
	}
}
