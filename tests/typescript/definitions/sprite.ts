// helder.sprite's shader (src/helder/sprite/SpriteShader.hx) in TypeScript:
// the same text in every language as Haxe's (Sprite.hx prints that one).
import {shader, position, sample, vec2, vec4, type Vec2, type Vec4, type Texture2D} from "helder/gfx";
import {print} from "./print";

type SpriteVertex = {pos: Vec2, uv: Vec2, color: Vec4};
type SpriteVaryings = {pos: Vec4, uv: Vec2, color: Vec4};
type SpriteView = {view: Vec4};

export const SpriteShader = shader({
	vertex: (v: SpriteVertex, p: {s: SpriteView}): SpriteVaryings =>
		({pos: position(vec4(v.pos.x * p.s.view.x + p.s.view.z, v.pos.y * p.s.view.y + p.s.view.w, 0, 1)), uv: v.uv, color: v.color}),
	fragment: (i, p: {image: Texture2D}) => sample(p.image, i.uv).mul(i.color),
});

print(SpriteShader);
// (the CPU's writers: a uniform block's std140 bytes, the stages run as they are)
const bytes = new Uint8Array(16);
SpriteShader.params.s.write({view: vec4(2, -2, -1, 1)}, bytes);
console.log(Array.from(bytes).join(","));
const o = SpriteShader.vertex({pos: vec2(1, 2), uv: vec2(0.5, 0.5), color: vec4(1, 1, 1, 1)}, {s: {view: vec4(2, -2, -1, 1)}});
console.log(o.pos.x, o.pos.y, o.pos.z, o.pos.w);
// (a texture parameter's slot)
console.log(SpriteShader.params.image.name, SpriteShader.params.image.binding);
