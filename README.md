# universe

next steps:
- archive theme, shadcn widgets, tailwind (these are not useful in current form)
- extract image into own package from ui (png etc)
- cli: helder dev, helder build that boots/builds projects without configuration
- rebuild existing packages on top of helder.scoped
- built-in coroutines that do simple async/await and a fiber/isolate thing for
  background work (in wasm w workers or similar) research first, so we can use it
  for asset loading, http etc
- audio on Android (AAudio) and iOS (RemoteIO) with a mixer
- multi-touch and gestures
- assets in bundles, ETC2/ASTC, MSAA
- Choreographer/CADisplayLink frame loop
- helder.2d package for sprite batch/tilemaps
- vscode plugin to do LSP, syntax highlighting, for proper jsx support etc