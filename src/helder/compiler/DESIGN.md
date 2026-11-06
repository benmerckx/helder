# Definitions: compile-time calls that read as runtime code

A design for helder's macros that reads the same in TypeScript and in Haxe
and compiles through one implementation. It replaces the macro forms in use
today (`class X implements Shaders`, `@:vertex`, `@:fragment` and
`@:position`, the `Asset.*` macros, the Sendable checks behind `Jobs.run`).
There is no backwards compatibility: helder's own code moves over, and the
old forms are removed.

## 1. The idea

A **definition** is a call to a helder function marked as compile-time. Its
argument is a plain object literal of fields and arrow functions:

```ts
export const Sky = shader({
	vertex: (v: {pos: Vec2}) => ({clip: vec4(v.pos, 0.9999, 1), ndc: v.pos}),
	fragment: (i, sky: SkyParams) => vec4(color(i, sky), 1),
});
```

```haxe
final Sky = shader({
	vertex: (v:{pos:Vec2}) -> ({clip: vec4(v.pos, 0.9999, 1), ndc: v.pos}),
	fragment: (i, sky:SkyParams) -> vec4(color(i, sky), 1),
});
```

- **It reads as runtime code.** It is an ordinary call with an ordinary typed
  result. Both checkers (tsgo, Haxe's typer) see a generic function:
  `shader<V, I, P>(def: {vertex: (v: V) => I, fragment: (i: I, p: P) => Vec4}): Shader<V, I, P>`.
  `I` is inferred from what the vertex function returns, and
  `Sky.params.write(...)` is checked against `P`.
- **The compiler evaluates it at build time.** It finds the call and checks
  that the argument is static. It hands the argument to the definition's
  handler, then replaces the call with what the handler generates.
- **Types are the schema.** We compile TypeScript ourselves, so the checked
  types exist at build time. `{pos: Vec2}` on a parameter *is* the vertex
  layout. There are no runtime schema objects (unlike TypeGPU's `d.struct`).
- **Shader functions still run on the CPU as they are.** The math types are
  real types with CPU implementations, as `ShaderMath` already provides, so a
  shader function can be unit-tested by calling it.

### What "static" means

A definition's argument may contain:
- literals;
- object and array literals;
- arrow functions;
- references to module-level constants;
- references to other definitions;
- calls to other definitions;
- calls to functions the handler accepts (for a shader: other shader
  functions and the built-ins).

Anything else is an error at the user's line, naming what is not allowed
("a shader cannot call `trace`", "a job cannot capture `window`: it is not
Sendable"). A definition usually sits at module level as a `const`/`final`.
A definition inside a function is allowed when its argument is still static:
it is hoisted, and made once.

## 2. One compiler for both languages

Markup sets the precedent: one planner, `Plan<E>`, with a small target per
language. Definitions do the same:

```
Haxe typed expr ─► Haxe adapter ─┐
                                 ├─► kernel AST ─► handler (shader, job, …) ─► generated code
TS checked node ─► TS adapter  ──┘
```

1. **The kernel AST** is the typed subset handlers need:
   - locals;
   - arithmetic and comparisons;
   - calls;
   - field and swizzle access;
   - `if`, ternaries, `for` and `while` over integers, `return`;
   - struct literals.

   Each node carries its type: scalar, vector, matrix, struct, texture,
   string, or a reference to a definition. For shaders this is
   `helder.gfx.shader.Ir`, generalised. `Lower.hx` becomes the Haxe adapter
   (from macro `TypedExpr`).
2. **Two adapters**, each covering only the kernel subset:
   - the **Haxe adapter**, from typed expressions, today's `Lower`;
   - the **TS adapter**, from tsgo's checked AST inside
     `helder.typescript.lower`.

   Both report anything outside the subset at its source position, in the
   compiler's usual diagnostics.
3. **One handler per definition**, written once in Haxe, running inside
   helder's compiler. A handler takes the kernel AST of the argument and
   returns:
   - the generated module-level value: fields, methods, data;
   - any extra outputs (shader text per back end, asset files).
4. **Recognising a call:**
   - **Haxe:** the function is a `macro` function, a thin forwarder that runs
     the Haxe adapter on its argument, calls the handler, and returns the
     generated expression.
   - **TS:** the API manifest (made from the Haxe types, as today) marks the
     function as a definition. The TS lowering then runs the TS adapter and
     calls the same handler, and lowers the generated value into the IR, as
     it lowers a manifest call today.
5. **Why not an hxmc IR pass:** by IR time, abstracts such as `Vec4` and
   their swizzles are inlined and lambdas are closure-converted. A shader's
   meaning is mostly gone by then. Adapters keep types and structure intact.
6. **Eval:** the interpreter target types Haxe with macros, so the Haxe path
   works there unchanged. TS programs don't run on Eval.

## 3. Shaders

```ts
import {shader, vec4, mix, normalize, pow, clamp, type Vec2, type Vec4, type Mat4} from "helder/gfx";

type SkyParams = {invViewProj: Mat4, eye: Vec4, horizon: Vec4, zenith: Vec4};

export const Sky = shader({
	vertex: (v: {pos: Vec2}) => ({clip: position(vec4(v.pos, 0.9999, 1)), ndc: v.pos}),
	fragment: (i, sky: SkyParams) => {
		const far = sky.invViewProj.mul(vec4(i.ndc, 1, 1));
		const d = normalize(far.xyz.div(far.w).sub(sky.eye.xyz));
		return vec4(mix(sky.horizon.xyz, sky.zenith.xyz, pow(clamp(d.y, 0, 1), 0.5)), 1);
	},
});

device.createPipeline(Sky.pipeline({blend: "alpha"}));
Sky.params.write({invViewProj, eye, horizon, zenith}, bytes);   // std140
Sky.vertexBytes([{pos: vec2(0, 0)}, ...]);
```

**Stages:**
- `vertex` takes a vertex, whose fields are the buffer's attributes in
  order, and returns the varyings.
- `position(x)` marks the clip-space position among the varyings. It
  replaces `@:position`.
- `fragment` takes the varyings and returns a colour, or a struct for
  multiple render targets.
- `compute` comes later, with workgroup size as a field:
  `shader({compute: ..., workgroup: [8, 8, 1]})`.

**Parameters:** a stage's further parameters are uniform blocks (structs) and
textures (`Texture2D`), with slots in order of appearance, as today.

**Result:** the generated value carries:

| Member | What it is |
|---|---|
| `vertexCode`, `fragmentCode` | the shader text in the target's languages (`-D helder.gfx.shaders`) |
| `layout` | the vertex buffer layout |
| `uniforms`, `textures` | the uniform blocks and textures, with their slots |
| `pipeline(options)` | a `PipelineDesc` built from the above |
| `vertexBytes(vertices)` | the vertex buffer's contents |
| `params.write(value, bytes, offset)` | one writer per uniform block, named after its parameter (`sky.write`) |

**Shared functions:** a plain function that only uses the math types can be
called from any stage, from a module or from another definition. The handler
compiles each one once per shader, by name. A function the handler can't
compile fails at the caller's line.

**Operators:** Haxe keeps `*`, `+`, `-` and `/` on the math types
(abstracts). TypeScript starts with `.mul`, `.add`, `.sub` and `.div`. A later
step lowers `a * b` in TS when both operands are Vec or Mat types. Our TS
frontend knows the types, but tsgo will reject `*` on objects unless the
declarations allow it, so this needs a decision on how to type it then.

### Built-ins and names

Built-ins keep WGSL's and TSL's names, so examples carry over:

- math: `mix`, `smoothstep`, `step`, `clamp`, `saturate`, `fract`;
- vectors: `normalize`, `dot`, `cross`, `length`, `reflect`;
- textures: `sample(t, uv)`;
- swizzles: `.xyz`, `.rgb`.

### Material slots (from Three.js's TSL)

Extending the standard material should not mean rewriting it. The PBR
shader becomes a definition with **slots**: partial functions a caller may
override, each with a default.

```ts
export const Glow = material({
	...pbr,
	color: (s) => s.baseColor.mul(1.5),
	emissive: (s, p: {time: number}) => vec3(0.2, 0.6, 1).mul(sin(p.time).mul(0.5).add(0.5)),
	position: (v) => v.position.add(v.normal.mul(0.02)),
});
```

- **Slots:** `pbr` is an object of slot functions (`color`, `normal`,
  `roughness`, `metalness`, `emissive`, `alpha`, `position`). Spreading it
  and overriding some is plain object syntax in both languages.
- **Parameters:** a slot's extra parameters join the material's uniform
  blocks.
- **Generated material:** `material(...)` produces a full shader with the
  slots inlined, plus the material type helder.scene renders with.
- **Haxe:** `{...pbr, color: s -> ...}` is the same with Haxe's object spread.
  Where Haxe can't spread a typed object literal, use the struct-with-defaults
  equivalent, `pbr.with({color: ...})`.

### Variants

A definition can take options, which are plain fields with static values:

```ts
const Lit = pbr.variant({normalMap: true, skinned: false, instanced: true});
```

- Inside a shader, a test of an option (`if (opts.normalMap)`) is folded at
  build time, so each variant compiles only what it uses.
- A `for` over a compile-time constant is unrolled.

This covers what TSL gets from running JavaScript to build its graph,
without a compiler at run time.

### Inferred uniforms (optional sugar)

```ts
const time = uniform(0);     // a uniform value, set from the CPU: time.value = t
const Pulse = shader({fragment: (i) => vec4(sin(time.value), 0, 0, 1)});
```

A shader that reads a `uniform(...)` definition gets that value in a
generated uniform block, filled from the definition at draw
(`Pulse.bind(encoder)`). This sits beside the explicit params form, not
instead of it.

### Compared with TSL

| | TSL (Three.js) | helder definitions |
|---|---|---|
| When it compiles | in the browser, when first used, by tracing the JS that runs | at build time; the shader text is shipped |
| Control flow | `If()`, `Loop()`, `select()`, `.toVar()` | plain `if`, `for`, ternaries, locals |
| Types | loose; errors appear in the generated WGSL at run time | fully checked; errors at the source line |
| Uniforms | inferred | explicit, or inferred via `uniform(...)` |
| Composition | node functions in material slots | functions, material slots, variants |
| Back ends | WebGPU, WebGL | GL, D3D, Metal, Vulkan, web; native or wasm |
| Run-time cost | the node system and the code generator ship | none beyond the shader text and writers |

## 4. The other definitions

| Definition | Argument | What the handler does |
|---|---|---|
| `job(fn)` | `(input: In) => Out`, or a module-level function | Checks the function's captures and its input and output types are Sendable (the rules of today's `helder.jobs.Sendable`). Generates the message types and the worker entry, and returns a `Job<In, Out>`. `await Decode.run(req)` in TS is `Decode.run(req)` in a Haxe coroutine. Replaces `Jobs.run(f, x)`'s macro and the `helder.jobs.gen.*` types. |
| `image(path)`, `font`, `model`, `sound`, `bytes(path)` | a path literal relative to the file | Resolves and bundles the asset as `Asset.*` does today, and returns the typed handle. TS may also write `import icon from "./icon.png" with {type: "image"}`, which is the same definition. |
| `actions(namespace, {...})` | an object whose keys are action names and whose arrow functions give the arguments: `{next: () => {}, zoomTo: (percent: number) => {}}` | Generates the action type: an enum in Haxe, a tagged union in TS. Also generates the keymap names (`viewer::ZoomTo`) and the JSON argument readers. Replaces the enum plus `Actions.declare` pair. The bodies are ignored; the parameters are what count. |
| `story({name, render, seed, store, caption, ...})` | the story's fields | Registers the story for `helder publish --dry-run` and the extension, and drops it from release builds. |
| `keep(key, () => initial)` | a key literal and an initialiser | Generates a dev-reload slot, replacing `Hot.keep` and `Hot.save`. |

As built (step 4):
- `keep` is `helder.dev.Keep`'s in Haxe, `helder/dev`'s in TS. Its slot is
  a signal's: the key in Hot's scope, the value's type hashed (Haxe) or
  its written type argument (TS), the initial value's source hashed (an
  edit to it starts afresh, said so). `Hot.keep` is gone. `Hot.save`,
  `load` and `onSnapshot` stay as the state libraries' primitives (signals,
  helder.scene's HotWorld): a program writes `keep`.
- `story` is `helder.story.Story`'s in Haxe, `helder/story`'s in TS. A
  story file's stories are its module-level values (`Stories.of(module)`);
  `store: true` marks a store screenshot. A release build is `-D
  helder.release` (helder build's), where the call is null.
- `job` is `Jobs.job`'s in Haxe, `helder/jobs`'s in TS. One handler,
  `JobDefinition`, checks the input, the result and the constants the
  function reads (TS's: a worker's instance does not run the program's
  module, so they are sent with the input) against each adapter's
  description of its types (`SendType`). In both languages the function is
  a module-level one, named. In TS it returns `Job<In, Out>`, `run(x)` a
  promise; the worker calls the program's function by its number
  (`helder.jobs.script.Entry.call`, written by the lowering).
| `uniform(value)` | a value | A uniform the shaders that read it bind (see §3). |

Markup (TSX and Haxe markup) already shares its planner and stays as it is.
A definition may contain markup; `story`'s `render` does.

### Writing a new definition

A handler is a Haxe class in helder or in a library, registered with
`@:definition`. In Haxe, `@:definition` sits on its forwarding `macro`
function, which is enough for the TS manifest to mark it too.

```haxe
class ShaderDefinition implements Definition<ShaderDef, ShaderValue> {
	public function check(arg:Kernel.Object):Void ...      // diagnostics at source positions
	public function generate(arg:Kernel.Object):Generated ... // the value, outputs
}
```

Libraries can then add their own: an SQL query checked against a schema, a
route table, a state machine.

## 5. Plan

Each step is one or more commits, each keeping CI green. Old forms are
removed in the same step that replaces them.

1. **The kernel AST:** generalise `helder.gfx.shader.Ir` so a handler can
   take an object literal's fields, functions, constants and strings. Then
   `Definition<A, V>` and the Haxe forwarding pattern.
2. **`shader` in Haxe:**
   - `shader({...})` replaces `implements Shaders`, using the existing
     `Lower` as the Haxe adapter and the existing emitters;
   - every helder shader moves over: ui, scene, sprite, canvas.gpu, the
     examples;
   - the generated GLSL, WGSL, MSL and HLSL must be byte-identical to
     today's for each migrated shader (the gfx-shader lane);
   - then `Shaders`, `Macro` and the metadata go.
3. **The TS adapter and `shader` in TS:** the manifest marks definitions,
   and `helder.typescript.lower` runs the TS adapter. A TS sky shader and a
   TS sprite example must produce byte-identical shader text to the Haxe
   ones.
4. **`job`, `image` and the asset definitions, `actions`, `keep`, `story`:**
   each replaces its macro and moves its users over.
5. **Material slots and variants:** `pbr` as a slot object, plus `material`
   and `variant`. The standard scenes' goldens are unchanged.
6. **`uniform` sugar, `compute`, and TS operators** on the math types.

Tests:
- the gfx-shader lane, comparing shader text before and after;
- the scene goldens;
- the typescript lane's cases, plus a `definitions/` folder: each definition
  in both languages, built natively and as wasm, with matching output and
  matching diagnostics for rejected arguments;
- the jobs, asset and actions lanes.
