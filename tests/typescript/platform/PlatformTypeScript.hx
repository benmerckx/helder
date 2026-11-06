// Win32 for TypeScript (tests/typescript/platform/main.ts): kernel32's
// GetTickCount64 behind a call, which only a Windows build may link.
@:typescript("./win32", "win32.d.ts")
@:typescript.classes(Win32)
@:build(helder.typescript.api.Manifest.build())
class PlatformTypeScript {}
