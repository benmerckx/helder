// helder/scene's pbr (src/helder/scene/pbr.ts) is PbrShader.hx's in
// TypeScript: its variants (the renderer's five) print the same text in
// every language as Haxe's (Pbr.hx), with their layouts, blocks and
// textures. (A literal below 1e-4 is printed by each runtime's Std.string:
// Haxe's macros write 1e-06 where helder's compiler writes 0.000001, so
// Pbr.hx writes it as this does.)
import {pbr} from "helder/scene";
import {print} from "./print";

print(pbr.variant());
print(pbr.variant({normalMap: true}));
print(pbr.variant({skinned: true}));
print(pbr.variant({instanced: true}));
print(pbr.variant({instanced: true, normalMap: true}));
