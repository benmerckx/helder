// The platform a program is built for, as constants: helder's compiler
// folds `platform.os`, `platform.target` and `platform.arm` where the
// program is compiled (helder.typescript.lower.Platform), as Haxe's
// `Platform.os()` and `Platform.target()` are, and a condition of them (===, !==, !,
// && and ||) with them: an `if` or a `?:` on one lowers only the branch it
// takes, so what only another platform's branch calls is not linked (Haxe's
// `#if`):
//
//   import { platform } from "helder/platform";
//
//   if (platform.os === "windows") useWin32();   // not in a Linux build
//   else if (platform.os === "macos") useCocoa();
//
// platform is read by its fields only (it is no object at run time).

// linux, macos, windows; wasi (WebAssembly, the browser's too), android
// (os() is Linux's in Haxe: Platform.target() >= 9), ios (and its simulator)
export type Os = "linux" | "macos" | "windows" | "wasi" | "android" | "ios";

// hxmc's target names
export type Target = "linux-x86_64" | "linux-arm64" | "macos-x86_64" | "macos-arm64" | "windows-x86_64" | "windows-arm64" | "wasm32-wasi"
	| "android-x86_64" | "android-arm64" | "ios-arm64" | "ios-sim-arm64" | (string & {});

export interface Platform {
	readonly os: Os;
	readonly target: Target;
	// an arm64 machine
	readonly arm: boolean;
}

export declare const platform: Platform;
