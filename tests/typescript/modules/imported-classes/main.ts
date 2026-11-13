// `new C(...)` of a class imported from another module: made directly
// (its layout's), the same as JavaScript's: renamed imports, a subclass,
// an export under another name, a default export
import { Vec, Named as Label, Shown } from "./shapes.js";
import Plain from "./shapes.js";
const a = new Vec(3, 4), b = new Label("b", 1, 2);
const c = a.add(b);
console.log(c.x, c.y, a.length, c instanceof Vec, b instanceof Label, b.name, Object.keys(a).join());
console.log(new Shown().tag, new Plain().kind);
let s = 0;
for (let i = 0; i < 1000; i++) s += new Vec(i, 1).add(new Vec(1, i)).x;
console.log(s);
