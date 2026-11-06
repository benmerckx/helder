// tests/view's TestRenderer for the TypeScript tests (tests/typescript/helder):
// a tree of nodes written out as HTML. A program's own Haxe classes declared
// to it as helder's are: a module's declaration class (helder.typescript.api.Modules),
// its declarations generated (tests/typescript/run.mjs checks them).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Mat4, Quat, Vec2, Vec3, Vec4} from "helder/gfx";

declare const __haxe: {TestNode: "TestRenderer.TestNode", MathProbe: "MathProbe", __module: "TestTypeScript"};

export declare class TestNode {
	// (for programs that render into a tree of their own: helder.typescript's tests)
	static root(tag: string): TestNode;
	// calls the listener for name of the first element with tag here or below
	fire(tag: string, name: string): void;
	toHtml(): string;
}

// helder's math types (helder.gfx.shader's vectors and matrix, helder.scene's
// quaternion: struct values) crossing to TypeScript as helder/gfx's classes
// (tests/typescript/helder/math.ts): arguments, results, a field, a property.
export declare class MathProbe {
	constructor(at: Vec3);
	static scaled(v: Vec3, s: number): Vec3;
	static sum(a: Vec2, b: Vec4): number;
	static translation(x: number, y: number, z: number): Mat4;
	static apply(m: Mat4, v: Vec4): Vec4;
	static spin(a: Quat, b: Quat): Quat;
	// where it is (a struct stored in the object)
	at: Vec3;
	// its turn (a property: through its accessors)
	turn: Quat;
	// moved by d: where it is now
	moved(d: Vec3): Vec3;
}
