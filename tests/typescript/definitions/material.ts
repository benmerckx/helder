// helder/scene's material(pbr.with({...})) in TypeScript: examples/glow's
// material (pbr's emissive slot a pulse of a block of its own, its colour
// slot lifting the base colour), its five variants the same text in every
// language as Haxe's MaterialShader.material (Material.hx), its block's
// slot in each, its writer's bytes. (A literal below 1e-4: as pbr.ts says)
import {material, pbr, type PbrSurface} from "helder/scene";
import {sin, vec4, type Vec3, type Vec4} from "helder/gfx";
import {print} from "./print";

type GlowParams = {color: Vec4, time: Vec4};

const Glow = material(pbr.with({
	emissive: (s: PbrSurface, p: {glow: GlowParams}): Vec3 => p.glow.color.xyz.mul(0.6 + 0.4 * sin(p.glow.time.x * 3 + s.world.x)),
	color: (s: PbrSurface, p: {}): Vec3 => s.baseColor.xyz.mul(1.4),
}));

for (const v of Glow.variants) print(v);
for (const b of Glow.blocks) console.log(`block ${b.name} ${b.bindings.join(" ")}`);
const bytes = new Uint8Array(32);
Glow.params.glow.write({color: vec4(1, 0.55, 0.2, 1), time: vec4(2.5, 0, 0, 0)}, bytes);
console.log(Glow.params.glow.block.binding, Glow.params.glow.block.size, Array.from(bytes).join(" "));
