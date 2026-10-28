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
any component type, normalized or strided. `GltfNodes.build(doc, world, ?parent, ?scene, ?mesh)` makes the node
hierarchy (TRS or matrices, cameras); `GltfScene` makes the GPU meshes and
materials once and `instantiate(world)` copies the hierarchy into a world.
`Asset.embed(path)` builds a file into the program.

## Models

```haxe
var hero = Model.of("models/hero.glb");      // checked and typed when compiling
var root = hero.instantiate(world, device);  // GPU meshes made once, shared
var hand = root.find(hero.nodes.LeftHand);   // hero.nodes.LeftHnad: a compile error
```

`Model.of` reads the file's names when compiling (nodes, meshes,
materials, animations: `model.nodes`, ...). A file up to 64 KB is built
into the program (`-D helder.scene.embed=<bytes>`); a larger one is copied
beside it (`assets/`, listed in `<output>.assets.json`), read from beside
the executable natively and fetched before main in the browser
(`browser.mjs`'s `assets` option: `run(wasm, {assets: 'app.wasm.assets.json'})`);
the repository tool's `hxmc <output> ...` form needs `-D helder.scene.out=<output>`.
For now self-contained files only for now (one embedded
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
materials (factors, maps, sampler), images (decoded by `Images.decode`
when loaded), cameras, lights, skins, morph targets, animations (`model.clip(name)`,
playing on the nodes `instantiate` made) and the hierarchy.

Big files or loading screens: `Model.of(path, Lazy)` is an `Asset` of the
same typed model, loaded in the background (`asset.then(m -> ...)`,
`asset.ready`); `Model.load(path)` loads a path known only at run time.
Loads advance in `Assets.poll()`, which `Stages.frame` calls.

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
var actions = new Actions();
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

`FrameStats` keeps the last frames' times and the renderer's counts;
`Overlay` draws them over the frame with `helder.ui`'s drawn renderer (put
`src` and `src` on the class path where it is
used).

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
ambient, ACES tone mapping, sRGB output. Nodes drawing the same primitive are drawn in one instanced call
(`renderer.instancing`, on by default). See-through materials (`material.blend`, glTF's alphaMode BLEND) are drawn after the opaque ones, farthest first. Shadows are opted in:
`renderer.use(new Shadows(device))` (one shadow map for the directional
light, fitted to the casters, filtered 3x3; `Shadows.cascaded(device, size, split)`:
two cascades, the first sharp over the camera's view up to `split`
metres). `Shapes.box`, `sphere` and
`plane` make meshes in code. Skinned meshes need
`renderer.use(new Skinning(device))`; materials' normal maps need
`renderer.use(new NormalMaps(device))`, made before the models load (they
get tangents: the file's, else computed); `renderer.use(new Sky(device))` draws
a sky behind the scene; `renderer.use(Environment.fromImage(device, mime, bytes))`
an equirectangular image behind it that also lights it (image-based ambient and reflections); `renderer.use(new Particles(device))` draws the
world's `Emitter`s (simulated by `Particles.update(world, dt)`). Programs draw at injection points:
`renderer.inject(BeforeOpaque | AfterOpaque | AfterPass, (enc, frame) -> ...)`; features reach the renderer through
`RenderFeature`, so unused ones are not linked.

`examples/gltf-viewer/sample.glb` (and `tests/3d/skinned.glb`, `tests/3d/textured.glb`, `examples/showroom/normals.glb`) is generated by `tests/3d/SampleModel.hx` (MIT).

Tests: `tests/3d/SceneTest.hx`, `tests/3d/GltfTest.hx` and the frames of
`tests/3d/Scenes.hx` against `tests/3d/<scene>.png` (`bun run test 3d`, natively;
`bun run test 3d-web`, WebGPU and WebGL2 in Chromium).
