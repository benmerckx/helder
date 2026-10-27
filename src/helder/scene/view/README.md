# helder.scene.view

`helder.view`'s markup and signals on `helder.scene`'s scene graph (Haxe package
`helder.scene.view`; a prototype, see the README's roadmap). An
optional package: the 3D core knows nothing of it.

```haxe
// -D helder.view.renderer=helder.scene.view.SceneRenderer
var pos = signal(new Vec3(0, 1, 0));
var lit = signal(true);
SceneRenderer.device = device;
Render.render(<node name="lamp" position={pos}>
	<mesh shape="sphere" size={0.4} color={new Vec4(1, 0.8, 0.4, 1)}/>
	<Show when={lit}><light kind="point" intensity={6.0} range={8.0}/></Show>
</node>, SceneRenderer.root(world));
pos.value = new Vec3(1, 1, 0);   // the node moves: no reconciliation, no re-render
```

Elements: `node`, `mesh` (shape `box`, `sphere`, `plane`; size, color,
metallic, roughness), `light` (kind `directional`, `point`; color,
intensity, range), `camera` (fov, near, far); `position`, `rotation`,
`scale`, `name`, `visible` on all. Per-frame work goes through the frame
stages (`helder.scene.Stages`), not through signals.

A prototype: properties go through `setProperty` by name; typed
constructors per tag, checked when compiling, come next. A struct value
(`Vec3`, `Quat`) is bound through a `Signal` for now (hxmc does not yet
pass a closure returning one where a function of another type is
expected).

Tests: `tests/3d-ui/SceneUiTest.hx` (`bun run test 3d`).
