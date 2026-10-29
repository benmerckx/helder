# helder.scene.view

`helder.view`'s markup and signals on `helder.scene`'s scene graph (Haxe package
`helder.scene.view`; a prototype, see the README's roadmap). An
optional package: the 3D core knows nothing of it.

```haxe
import helder.scene.view.SceneTags.*;

var pos = signal(new Vec3(0, 1, 0));
var lit = signal(true);
UiWindow.run(<Surface title="Lamp" width={640} height={400}>
	<view direction="row" grow={1}>
		<Scene grow={1} camera={camera}>
			<node name="lamp" position={pos}>
				<mesh shape="sphere" size={0.4} color={new Vec4(1, 0.8, 0.4, 1)} onClick={() -> lit(on -> !on)}/>
				<Show when={lit}><light kind="point" intensity={6.0} range={8.0}/></Show>
				<Ui><text>lamp</text></Ui>
			</node>
		</Scene>
		<view width={160}>...</view>
	</view>
</Surface>);
pos(new Vec3(1, 1, 0));   // the node moves at the next flush: no reconciliation, no re-render
```

- **`<Scene>`** (`SceneTags.Scene`): a ui node, a box in ui's layout (`grow`,
  `width`, `height`, `style`), drawing its `world` (its own by default) as
  `camera` sees it (else the world's first camera, else one at (0, 2, 6)
  looking at the origin); its children are this package's markup
  (`SceneView`). It draws into a texture of its size (an offscreen
  `helder.scene.render.Renderer` on the window's device, recorded before
  ui's pass), again when a node of its markup changes, or every frame
  while `animate` is set. Multisampled by default, 4 samples a pixel
  resolved into the texture ui draws (`antialias={false}`: one);
  `setup={r -> ...}` gets its renderer once made (its clear colour, a
  transparent one showing ui's background under the world, the ambient,
  `Shadows`), `ref` the `SceneBox` (its size, `safeArea()`, its gestures:
  examples/golf's shot is a recogniser of its own there).
- **Pointer events across the boundary**: ui's hit testing finds the box
  (ui's nodes over it first: a HUD's buttons; `pointerEvents="none"` lets
  a container through); `onPointerDown`, `onPointerUp`, `onPointerMove`,
  `onPointerCancel`, `onClick`, `onPointerEnter`, `onPointerLeave` on scene
  elements get a `SceneEvent` (the node hit, the point, the distance,
  ui's event, the pointer's id), from the nearest node whose mesh's bounds
  the pointer's ray crosses (`Pick.ray`) up through its ancestors
  (`stop()` ends it). Bounds, not triangles. Picked once, at each
  pointer's press (fingers, pens and the mouse each their own): the node
  hit owns the pointer until it lifts (its moves, release, cancel and
  click go there); a hovering mouse or pen picks as it moves (enter,
  leave). The `SceneEvent` is one per box, refilled; listeners are kept by
  kind when set. The box's pointers are the game's (`ownsPointer`: a
  touch on the scene is not marked the ui's). `SceneEvents` declares them
  (SceneRenderer's `@:events`): a handler takes a `SceneEvent` or nothing,
  an untyped parameter is one (`onClick={e -> picked(e.node.name)}`),
  another type or name a compile error at the attribute.
- **Taps and the camera**: `onTap` on scene elements (the box's own
  `Tap`, for the node its press picked; `e.gesture`) competes in the
  pointer's arena with `<OrbitControls>` (`SceneTags.OrbitControls`,
  three.js's names: `target`, `minDistance`, `maxDistance`, `minPitch`,
  `maxPitch`, `rotateSpeed`, `zoomSpeed`, `panSpeed`, `damping`,
  `enableRotate`, `enableZoom`, `enablePan`, `enableTwist`, `ref`), which
  reads the box's `Scale` gesture: one finger or the left button turns
  the camera round the target, two fingers pinch it nearer about their
  centre (the point under them stays), move the target and twist it, the
  right button moves the target, the wheel zooms about the pointer; let
  go moving it glides on, slowing by `damping` a frame. A tap on a mesh
  selects, a drag from it orbits.
- **`<Stick>`** (`SceneTags.Stick`): an on-screen stick
  (`helder.scene.input.VirtualStick`, bound by `Actions`) drawn over the
  ui, at rest at `left`, `bottom`, under the thumb once it holds it; the
  pointer goes through it.
- **`<Ui>`** (`SceneTags.Ui`): back to ui inside a scene, drei's `<Html>`:
  a scene node (`position`) whose children, ui's markup, are drawn over the
  box at its place, centred; placed from the frame drawn (a frame late) and
  hidden behind the camera.
- **Errors**: `<view>` in a scene's markup is no element of
  `SceneRenderer` (`@:elements`: node, mesh, light, camera); `<Scene>` in a
  scene's markup is ui's (it returns a `helder.ui.Node`).

Elements: `node`, `mesh` (shape `box`, `sphere`, `plane`; size, color,
metallic, roughness), `light` (kind `directional`, `point`; color,
intensity, range), `camera` (fov, near, far); `position`, `rotation`,
`scale`, `name`, `visible` on all. Markup outside a `<Scene>` renders into a
world's root: `Render.render(<node/>, SceneRenderer.root(world))`. Per-frame
work goes through the frame stages (`helder.scene.Stages`), not through
signals.

A prototype: properties go through `setProperty` by name; typed
constructors per tag, checked when compiling, come next. A struct value
(`Vec3`, `Quat`) is bound through a `Signal` for now (hxmc does not yet
pass a closure returning one where a function of another type is
expected). In a `<Scene>`, the renderer's own pipelines draw into its
target; its features' (skins, normal maps, the sky, particles) are the
frame's still.

Tests (`bun run test 3d`): `tests/3d-ui/SceneUiTest.hx` (markup on a
world), `tests/3d-ui/SurfaceTest.hx` (under Xvfb: two `<Surface>`s, a
`<Scene>`'s pixels in its box, a click picked in it, fingers picked at
their presses, a tap on the mesh, a drag from it orbiting the camera, a
cancel, `<Ui>` placed, `<Stick>` drawn); `OrbitControls.test.hx` (the
camera's motion without a GPU, natively and as wasm32-wasi).
`examples/planets` puts them together.
