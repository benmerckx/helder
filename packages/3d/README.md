# @hxmc/3d

A scene layer for 3D games on `@hxmc/gfx`, in pure Haxe (Haxe package
`hxmc.scene`; the plan and its order: docs/plans/3d.md). It is ordinary gfx
code: use the parts you want, replace the rest.

## Math

gfx's shader types (`Vec2`, `Vec3`, `Vec4`, `Mat4` of `hxmc.gfx.shader`)
are the CPU's types too, so what the CPU computes is what a shader reads.
3d adds, as immutable values like them:

- `Quat`: a unit quaternion (`axisAngle`, `fromEuler`, `fromMat4`, `*`,
  `rotate`, `toMat4`, `slerp`, `conjugate`);
- `Aabb`: an axis-aligned box (`union`, `transform`, `contains`,
  `intersects`, `ray`);
- `MathTools`, a static extension of `Mat4` (`using
  hxmc.scene.math.MathTools`): `inverse`, `transpose`, `determinant`,
  `compose(t, r, s)`, `decompose`, `lookAt`, `lookRotation`,
  `transformPoint`, `transformDir`, `normalMatrix`.

## Scene

```haxe
var scene = new Scene();
var arm = scene.add(new Node("arm"));
arm.position = new Vec3(2, 0, 0);
arm.rotation = Quat.axisAngle(new Vec3(0, 0, 1), Math.PI / 2);
var eye = scene.add(new Node("eye"));
eye.camera = Camera.perspective(Math.PI / 3, 0.1, 100);
eye.position = new Vec3(4, 3, 6);
eye.lookAt(new Vec3(0, 1, 0));
var mvp = eye.camera.viewProjection(width / height) * arm.world();
```

A node's `world()` is cached until a transform above it changes. `FixedStep`
runs a simulation at a fixed rate from the app loop's frames and gives the
fraction between the last two steps for drawing.

Tests: `test/SceneTest.hx` (`make 3d-check`).
