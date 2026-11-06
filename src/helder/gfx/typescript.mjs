// helder/gfx for TypeScript programs: writes src/helder/gfx/index.ts, the
// math types and shader({vertex, fragment}) as TypeScript itself (CPU code,
// compiled with the program), as helder.gfx.shader's VecBuild writes Haxe's:
// each vector's componentwise add, sub, mul and div (a vector or a number),
// neg and swizzles of 2 to 4 components; Mat4's mul (a matrix or a vector);
// ShaderMath's builtins by the same names. shader(...) is a definition
// (src/helder/compiler/DESIGN.md): the compiler checks and compiles its
// stages at build time (helder.typescript.lower's TS adapter, the handler
// helder.gfx.shader.ShaderDefinition shared with Haxe) and passes what it
// made as its second argument.
//   node src/helder/gfx/typescript.mjs [--check]
import fs from 'node:fs';

const XYZW = ['x', 'y', 'z', 'w'];
const out = [];
const w = (s) => out.push(s);
w(`// helder/gfx for TypeScript: written by src/helder/gfx/typescript.mjs (do not edit).
//
// The shader math as CPU code (helder.gfx.shader's types, the same names),
// and shader({vertex, fragment}), a definition: its stages compiled when the
// program is built, to GLSL, WGSL, MSL and HLSL, the same text as Haxe's
// shader({...}) of the same functions (src/helder/gfx/shader/Shader.hx):
//
//   type Vertex = {pos: Vec2, color: Vec3};
//   type Varyings = {pos: Vec4, color: Vec3};
//   type Tint = {color: Vec4};
//   export const Triangle = shader({
//     vertex: (v: Vertex): Varyings => ({pos: position(vec4(v.pos, 0, 1)), color: v.color}),
//     fragment: (i: Varyings, p: {tint: Tint}) => vec4(i.color, 1).mul(p.tint.color),
//   });
//   Triangle.params.tint.write({color: vec4(1)}, bytes);
//
// A stage's parameters are one object, after its input: its fields uniform
// blocks and textures (params: a UniformWriter or a TextureSlot each).
// The operators are methods (a.mul(b), a.add(1); a number's side second:
// x.mul(2), as Haxe's 2 * x prints).
// Structs are type aliases of object types (their name the struct's).

type Scalar = number;
`);

function vecClass(n) {
	const self = `Vec${n}`, c = XYZW.slice(0, n);
	const each = (f) => `new ${self}(${c.map((k) => f(k)).join(', ')})`;
	w(`export class ${self} {`);
	w(`\tconstructor(${c.map((k) => `readonly ${k}: number`).join(', ')}) {}`);
	for (const [name, op] of [['add', '+'], ['sub', '-'], ['mul', '*'], ['div', '/']])
		w(`\t${name}(b: ${self} | number): ${self} {\n\t\treturn typeof b === "number" ? ${each((k) => `this.${k} ${op} b`)} : ${each((k) => `this.${k} ${op} b.${k}`)};\n\t}`);
	w(`\tneg(): ${self} {\n\t\treturn ${each((k) => `-this.${k}`)};\n\t}`);
	const sw = (prefix, len) => {
		if (prefix.length === len) {
			w(`\tget ${prefix}(): Vec${len} {\n\t\treturn new Vec${len}(${[...prefix].map((k) => `this.${k}`).join(', ')});\n\t}`);
			return;
		}
		for (const k of c) sw(prefix + k, len);
	};
	for (let len = 2; len <= 4; len++) sw('', len);
	w(`}\n`);
}
for (const n of [2, 3, 4]) vecClass(n);
w(`export class Mat4 {
	constructor(readonly c0: Vec4, readonly c1: Vec4, readonly c2: Vec4, readonly c3: Vec4) {}
	mul(b: Mat4): Mat4;
	mul(b: Vec4): Vec4;
	mul(b: Mat4 | Vec4): Mat4 | Vec4 {
		if (b instanceof Vec4) return this.c0.mul(b.x).add(this.c1.mul(b.y)).add(this.c2.mul(b.z)).add(this.c3.mul(b.w));
		return new Mat4(this.mul(b.c0), this.mul(b.c1), this.mul(b.c2), this.mul(b.c3));
	}
}

// a texture and its sampler, a shader's parameter (sample(t, uv)); on the
// CPU, RGBA8 texels, rows top to bottom, read at the nearest, repeating
export class Texture2D {
	constructor(readonly width: number, readonly height: number, readonly texels: Uint8Array) {}
	read(uv: Vec2): Vec4 {
		const x = Math.floor((uv.x - Math.floor(uv.x)) * this.width), y = Math.floor((uv.y - Math.floor(uv.y)) * this.height);
		const p = 4 * (y * this.width + x);
		return new Vec4(this.texels[p] / 255, this.texels[p + 1] / 255, this.texels[p + 2] / 255, this.texels[p + 3] / 255);
	}
}

type Vec = Vec2 | Vec3 | Vec4;
type Flat = number | Vec;

// (a function of numbers, componentwise over vectors; numbers broadcast)
function each(f: (...xs: number[]) => number, xs: Flat[]): any {
	let shape: Vec | undefined;
	for (const x of xs) if (typeof x !== "number") shape = x;
	if (shape === undefined) return f(...(xs as number[]));
	const at = (x: Flat, k: "x" | "y" | "z" | "w") => typeof x === "number" ? x : (x as any)[k] as number;
	if (shape instanceof Vec2) return new Vec2(f(...xs.map((x) => at(x, "x"))), f(...xs.map((x) => at(x, "y"))));
	if (shape instanceof Vec3) return new Vec3(f(...xs.map((x) => at(x, "x"))), f(...xs.map((x) => at(x, "y"))), f(...xs.map((x) => at(x, "z"))));
	return new Vec4(f(...xs.map((x) => at(x, "x"))), f(...xs.map((x) => at(x, "y"))), f(...xs.map((x) => at(x, "z"))), f(...xs.map((x) => at(x, "w"))));
}
`);
const unary = [['abs', 'Math.abs(x)'], ['sign', 'x > 0 ? 1 : x < 0 ? -1 : 0'], ['floor', 'Math.floor(x)'], ['ceil', 'Math.ceil(x)'],
	['fract', 'x - Math.floor(x)'], ['sqrt', 'Math.sqrt(x)'], ['inversesqrt', '1 / Math.sqrt(x)'], ['sin', 'Math.sin(x)'], ['cos', 'Math.cos(x)'],
	['tan', 'Math.tan(x)'], ['exp', 'Math.exp(x)'], ['log', 'Math.log(x)']];
for (const [name, body] of unary)
	w(`export function ${name}<T extends Flat>(x: T): T {\n\treturn each((x) => ${body}, [x]);\n}`);
for (const [name, body] of [['min', 'Math.min(x, y)'], ['max', 'Math.max(x, y)'], ['pow', 'Math.pow(x, y)']])
	w(`export function ${name}<T extends Flat>(x: T, y: T | number): T {\n\treturn each((x, y) => ${body}, [x, y]);\n}`);
w(`export function step<T extends Flat>(edge: T | number, x: T): T {
	return each((edge, x) => x < edge ? 0 : 1, [edge, x]);
}
export function mix<T extends Flat>(x: T, y: T, a: T | number): T {
	return each((x, y, a) => x + (y - x) * a, [x, y, a]);
}
export function clamp<T extends Flat>(x: T, lo: T | number, hi: T | number): T {
	return each((x, lo, hi) => Math.min(Math.max(x, lo), hi), [x, lo, hi]);
}
export function smoothstep<T extends Flat>(e0: T | number, e1: T | number, x: T): T {
	return each((e0, e1, x) => {
		const t = Math.min(Math.max((x - e0) / (e1 - e0), 0), 1);
		return t * t * (3 - 2 * t);
	}, [e0, e1, x]);
}
export function dot<T extends Vec>(a: T, b: T): number {
	const p = each((a, b) => a * b, [a, b]);
	return p.x + p.y + (p.z ?? 0) + (p.w ?? 0);
}
export function length(a: Vec): number {
	return Math.sqrt(dot(a, a));
}
export function distance<T extends Vec>(a: T, b: T): number {
	return length(each((a, b) => a - b, [a, b]));
}
export function normalize<T extends Vec>(a: T): T {
	const l = length(a);
	return each((a) => a / l, [a]);
}
export function reflect<T extends Vec>(i: T, n: T): T {
	const d = 2 * dot(n, i);
	return each((i, n) => i - n * d, [i, n]);
}
export function cross(a: Vec3, b: Vec3): Vec3 {
	return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
// a texture's colour at uv (the fragment stage: at the mip level its footprint needs)
export function sample(t: Texture2D, uv: Vec2): Vec4 {
	return t.read(uv);
}
// at a mip level (the CPU's textures have one)
export function sampleLevel(t: Texture2D, uv: Vec2, level: number): Vec4 {
	return t.read(uv);
}
// (the fragment dropped: alpha testing; nothing on the CPU)
export function discard(): void {}
// the clip-space position among a vertex stage's varyings, where it builds them
export function position(v: Vec4): Vec4 {
	return v;
}

export function vec2(x: number, y?: number): Vec2 {
	return new Vec2(x, y ?? x);
}
export function vec3(s: number): Vec3;
export function vec3(x: number, y: number, z: number): Vec3;
export function vec3(xy: Vec2, z: number): Vec3;
export function vec3(x: number, yz: Vec2): Vec3;
export function vec3(...a: Flat[]): Vec3 {
	const c = flatten(a);
	return c.length === 1 ? new Vec3(c[0], c[0], c[0]) : new Vec3(c[0], c[1], c[2]);
}
export function vec4(s: number): Vec4;
export function vec4(x: number, y: number, z: number, w: number): Vec4;
export function vec4(xyz: Vec3, w: number): Vec4;
export function vec4(x: number, yzw: Vec3): Vec4;
export function vec4(xy: Vec2, z: number, w: number): Vec4;
export function vec4(xy: Vec2, zw: Vec2): Vec4;
export function vec4(...a: Flat[]): Vec4 {
	const c = flatten(a);
	return c.length === 1 ? new Vec4(c[0], c[0], c[0], c[0]) : new Vec4(c[0], c[1], c[2], c[3]);
}
function flatten(a: Flat[]): number[] {
	const c: number[] = [];
	for (const x of a)
		if (typeof x === "number") c.push(x);
		else if (x instanceof Vec2) c.push(x.x, x.y);
		else if (x instanceof Vec3) c.push(x.x, x.y, x.z);
		else c.push(x.x, x.y, x.z, x.w);
	return c;
}
export function mat4(s: number): Mat4;
export function mat4(c0: Vec4, c1: Vec4, c2: Vec4, c3: Vec4): Mat4;
export function mat4(a: number | Vec4, c1?: Vec4, c2?: Vec4, c3?: Vec4): Mat4 {
	if (typeof a === "number") return new Mat4(new Vec4(a, 0, 0, 0), new Vec4(0, a, 0, 0), new Vec4(0, 0, a, 0), new Vec4(0, 0, 0, a));
	return new Mat4(a, c1!, c2!, c3!);
}

// --- shaders

// a stage's text in the build's languages (only the target's), and what it binds
export type ShaderCode = {glsl?: string, wgsl?: string, msl?: string, hlsl?: string, bindings: {name: string, slot: number, kind: number, size?: number}[]};
export type VertexBufferLayout = {stride: number, attributes: {location: number, format: number, offset: number}[]};
export type UniformBlock = {name: string, binding: number, size: number};
export type TextureBinding = {name: string, binding: number};
export type PipelineOptions = {topology?: number, cull?: number, blend?: number, depthCompare?: number, depthWrite?: boolean};

// a uniform block's writer: its struct's value at offset, std140
export class UniformWriter<T> {
	constructor(readonly block: UniformBlock, private readonly fields: {field: string, kind: string, offset: number}[]) {}
	write(value: T, bytes: Uint8Array, offset = 0): void {
		const d = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
		for (const f of this.fields) {
			const v = (value as any)[f.field];
			if (f.kind === "i") d.setInt32(offset + f.offset, v, true);
			else if (f.kind === "m") {
				const m = v as Mat4, cs = [m.c0, m.c1, m.c2, m.c3];
				for (let c = 0; c < 4; c++) for (let k = 0; k < 4; k++) d.setFloat32(offset + f.offset + 16 * c + 4 * k, (cs[c] as any)[XYZW[k]], true);
			} else store(d, offset + f.offset, v, f.kind);
		}
	}
}
const XYZW = ["x", "y", "z", "w"];
function store(d: DataView, at: number, v: any, kind: string) {
	if (kind === "f") d.setFloat32(at, v, true);
	else for (let k = 0; k < Number(kind); k++) d.setFloat32(at + 4 * k, v[XYZW[k]], true);
}

// a texture parameter's slot (setTexture(slot.binding, ...))
export class TextureSlot {
	constructor(readonly name: string, readonly binding: number) {}
}

// a shader's parameters, the fields of its stages' objects of parameters:
// a writer per uniform block, a slot per texture
export type Params<P> = {readonly [K in keyof P]: P[K] extends Texture2D ? TextureSlot : UniformWriter<P[K]>};
type ParamsOf<R> = R extends [infer P] ? P : {};

export type Shader<V, VS, FS, P> = {
	readonly vertexCode: ShaderCode,
	readonly fragmentCode: ShaderCode,
	readonly layout: VertexBufferLayout[],
	readonly uniforms: UniformBlock[],
	readonly textures: TextureBinding[],
	readonly params: Params<P>,
	readonly vertex: VS,
	readonly fragment: FS,
	pipeline(options?: PipelineOptions): {program: {vertex: ShaderCode, fragment: ShaderCode}, layout: VertexBufferLayout[]} & PipelineOptions,
	vertexBytes(vertices: V[]): Uint8Array,
	// the block of the uniform(...)s the stages read: its slot (-1: none), its bytes with their values now, bound
	readonly uniformBinding: number,
	uniformBytes(): Uint8Array | null,
	bind(encoder: {setUniforms(slot: number, bytes: Uint8Array): void}): void,
};

// a value the CPU sets and the shaders that read it get (uniform(value):
// a module-level const; uniform.value in a stage: Shader.uniformBytes)
export class Uniform<T> {
	constructor(public value: T) {}
}

export function uniform<T>(value: T): Uniform<T> {
	return new Uniform(value);
}

// shader({vertex, fragment}): each stage takes its input and, optionally,
// one object of parameters, its fields uniform blocks and textures
// (fragment: (i, p: {sky: SkyParams, image: Texture2D}) => ...)
/** @definition shader */
export function shader<V, I, VR extends [] | [object], FR extends [] | [object]>(def: {vertex: (v: V, ...p: VR) => I, fragment: (i: I, ...p: FR) => Vec4},
		generated?: string, uniforms?: Uniform<any>[]): Shader<V, (v: V, ...p: VR) => I, (i: I, ...p: FR) => Vec4, ParamsOf<VR> & ParamsOf<FR>> {
	if (generated === undefined) throw new Error("shader: a definition, compiled by helder's compiler (its argument static)");
	const g = JSON.parse(generated);
	const params: {[parameter: string]: UniformWriter<any> | TextureSlot} = {};
	const uniformValues = new Uint8Array(g.uniformBlock ? g.uniformBlock.size : 0);
	for (const b of g.params) params[b.param] = b.texture !== undefined ? new TextureSlot(b.texture.name, b.texture.binding) : new UniformWriter<any>(b.block, b.fields);
	return {
		vertexCode: g.vertexCode,
		fragmentCode: g.fragmentCode,
		layout: g.layout,
		uniforms: g.uniforms,
		textures: g.textures,
		params: params as any,
		vertex: def.vertex,
		fragment: def.fragment,
		pipeline(options?: PipelineOptions) {
			return {program: {vertex: g.vertexCode, fragment: g.fragmentCode}, layout: g.layout, ...(options ?? {})};
		},
		uniformBinding: g.uniformBlock ? g.uniformBlock.binding : -1,
		uniformBytes(): Uint8Array | null {
			if (!g.uniformBlock || uniforms === undefined) return null;
			const values: {[field: string]: any} = {};
			for (let i = 0; i < uniforms.length; i++) values[g.uniformBlock.fields[i]] = uniforms[i].value;
			(params.uniforms as UniformWriter<any>).write(values, uniformValues);
			return uniformValues;
		},
		bind(encoder: {setUniforms(slot: number, bytes: Uint8Array): void}) {
			const b = this.uniformBytes();
			if (b !== null) encoder.setUniforms(g.uniformBlock.binding, b);
		},
		vertexBytes(vertices: V[]): Uint8Array {
			const bytes = new Uint8Array(g.stride * vertices.length);
			const d = new DataView(bytes.buffer);
			for (let i = 0; i < vertices.length; i++)
				for (const a of g.attributes) store(d, i * g.stride + a.offset, (vertices[i] as any)[a.field], a.components === 1 ? "f" : String(a.components));
			return bytes;
		},
	};
}

// slots({vertex, fragment, options, <slot>: ...}): a shader with slots and
// options (src/helder/gfx/shader/Slots.hx). The stages take the object as
// their third parameter (m.options.<name>, m.<slot>(s, p)); variant(options)
// is a definition (compiled at build time: the options folded, the slots
// inlined, what a variant never reads of the optional fields dropped),
// with(slots) the object with some slots replaced, as is {...object, <slot>}
// given to slots(...).
type Stage<F> = F extends (i: infer I, p: infer P, m: any) => infer R ? (i: I, p: P) => R : never;
type InputOf<F> = F extends (i: infer I, ...rest: any[]) => any ? I : never;
type ParamsOfStage<F> = F extends (i: any, p: infer P, ...rest: any[]) => any ? P : {};
// (an override's own parameters join the variants': X, their intersection)
type Intersect<U> = (U extends any ? (x: U) => void : never) extends (x: infer I) => void ? I : never;
type SlotParams<O> = Intersect<{[K in keyof O]-?: O[K] extends (s: any, p: infer P) => any ? P : {}}[keyof O]>;
export type SlotsDef = {options: object, vertex: (v: any, p: any, m: any) => any, fragment: (i: any, p: any, m: any) => Vec4};
export type Slots<D extends SlotsDef, X = {}> = D & {
	variant(options?: Partial<D["options"]>): Shader<InputOf<D["vertex"]>, Stage<D["vertex"]>, Stage<D["fragment"]>, ParamsOfStage<D["vertex"]> & ParamsOfStage<D["fragment"]> & X>,
	with<O extends {[K in Exclude<keyof D, "vertex" | "fragment" | "options">]?: (s: any, p: any) => any}>(slots: O): Slots<D, X & SlotParams<O>>,
};

export function slots<D extends SlotsDef>(def: D): Slots<D> {
	return {
		...def,
		variant(options?: any, generated?: any, uniforms?: any): any {
			// (the handler's output: after the options, when they are given; the uniforms' objects after it)
			if (typeof options === "string") {
				uniforms = generated;
				generated = options;
				options = undefined;
			}
			if (generated === undefined) throw new Error("slots: a variant is a definition, compiled by helder's compiler (the object and its options static)");
			const m = {...def, options: {...def.options, ...(options ?? {})}};
			return shader({vertex: (v: any, p: any) => def.vertex(v, p, m), fragment: (i: any, p: any) => def.fragment(i, p, m)}, generated, uniforms);
		},
		with(over: any): any {
			return slots({...def, ...over});
		},
	};
}
`);
const text = out.join('\n');
const file = new URL('./index.ts', import.meta.url);
if (process.argv.includes('--check')) {
	if (fs.readFileSync(file, 'utf8') !== text) {
		console.error('src/helder/gfx/index.ts is not as typescript.mjs writes it: node src/helder/gfx/typescript.mjs');
		process.exit(1);
	}
} else fs.writeFileSync(file, text);
