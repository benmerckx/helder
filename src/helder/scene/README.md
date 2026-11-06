# helder.scene

A scene layer for 3D games on `helder.gfx`, in pure Haxe (Haxe package
`helder.scene`; what comes next: the README's roadmap). It is ordinary gfx
code: use the parts you want, replace the rest.

## Math

gfx's shader types (`Vec2`, `Vec3`, `Vec4`, `Mat4` of `helder.gfx.shader`)
are the CPU's types too, so what the CPU computes is what a shader reads.
3d adds, as immutable values like them:

- `Quat`: a unit quaternion (`axisAngle`, `fromEuler`, `fromMat4`, `*`,
  `rotate`, `toMat4`, `slerp`, `conjugate`);
- `Aabb`: an axis-aligned box (`union`, `transform`, `contains`,
  `intersects`, `ray`);
- `MathTools`, a static extension of `Mat4` (`using
  helder.scene.math.MathTools`): `inverse`, `transpose`, `determinant`,
  `compose(t, r, s)`, `decompose`, `lookAt`, `lookRotation`,
  `transformPoint`, `transformDir`, `normalMatrix`.

## World

A `World` is a scene graph of `Node`s: handles (an `Int`: the world, a
generation, a slot) over flat arrays of transforms, so nodes cost no
object each and a disposed node's handle is stale (`valid` false).

```haxe
var world = new World();
var arm = world.node("arm");                 // under world.root
arm.position = new Vec3(2, 0, 0);            // Vec3 and Quat: immutable values
arm.rotation = Quat.axisAngle(new Vec3(0, 0, 1), Math.PI / 2);
var hand = world.node("hand", arm);
var eye = world.node("eye");
var camera = Camera.attach(eye, Camera.perspective(Math.PI / 3, 0.1, 100));
eye.position = new Vec3(4, 3, 6);
eye.lookAt(new Vec3(0, 1, 0));
var mvp = camera.viewProjection(width / height) * hand.worldMatrix();
```

A node's `worldMatrix()` is cached until a transform above it changes.
What nodes carry is in typed stores (`world.store(kind)`, a `StoreKind`
per kind: `Camera.KIND`, `MeshRenderer.KIND`, `Light.KIND`), made when
first used. `FixedStep` runs a simulation at a fixed rate from the app
loop's frames and gives the fraction between the last two steps; `Stages` runs a frame's work in
ordered stages (`Input`, `FixedUpdate`, `Update`, `LateUpdate`, `PreRender`).

## glTF

`Gltf.parse(bytes, ?resolve)` reads glTF 2.0, .gltf (buffers as `data:`
URIs or files `resolve` returns) and .glb, into a `GltfDoc`: typed and
checked data (indices in range, views inside buffers, accessors inside
views). `doc.floats(accessor)` and `doc.indices(accessor)` read accessors of
any component type, normalized or strided. Materials' extensions:
KHR_texture_transform (one transform for a material's maps: the base
colour's, else the first one's), KHR_materials_emissive_strength,
KHR_materials_clearcoat (its factor and roughness) and
KHR_materials_transmission (its factor); alphaMode MASK is cut out at
alphaCutoff. `GltfNodes.build(doc, world, ?parent, ?scene, ?mesh)` makes the node
hierarchy (TRS or matrices, cameras); `GltfScene` makes the GPU meshes and
materials once and `instantiate(world)` copies the hierarchy into a world.
helder.asset's `Asset.embed(path)` builds a file into the code itself.

## Models

```haxe
var hero = Model.of("models/hero.glb");      // checked and typed when compiling
var root = hero.instantiate(world, device);  // GPU meshes made once, shared
var hand = root.find(hero.nodes.LeftHand);   // hero.nodes.LeftHnad: a compile error
```

`Model.of` reads the file's names when compiling (nodes, meshes,
materials, animations: `model.nodes`, ...). Its path is an asset's
(src/helder/asset/README.md): found under a class path or the project,
checked when compiling, the file in every build that still uses it (the
executable's data, the APK's or the app's `assets/`, beside the page), read
before anything runs (in the browser fetched before main: `browser.mjs`'s
`assets` option, `<module>.assets.json`). For now self-contained files only (one embedded
buffer, images inside it). Textures need a decoder, named by
the program so that none is linked otherwise (`helder.image`'s; a glTF
viewer natively: 805 KB without one, 1.1 MB with PNG, JPEG and WebP):

```haxe
Images.decode = Images.png;     // PNG only
Images.decode = Images.common;  // PNG, JPEG and WebP
```

## The asset step

```sh
haxe -cp src \
  --run helder.scene.gltf.Pack level.glb level.hxm3d
```

```haxe
PackedModel.read(Asset.embed("level.hxm3d"), device).instantiate(world);
```

A packed model needs no glTF reader or JSON at run time (73 KB less
natively, `tests/3d/size/sizes.sh`): meshes (vertices in the renderer's layout,
joints and weights, tangents computed at build time for normal maps),
materials (factors, maps, sampler, the extensions' fields), images (decoded by `Images.decode`
when loaded), cameras, lights, skins, morph targets, animations (`model.clip(name)`,
playing on the nodes `instantiate` made) and the hierarchy.

`--textures bc` or `--textures astc` compresses the images for a target's
GPUs (BC1, BC3 with alpha: desktops and the web; ASTC 4x4: phones), their
mip chains made at build time (helder.image's `BlockCompress`):
`PackedModel` uploads the levels as they are (`Images.compressed`), or on a
GPU without the format (`Device.supports`) decodes them on the CPU.
Sponza's 69 textures: 363 MB on the GPU as RGBA8, 50 MB as BC, 95 MB as
ASTC (examples/sponza). Built natively, the step packs them in seconds.

Big files or loading screens: `Asset.model(path)` (or `Model.of(path,
Lazy)`) is an `Asset` of the same typed model, loaded in the background
(`var hero = Asset.model(path).load();` in a coroutine; `asset.ready`,
`asset.peek()` in the frame loop); under `helder dev` a change to the file
is loaded again into the same `Model` (`replace`: each mesh's primitives
and materials swapped in the mesh objects its instances draw; their nodes,
morphs and skins as they were made). `Model.load(path)` loads a path known
only at run time (not bundled). Loads advance on the main thread's loop
(`App.run`), or in `Assets.poll()`, which `Stages.frame` calls.

## Animation

```haxe
var made = [];
var root = hero.instantiate(world, device, null, made);   // made: the glTF nodes by index
var animator = new Animator(made);
animator.play(hero.clip(hero.animations.Run), {loop: true, fade: 0.2});
// each simulation step:
animator.update(dt);
```

Clips are glTF's keyframes (translation, rotation, scale; step, linear,
cubic spline). Skinned glTF meshes deform with their joints (a `Skin` per
instance, joint matrices in a texture); `tests/3d/skinned.glb` is a
generated two-joint sample.

## Input

```haxe
var actions = new InputMap();
actions.bind("jump", Key(0x20)).bind("jump", Region(0.75, 0.5, 1, 1));   // Space, or the screen's lower right
actions.bind("moveX", KeyAxis(0xFF51, 0xFF53));                         // the arrows
App.run(frame, e -> actions.event(e));
// each simulation step:
actions.step();
if (actions.pressed("jump")) ...;
var x = actions.axis("moveX");
```

Fingers are actions too, through on-screen controls that are virtual
devices (Unity's on-screen controls): gameplay reads the same actions as
for keys and pads.

```haxe
final move = new VirtualStick({zone: Zone.rect(0, 0.4, 0.5, 1), radius: 60, deadZone: 0.1});   // floating: where the thumb lands
final fire = new VirtualButton({zone: Zone.circle(0.88, 0.8, 40)});                            // radius in points
actions.bind("moveX", Stick(move, 0)).bind("moveX", KeyAxis(0x61, 0x64)).bind("moveX", PadAxis(0, 1));
actions.bind("lookX", TouchDelta(0, Zone.rect(0.5, 0, 1, 1), 0.3)).bind("lookX", PadAxis(2, 1));
actions.bind("fire", Button(fire)).bind("fire", PadButton(7)).bind("grab", Touch(Zone.rect(0, 0, 0.5, 0.4)));
// in the ui, over the scene: the stick drawn where the thumb holds it
<Stick bind={move} left={24} bottom={24}/>
```

`step` reads `helder.os.Pointers` (no events needed): each finger's press
is taken by the first control whose zone it began in (sticks, buttons and
`Touch` zones, then `TouchDelta`'s look zones), if nobody had it: not a
press on a ui node (helder.ui's window marks those the ui's, so a touch
on a HUD button never reaches the game), and kept until it lifts or is
cancelled, wherever it goes (a finger sliding over a button from
elsewhere does not press it; a button's finger sliding off lets it go).
A cancel lets go too: the player stops. `TouchDelta` is the drag over
the step in points times its scale (a look, not clamped); a press and
its release within a step still count. Equal zones are one control.
Nothing is allocated per event or per step (`changed`'s closures and the
key sets' maps are gone). Tests: `src/helder/scene/input/TouchActions.test.hx`
(natively and as wasm32-wasi, the allocation included),
`tests/3d/InputTest.hx`, `<Stick>` drawn in `tests/3d-ui/SurfaceTest.hx`.

## Debugging

`FrameStats` keeps the last frames' times (and, given to `add`, the CPU's
share of each), the renderer's counts, `percentile(0.5)`, `percentile(0.99,
true)` and `fps()` without allocating; `Overlay` draws them over the frame
with `helder.ui`'s drawn renderer (put `src` on the class path where it is
used): its bars and figures, with `detail` the fps, frame time and CPU
p50/p99 and the program's own `lines`, and with `extra` a program's own
controls in its pass (`text` in its pixel font, `rect`; `panel = false`:
those alone). The performance examples use it: `examples/instancing`,
`bunnymark`, `particles`, `physics-stress`.

## Instancing

Nodes that draw the same primitive are batched by the renderer (above).
For many copies without a node each, an `InstancedMesh` is one mesh drawn
from flat per-instance data in one instanced draw a primitive: a transform
(position, unit quaternion, uniform scale; or a matrix), a colour (times
the material's), and custom floats for a program's own shader:

```haxe
var rocks = new InstancedMesh(Shapes.box(device, rock), 100000);   // capacity, count, custom floats
InstancedMesh.attach(world.node("belt"), rocks);                  // drawn while the node is shown
rocks.bounds = beltBounds;                                        // optional: culled whole, fitted by Shadows
// each frame, nothing allocated:
for (i in 0...rocks.count) rocks.setTransform(i, x, y, z, qx, qy, qz, qw, scale);
rocks.setColor(i, r, g, b);
```

The data is the instance buffer's layout (`data`, 64 bytes an instance;
`customData` beside it, uploaded to `customBuffer`), uploaded by the
renderer before its pass when written (count instances, one
`writeBuffer`); the standard material draws it (normal maps too), and it
casts into `Shadows`' map. In markup: `<instances of={rocks}/>`. Tests:
`src/helder/scene/render/InstancedMesh.test.hx` (the layout, resize,
nothing allocated), the 3d lane's `instancedmesh` frame (shadows, a set
culled), `tests/3d-ui/SceneUiTest.hx`.

## Fast refresh

`HotWorld.keep(world, key)`, after the world is made: under `helder dev` the
old build's transforms are put back by node path; nothing without
`-D hxmc.dev`.

## Rendering

```haxe
var renderer = new Renderer(device);
new GltfScene(Gltf.parse(Asset.embed("sample.glb")), device).instantiate(world);
// in the frame:
renderer.draw(enc, world, camera);   // one pass into the frame
```

The renderer extracts the world's meshes (`MeshRenderer`) into a draw
list (shown nodes inside the view, sorted by pipeline and material), then
records it with `PbrShader`: glTF's metallic-roughness model, the world's
first directional `Light` and up to four point lights
(`Light.pointLight(color, intensity, range)`, `Light.spot(...)`; a world without lights:
`renderer.sun*`), a sky-and-ground
ambient, ACES tone mapping, sRGB output (or linear light into HDR targets: below). Nodes drawing the same primitive are drawn in one instanced call
(`renderer.instancing`, on by default). See-through materials (`material.blend`, glTF's alphaMode BLEND) are drawn after the opaque ones, farthest first.
Materials also take a uv transform (`uvOffset`, `uvRotation`, `uvScale`),
an alpha cutoff (`alphaCutoff`: below it dropped), a clear coat
(`clearcoat`, `clearcoatRoughness`: a polished dielectric layer, its
reflection of the sun and the environment over the base) and transmission
(`transmission`: a thin surface, drawn see-through twice: what is behind
multiplied by its colour, then its reflections over it; no refraction or
blur). Shadows are opted in:
`renderer.use(new Shadows(device))` (one shadow map for the directional
light, fitted to the casters, filtered 3x3; `Shadows.cascaded(device, size, split)`:
two cascades, the first sharp over the camera's view up to `split`
metres). `Shapes.box`, `sphere` and
`plane` make meshes in code. Skinned meshes need
`renderer.use(new Skinning(device))`; materials' normal maps need
`renderer.use(new NormalMaps(device))`, made before the models load (they
get tangents: the file's, else computed); `renderer.use(new Sky(device))` draws
a sky behind the scene; `renderer.use(Environment.fromImage(device, mime, bytes))`
an equirectangular image behind it that also lights it (image-based ambient and reflections); `renderer.use(new GpuParticles(device, capacity))` draws particles written once and moved by the GPU (`fx.live`: the newest slots drawn, a bound on those alive; examples/particles draws a million). Programs draw at injection points:
`renderer.inject(BeforeOpaque | AfterOpaque | AfterPass, (enc, frame) -> ...)`; features reach the renderer through
`RenderFeature`, so unused ones are not linked.

The standard material is a slot object, `pbr` (`PbrShader`; helder.gfx's
`slots`, DESIGN.md 3 in src/helder/compiler): one shader whose variants
are the renderer's (`pbr.variant({normalMap, skinned, instanced})`:
`PbrShader`, `PbrNormalShader`, `PbrSkinnedShader`, `PbrInstancedShader`,
`PbrInstancedNormalShader`; the shadow map's casters are `shadowCaster`'s)
and whose slots a material replaces: `color`, `alpha`, `normal`,
`roughness`, `metalness` and `emissive` (of the fragment's `PbrSurface`),
`position` (of the vertex's `PbrPoint`). `MaterialShader.material(pbr.with({...}))`
compiles them, at build time, into a shader of the material's own
(`material.shader`, every variant the renderer draws with); a slot's
parameters beyond the standard ones are blocks of its own
(`material.uniforms`, written by its `params`). examples/glow replaces
the emissive and colour slots.

### HDR and post-processing

An offscreen renderer made with `hdr` (`new Renderer(device, true,
samples, true)`; a `<Scene hdr>` box) draws in linear light into half-float
targets (RGBA16F: light brighter than white kept; the shaders' last step
`PbrShader.output` leaves the tone mapping to later), and a `PostProcess`
turns the frame into the 8-bit image shown:

```haxe
var post = new PostProcess(device);   // into RGBA8 targets (a <Scene>'s box's); (device, RGBA8, true): the frame
post.bloom = 0.05;                    // the share of the light spread: no threshold, what is bright blooms
post.toneMap = Aces;                  // Narkowicz's, the 8-bit path's; AgX; Clamp
post.saturation = 1.05; post.contrast = 1.05; post.lift = ...; post.gain = ...;
post.vignette = 0.3; post.grain = 0.03; // both 0 by default: no grain, a still dither
post.levels = 4; post.base = 2;       // a cheaper bloom: 4 levels from a quarter of the frame (default 6 from half)
renderer.post = post;                 // a <Scene hdr>'s box runs it; else post.run(enc, hdrColor, target, w, h, time)
```

Bloom is the physically based kind (Jimenez, Call of Duty: Advanced
Warfare; Unity's HDRP): the frame filtered down a chain of half-sized
RGBA16F targets (13 taps, the first level in Karis' average against
fireflies) and back up (a tent filter, each level added to the one
above), mixed into the frame by its share. A run records 2 * levels
passes (6 levels by default) and allocates nothing; its targets are the
GPU's, as many as the levels, made again when the size, the base or the
levels change. On a phone 4 levels from a quarter of the frame (`base = 2`)
look alike at a third fewer passes and a quarter of the pixels. `tests/3d/bloom.png` is its
frame. A GPU that cannot draw into half floats (GL ES without
EXT_color_buffer_half_float or _float; WebGL2 enables either): a `<Scene>`
says so once and draws in 8 bits.

### Image-based light, prefiltered

`Environment.prefiltered(device, mime, bytes, levels)` lights the scene
from an atlas filtered once ahead (a tool: Expansion's `tools/envbake.py`):
`levels` rows of the sphere (equirectangular, width by width / 2) by
roughness (GGX's lobe convolved, the split sum's first half) and the
diffuse irradiance's row below them. The standard material reads two rows
by its roughness, blended, along the reflection, and the last along its
normal: 128 x 448 for 6 levels, 224 KB on the GPU, no mip levels.
`renderer.rim` (a colour times intensity) and `rimPower` add a rim light
from the sun's side along the silhouettes. `material.emissiveNight` (0 to 1) keeps a
material's light to its night side, faded in across the terminator (a
planet's city lights).

`examples/gltf-showcase` shows Khronos' sample models (DamagedHelmet,
FlightHelmet, SciFiHelmet, the extensions' tests) under prefiltered HDR
environments, compared with the sample viewer's renders in its README.

## TypeScript

`helder/scene` (src/helder/scene/index.ts, over `helder/scene/runtime`,
which `TypeScript.hx` declares: src/helder/typescript/README.md) is this
package for TypeScript programs: World, Camera, Light, Material,
MeshRenderer, Shapes, Model, Renderer, InputMap (its bindings made by
Bindings: `actions.bind("jump", Bindings.key(0x20))`), FixedStep, and what
a scene is drawn with (helder.os's Window, App, Event and Surface,
helder.gfx's Device). A Node is the program's class over a node's handle
(its members `Script`'s functions: Node's own are inline), Vec3 and Quat
helder/gfx's values:

```ts
const world = new World("demo");
const eye = world.node("eye");
const camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
eye.position = vec3(0, 1, 4);
eye.lookAt(vec3(0, 0, 0));
```

A material of its own is `material(pbr.with({...}))`, as Haxe's
MaterialShader.material: `pbr` is the standard material's slot object
(src/helder/scene/pbr.ts: PbrShader.hx in TypeScript, keep the two in
step; tests/typescript/definitions/pbr.ts checks their text is the same),
and its value's `apply(material, {glow: bytes})` gives a material the
shader and its blocks (`params.glow.write(value, bytes)`):

```ts
type GlowParams = {color: Vec4, time: Vec4};
const Glow = material(pbr.with({
	emissive: (s: PbrSurface, p: {glow: GlowParams}): Vec3 => p.glow.color.xyz.mul(0.6 + 0.4 * sin(p.glow.time.x * 3 + s.world.x)),
}));
Glow.apply(orb, {glow: bytes});
```

`tests/typescript/helder/scene.ts` checks it without a GPU.

`examples/gltf-viewer/sample.glb` (and `tests/3d/skinned.glb`, `tests/3d/textured.glb`, `examples/showroom/normals.glb`) is generated by `tests/3d/SampleModel.hx` (MIT).

Tests: `tests/3d/SceneTest.hx`, `tests/3d/GltfTest.hx` and the frames of
`tests/3d/Scenes.hx` against `tests/3d/<scene>.png` (`bun run test 3d`, natively;
`bun run test 3d-web`, WebGPU and WebGL2 in Chromium).
