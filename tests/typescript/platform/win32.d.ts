// Win32 for TypeScript (tests/typescript/platform/main.ts): kernel32's
// GetTickCount64 behind a call, which only a Windows build may link.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Win32: "Win32", __module: "PlatformTypeScript"};

// Something only Windows links, for the platform checks (tests/typescript/run.mjs):
// kernel32's GetTickCount64, which a build for another platform must not
// name (main.ts's and Main.hx's Windows branch, helder/platform's and
// Platform.os()'s constants folded).
export declare class Win32 {
	// milliseconds since Windows started
	static ticks(): number;
}
