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
	fragment: (i, p: {sky: SkyParams}) => vec4(color(i, p.sky), 1),
});
```

```haxe
final Sky = shader({
	vertex: (v:{pos:Vec2}) -> ({clip: vec4(v.pos, 0.9999, 1), ndc: v.pos}),
	fragment: (i, p:{sky:SkyParams}) -> vec4(color(i, p.sky), 1),
});
```

- **It reads as runtime code.** It is an ordinary call with an ordinary typed
  result. Both checkers (tsgo, Haxe's typer) see a generic function:
  `shader<V, I, P>(def: {vertex: (v: V) => I, fragment: (i: I, p: P) => Vec4}): Shader<V, I, P>`.
  `I` is inferred from what the vertex function returns, and
  `Sky.params.sky.write(...)` is checked against `P`.
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
   - **TS:** by its import. A call of a name imported from one of helder's
     modules that declares definitions (`helder/gfx`'s `shader`,
     `helder/dev`'s `keep`, `helder/story`'s `story`, `helder/jobs`'s `job`,
     `helder/asset`'s `image`, `font`, ...: `lower/Definitions.hx`'s table)
     is one, and so is `<object>.variant(...)` of a slot object
     (`helder/gfx`'s `slots`). The API manifest does not mark them: a
     module's own TypeScript (`helder/gfx`) has no manifest entry, and the
     import is what tsgo has already resolved. The TS lowering runs the TS
     adapter, calls the same handler, and passes what it made to the
     function as its last argument (JSON), or lowers the call to what it
     stands for (keep's slot, an asset's handle, a job).
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
	fragment: (i, p: {sky: SkyParams}) => {
		const far = p.sky.invViewProj.mul(vec4(i.ndc, 1, 1));
		const d = normalize(far.xyz.div(far.w).sub(p.sky.eye.xyz));
		return vec4(mix(p.sky.horizon.xyz, p.sky.zenith.xyz, pow(clamp(d.y, 0, 1), 0.5)), 1);
	},
});

device.createPipeline(Sky.pipeline({blend: "alpha"}));
Sky.params.sky.write({invViewProj, eye, horizon, zenith}, bytes);   // std140
Sky.vertexBytes([{pos: vec2(0, 0)}, ...]);
```

**Stages:**
- `vertex` takes a vertex, whose fields are the buffer's attributes in
  order, and returns the varyings.
- `position(x)` marks the clip-space position among the varyings. It
  replaces `@:position`.
- `fragment` takes the varyings and returns a colour, or a struct for
  multiple render targets.
- `compute` is deferred: helder.gfx has no compute pipelines yet (a
  separate helder.gfx project). When it has, it is a field with its
  workgroup size: `shader({compute: ..., workgroup: [8, 8, 1]})`.

**Parameters:** a stage takes one object of parameters after its input,
`(i, p: {sky: SkyParams, image: Texture2D})`. Its fields are uniform blocks
(structs) and textures (`Texture2D`), with slots in order of appearance;
the adapters flatten it into the stage's parameters, in field order, so
the text is what separate parameters printed.

**Result:** the generated value carries:

| Member | What it is |
|---|---|
| `vertexCode`, `fragmentCode` | the shader text in the target's languages (`-D helder.gfx.shaders`) |
| `layout` | the vertex buffer layout |
| `uniforms`, `textures` | the uniform blocks and textures, with their slots |
| `pipeline(options)` | a `PipelineDesc` built from the above |
| `vertexBytes(vertices)` | the vertex buffer's contents |
| `params` | a member per field of the stages' parameters: a uniform block's writer (`params.sky.write(value, bytes, offset)`), a texture's slot (`params.image.binding`); TS types it `{[K in keyof P]: P[K] extends Texture2D ? TextureSlot : UniformWriter<P[K]>}` |

**Shared functions:** a plain function that only uses the math types can be
called from any stage, from a module or from another definition. The handler
compiles each one once per shader, by name. A function the handler can't
compile fails at the caller's line.

**Operators:** Haxe has `*`, `+`, `-` and `/` on the math types
(abstracts' operator overloading). TypeScript has `.mul`, `.add`, `.sub`
and `.div`, and keeps them: a TS program stays valid for TypeScript's own
checker and editors, with nothing rewritten before checking, and
operators in TS are not planned.

### Built-ins and names

Built-ins keep WGSL's and TSL's names, so examples carry over:

- math: `mix`, `smoothstep`, `step`, `clamp`, `saturate`, `fract`;
- vectors: `normalize`, `dot`, `cross`, `length`, `reflect`;
- textures: `sample(t, uv)`;
- swizzles: `.xyz`, `.rgb`.

### Material slots (from Three.js's TSL)

Extending the standard material should not mean rewriting it. A shader
with **slots** is a slot object: `slots({vertex, fragment, options,
<slot>: ...})` (helder/gfx, `helder.gfx.shader.Slots`), whose slots are
functions a caller may replace, each with a default.

```ts
export const lit = slots({
	options: {tinted: false},
	vertex: (v: Vertex, p: {view: View}, m: Lit): Varyings => ...,
	fragment: (i: Varyings, p: LitParams, m: Lit) => {
		const s: Surface = {uv: i.uv, base: vec3(i.uv, 1)};
		return vec4(m.color(s, p).add(m.emissive(s, p)), 1);   // the slots
	},
	color: baseColor,     // a module-level function: (s: Surface, p: {tint: Tint}) => Vec3
	emissive: noLight,
});

export const Glow = lit.with({
	emissive: (s: Surface, p: {time: Time}) => vec3(0.2, 0.6, 1).mul(sin(p.time.seconds.x) * 0.5 + 0.5),
}).variant({tinted: true});
```

- **The object:** the stages take it as their third parameter, `m`:
  `m.<slot>(s, p)` calls a slot, `m.options.<name>` reads an option. Its
  type is the program's (a structure of the options and the slots'
  function types), so both checkers type the stages as plain code.
- **Slots:** a slot takes its input and, optionally, an object of
  parameters of its own. Its fields are the stage's parameters of the same
  names (the material's block, its textures); the others join the shader's
  uniform blocks and textures after the stage's (a block of the
  material's own: `Glow.params.time`).
- **Overriding:** `lit.with({emissive: ...})` in both languages (Haxe has
  no object spread); TypeScript also spreads it, `slots({...lit,
  emissive: ...})`. A replaced slot's input type is the object type's when
  not written.
- **helder.scene:** the standard material is one, `pbr` (slots `color`,
  `alpha`, `normal`, `roughness`, `metalness`, `emissive`, of the
  fragment's surface; `position`, of the vertex's point).
  `MaterialShader.material(pbr.with({...}))` produces the material's own
  shaders with the slots inlined (every variant the renderer draws with)
  and the material type helder.scene renders with (`material.shader`, its
  own blocks in `material.uniforms`). examples/glow replaces two slots.
  helder.scene has no TypeScript declarations yet, so `pbr` and `material`
  are Haxe's; TypeScript's slot objects are its own (the parity case:
  tests/typescript/definitions/glow.ts).

### Variants

A slot object's options are plain fields with static values:

```ts
const Lit = pbr.variant({normalMap: true, instanced: true});
```

- A variant is a definition: compiled at build time, a `Shader`.
- Inside it, a test of an option (`if (m.options.normalMap)`, a ternary, `!`,
  `&&`, `||`, comparisons) is folded, so each variant compiles only what
  it uses.
- A `for` over compile-time constants is unrolled (in Haxe the typer's
  form of `for (k in 0...n)`, in TS `for (let k = a; k < b; k++)`), its
  variable a constant in each copy.
- What a variant never reads of the **optional** fields is dropped: the
  vertex's (its attributes), the varyings' (with the values the vertex
  stage built them from), the stages' parameters'. helder.scene's pbr has
  one combined vertex, `{pos, normal, uv, ?tangent, ?joints, ?weights,
  ?m0, ..., ?m3}`, laid out as each variant reads it: the five standard
  variants and the shadow casters' three have the layouts, uniform blocks
  and slots the hand-written shaders had, and the scenes' frames are the
  same pixels.
- On the CPU a variant's stages are the object's with the options and
  slots inlined (Haxe: static functions of a module made with the object's
  module's imports, as hxmc calls functions of struct values by their
  exact types; an override with parameters of its own runs on the GPU
  only). The object itself is nothing at run time in Haxe.

This covers what TSL gets from running JavaScript to build its graph,
without a compiler at run time.

### Inferred uniforms (optional sugar)

```ts
export const time = uniform(0);     // a uniform value, set from the CPU: time.value = t
const Pulse = shader({vertex: ..., fragment: (i) => vec4(sin(time.value), 0, 0, 1)});
```

A shader that reads a `uniform(...)`'s `value` (a module-level constant,
here or imported) gets that value in a generated uniform block,
`Uniforms`, a field per uniform in the order they are first read, a
parameter of the stages that read it (`params.uniforms`, after the
others). `Pulse.uniformBytes()` is the block of the uniforms' current
values, `Pulse.bind(encoder)` binds it at its slot. This sits beside the
explicit params form, not instead of it; on the CPU the stages read the
value itself.

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
- `keep` is `helder.dev.Keep`'s in Haxe, `helder/dev`'s in TS:
  `keep(key, () => initial)`, a key literal and a function of no
  arguments (rejected otherwise, with the same diagnostic in both
  languages: a key that is not static or empty, an initialiser that takes
  arguments). Its slot is a signal's: the key in Hot's
  scope, the value's type hashed (Haxe) or its written type argument (TS),
  the initial value's source hashed (an edit to it starts afresh, said
  so); `helder dev` keeps the value across a reload, and a build that is
  not a dev build is `initial()`. `Hot.keep` is gone. `Hot.save`, `load`
  and `onSnapshot` stay as the state libraries' primitives (signals,
  helder.scene's HotWorld): a program writes `keep`.
- `story` is `helder.story.Story`'s in Haxe, `helder/story`'s in TS:
  `story({name, render, seed, store, caption, ...})`, its fields checked
  where it is written (static ones static, a seed an integer literal, a
  caption a store screenshot's). A story file's stories are its module-level values
  (`Stories.of(module)`); `helder publish --dry-run` and the extension list
  them, `store: true` marks a store screenshot. A release build is `-D
  helder.release` (helder build's), where the call is null and its
  argument is not compiled.
- `job` is `Jobs.job`'s in Haxe, `helder/jobs`'s in TS. One handler,
  `JobDefinition`, checks the input, the result and the constants the
  function reads (TS's: a worker's instance does not run the program's
  module, so they are sent with the input) against each adapter's
  description of its types (`SendType`). In both languages the function is
  a module-level one, named. In TS it returns `Job<In, Out>`, `run(x)` a
  promise; the worker calls the program's function by its number
  (`helder.jobs.script.Entry.call`, written by the lowering).
- `image`, `font`, `model`, `sound`, `bytes` are `Asset.*` in Haxe,
  `helder/asset`'s in TS (one check, `AssetCheck`); TS's import of a file
  with a type is the same definition. TS bundles a program's assets when
  its build starts (`TsAssets`), as `AssetMacro` does from the macro.
| `uniform(value)` | a value | A uniform the shaders that read it bind (see §3). |

Markup (TSX and Haxe markup) already shares its planner and stays as it is.
A definition may contain markup; `story`'s `render` does.

### Writing a new definition

A handler is a Haxe class in helder or in a library. In Haxe,
`@:definition` sits on its forwarding `macro` function. In TS a
definition is recognised by its import (2): its module and name join
`lower/Definitions.hx`'s table, with the TS adapter's call of the
handler.

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
3. **The TS adapter and `shader` in TS:** a definition is recognised by
   its import, and `helder.typescript.lower` runs the TS adapter. A TS sky shader and a
   TS sprite example must produce byte-identical shader text to the Haxe
   ones.
4. **`job`, `image` and the asset definitions, `actions`, `keep`, `story`:**
   each replaces its macro and moves its users over.
5. **Material slots and variants:** `pbr` as a slot object, plus `material`
   and `variant`. The standard scenes' goldens are unchanged. (Done: and
   before it, each stage's parameters as one object, `(i, p: {...})`.)
6. **`uniform` sugar.** (Done.) `compute` waits on compute pipelines in
   helder.gfx. TS keeps the math's methods (no operators, by decision).
7. **`actions`**, which waits on its design.

Tests:
- the gfx-shader lane, comparing shader text before and after;
- the scene goldens;
- the typescript lane's cases, plus a `definitions/` folder: each definition
  in both languages, built natively and as wasm, with matching output and
  matching diagnostics for rejected arguments;
- the jobs, asset and actions lanes.
