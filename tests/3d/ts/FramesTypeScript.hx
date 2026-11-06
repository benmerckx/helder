// tests/3d/ts/frames.ts's own module: FrameCheck, which draws a frame
// headless and compares it (declared as helder's modules are:
// helder.typescript.api.Modules; frame-check.d.ts generated, checked by the
// 3d lane)
@:typescript("./frame-check", "frame-check.d.ts")
@:typescript.classes(FrameCheck)
@:build(helder.typescript.api.Manifest.build())
class FramesTypeScript {}
