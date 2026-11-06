// helder.scene for TypeScript: a World of Nodes (src/helder/scene/README.md),
// cameras, lights, meshes and materials, glTF models, the renderer, input
// actions, and what a scene is drawn with (a window, its device, the app's
// loop: helder/scene/runtime, helder's Haxe classes), with Node, a class of
// the program's over a node's handle:
//
//   import { World, Camera, Light, Renderer, Window, Device, App } from "helder/scene";
//   import { vec3 } from "helder/gfx";
//
//   const world = new World("demo");
//   const eye = world.node("eye");
//   const camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
//   eye.position = vec3(0, 1, 4);            // Vec3 and Quat: helder/gfx's values
//   eye.lookAt(vec3(0, 0, 0));
//   Light.attach(world.node("lamp"), Light.pointLight(vec3(1, 0.8, 0.6), 6, 8));
//
// A node is its world's handle (Haxe's helder.scene.Node, an Int): a Node
// is an object of that id, made where helder gives one (world.node(...),
// camera.node, model.instantiate(...)) and read where helder takes one, so
// two Nodes of the same node are equal by equals(), not by ===. NONE's is
// a Node of id 0 (isNone: the root's parent, find's nothing).
//
// material(pbr.with({...})) is a material's own shader, Haxe's
// MaterialShader.material (src/helder/scene/render/MaterialShader.hx): pbr,
// the standard material's slot object (./pbr.ts, PbrShader.hx's), with some
// of its slots replaced, a definition compiled with the program into the
// variants the renderer draws with; a slot's parameters that are not the
// stages' are blocks of the material's own (params: their writers):
//
//   type GlowParams = {color: Vec4, time: Vec4};
//   const Glow = material(pbr.with({
//     emissive: (s: PbrSurface, p: {glow: GlowParams}) => p.glow.color.xyz.mul(sin(p.glow.time.x).mul(0.4).add(0.6)),
//   }));
//   const bytes = new Uint8Array(32);
//   Glow.apply(orb, {glow: bytes});          // orb.shader, its block
//   Glow.params.glow.write({color: vec4(1, 0.5, 0.2, 1), time: vec4(t, 0, 0, 0)}, bytes);
import { Script, MaterialShader, type Material } from "helder/scene/runtime";
import {
	UniformWriter, TextureSlot, type Mat4, type Quat, type Vec3, type Params, type Slots, type SlotsDef, type ShaderCode, type VertexBufferLayout,
	type UniformBlock, type TextureBinding,
} from "helder/gfx";
import type { World } from "helder/scene/runtime";

export * from "helder/scene/runtime";
export {
	pbr, pbrColor, pbrAlpha, pbrNormal, pbrRoughness, pbrMetalness, pbrEmissive, pbrPosition, type Pbr, type PbrVertex, type PbrVaryings,
	type PbrFrame, type PbrObject, type PbrMaterial, type PbrSkinInfo, type PbrVertexParams, type PbrFragmentParams, type PbrOptions,
	type PbrSurface, type PbrPoint,
} from "./pbr";

// a material's own shader (material(...)): the renderer's MaterialShader, the
// writers of its own blocks (and its textures' slots), and apply(m, blocks),
// which sets it on a material with its blocks' bytes by their names
export type MaterialOf<P> = {
	readonly shader: MaterialShader,
	readonly params: Params<P>,
	// (each variant's code and layout, as MaterialShader's: plain, normal mapped, skinned, instanced, instanced and normal mapped)
	readonly variants: readonly MaterialVariant[],
	// its blocks: their parameters' names, their slots in each variant
	readonly blocks: readonly {name: string, bindings: number[]}[],
	apply(m: Material, blocks: {readonly [K in keyof P]?: Uint8Array}): void,
};

export type MaterialVariant = {
	readonly vertexCode: ShaderCode, readonly fragmentCode: ShaderCode, readonly layout: VertexBufferLayout[], readonly uniforms: UniformBlock[],
	readonly textures: TextureBinding[],
};

/** @definition material */
export function material<D extends SlotsDef, X>(def: Slots<D, X>, generated?: string): MaterialOf<X> {
	if (generated === undefined) throw new Error("material: a definition, compiled by helder's compiler (its slot object static)");
	const g = JSON.parse(generated);
	const params: {[parameter: string]: UniformWriter<any> | TextureSlot} = {};
	for (const b of g.variants[0].params) params[b.param] = b.texture !== undefined ? new TextureSlot(b.texture.name, b.texture.binding) : new UniformWriter<any>(b.block, b.fields);
	const shader = MaterialShader.script(generated);
	return {
		shader,
		params: params as any,
		variants: g.variants.map((v: any) => ({vertexCode: v.vertexCode, fragmentCode: v.fragmentCode, layout: v.layout, uniforms: v.uniforms, textures: v.textures})),
		blocks: g.blocks,
		apply(m: Material, blocks: {[name: string]: Uint8Array | undefined}) {
			m.shader = shader;
			for (const name of Object.keys(blocks)) {
				const bytes = blocks[name];
				if (bytes !== undefined) Script.materialBlock(m, name, bytes);
			}
		},
	};
}

// helder.os's EventKind (an Event's kind) by name
export const EventKind = {
	None: 0, Close: 1, Resize: 2, KeyDown: 3, KeyUp: 4, MouseMove: 5, MouseDown: 6, MouseUp: 7, TextInput: 8, Redraw: 9, TextEditing: 10,
	Scroll: 11, ScaleChange: 12, Suspend: 13, Resume: 14, PointerDown: 15, PointerMove: 16, PointerUp: 17, PointerCancel: 18, Drop: 19, TextReplace: 20,
} as const;
export type EventKind = number;

export class Node {
	constructor(readonly id: number) {}
	get world(): World {
		return Script.world(this);
	}
	get isNone(): boolean {
		return this.id === 0;
	}
	// not disposed (every other access to a disposed node throws)
	get valid(): boolean {
		return this.id !== 0 && Script.valid(this);
	}
	get name(): string {
		return Script.name(this);
	}
	set name(v: string) {
		Script.setName(this, v);
	}
	get position(): Vec3 {
		return Script.position(this);
	}
	set position(v: Vec3) {
		Script.setPosition(this, v);
	}
	get rotation(): Quat {
		return Script.rotation(this);
	}
	set rotation(v: Quat) {
		Script.setRotation(this, v);
	}
	get scale(): Vec3 {
		return Script.scale(this);
	}
	set scale(v: Vec3) {
		Script.setScale(this, v);
	}
	// hidden: neither it nor what is below it is drawn
	get visible(): boolean {
		return Script.visible(this);
	}
	set visible(v: boolean) {
		Script.setVisible(this, v);
	}
	// NONE's for the root (and a node taken out of the tree)
	get parent(): Node {
		return Script.parent(this);
	}
	add(child: Node): Node {
		return Script.add(this, child);
	}
	// out of its parent (it and what is below it no longer drawn or reached from the root)
	detach(): void {
		Script.detach(this);
	}
	children(): Node[] {
		return Script.children(this).map(id => new Node(id));
	}
	localMatrix(): Mat4 {
		return Script.localMatrix(this);
	}
	// cached until a transform above it changes
	worldMatrix(): Mat4 {
		return Script.worldMatrix(this);
	}
	worldPosition(): Vec3 {
		return Script.worldPosition(this);
	}
	setMatrix(m: Mat4): void {
		Script.setMatrix(this, m);
	}
	// turned so that its -z looks at target (a point in its parent's space)
	lookAt(target: Vec3, up?: Vec3): void {
		if (up === undefined) Script.lookAt(this, target);
		else Script.lookAtUp(this, target, up);
	}
	// the first node named name, this one or below it (depth first)
	find(name: string): Node {
		return Script.find(this, name);
	}
	// whether it and all its ancestors are visible
	shown(): boolean {
		return Script.shown(this);
	}
	// it and what is below it removed from the world (their components too)
	dispose(): void {
		Script.dispose(this);
	}
	equals(other: Node): boolean {
		return this.id === other.id;
	}
}
