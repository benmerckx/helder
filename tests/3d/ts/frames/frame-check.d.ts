// tests/3d/ts/frames.ts's own module: FrameCheck, which draws a frame
// headless and compares it (declared as helder's modules are:
// helder.typescript.api.Modules; frame-check.d.ts generated, checked by the
// 3d lane)
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Device, Encoder} from "helder/scene/runtime";

declare const __haxe: {FrameCheck: "frames.FrameCheck", __module: "frames.FramesTypeScript"};

// helder/scene's frames drawn by TypeScript (tests/3d/ts/frames.ts), as
// RenderTest draws Haxe's: headless, 256 x 192, against a golden image by
// packages/gfx's rule (GfxTest.compareBytes; HXMC_3D_TOLERANCE as
// RenderTest's). Declared to the program by FramesTypeScript.
//
//   frames <scene> <golden.png> <out.png> [--bless]
export declare class FrameCheck {
	// the program's arguments
	static args(): string[];
	// a headless device given to make, the frame make's function draws read
	// back and compared (the process ends with the result: 0 alike, 1 not,
	// 3 skipped: no Metal device)
	static run(make: (arg0: Device) => ((arg0: Encoder) => void)): void;
}
