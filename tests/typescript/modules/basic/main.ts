// modules: named, default and namespace imports, re-exports, live bindings, cycles, evaluation order
import greet, { VERSION, add as plus, Counter } from "./lib/greet.js";
import * as math from "./lib/math.js";
import { square, Shape, cube } from "./lib/index.js";
import { ping } from "./cycle-a.js";
import type { Point } from "./lib/types.js";
import "./side-effect.js";
import { count, increment } from "./lib/state.js";
console.log("main runs last");
const p: Point = { x: 1, y: 2 };
console.log(greet("world"), VERSION, plus(2, 3), new Counter().inc().inc().value, p.x + p.y);
console.log(math.PI_ISH, math.mul(6, 7), Object.keys(math).join(), String(math[Symbol.toStringTag as never]));
console.log(square(5), cube(2), Shape.Circle, Shape[1], ping(3));
console.log(count); increment(); increment(); console.log(count);
