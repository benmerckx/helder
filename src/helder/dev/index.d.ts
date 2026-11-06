// helder.dev for TypeScript programs (helder.typescript): keep(key, () =>
// initial), a value kept across a reload under `helder dev`, as a signal
// is (a definition: Slot).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Slot: "helder.dev.Slot", __module: "helder.dev.TypeScript"};

// keep(key, () => initial) as TypeScript programs import it (helder/dev:
// helder.dev.TypeScript): a definition, its calls compiled by
// helder.typescript.lower's Definitions (KeepDefinition, as Haxe's
// helder.dev.Keep): under -D hxmc.dev the value the last build kept under
// the key, unless the initial value's source changed, saved on each
// snapshot (a program's data: numbers, strings, booleans, null, arrays and
// plain objects of them, as its signals'); else init().
export declare class Slot {
	// a value kept across a reload under `helder dev`: the key a string
	// literal, the initial value made by a function of no arguments
	static keep<T>(key: string, init: () => T): T;
}

export declare const keep: typeof Slot.keep;
