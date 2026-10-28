// enums (numeric, string, merged, const), namespaces (nested, merged, exported members)
enum Color { Red, Green = 5, Blue, Mixed = Green * 2 + Blue }
enum Dir { Up = "UP", Down = "DOWN" }
enum Color { Extra = 100 }
const enum Flags { None = 0, A = 1 << 0, B = 1 << 1, AB = A | B }
console.log(Color.Red, Color.Blue, Color[6], Color.Mixed, Color.Extra, Dir.Down, Flags.AB, Object.keys(Color).join(), JSON.stringify(Dir));
function paint(c: Color) { switch (c) { case Color.Red: return "red"; default: return Color[c] ?? "?"; } }
console.log(paint(Color.Red), paint(Color.Blue));
namespace Geometry { export const unit = 1; const hidden = 2; export function area(r: number) { return Math.PI * r * r * unit; } export namespace Shapes { export class Square { constructor(public side: number) {} area() { return this.side ** 2 + hidden; } } } }
namespace Geometry { export const extra = unit + 1; }
namespace A.B.C { export const deep = "deep"; }
console.log(Geometry.unit, Geometry.area(1).toFixed(3), new Geometry.Shapes.Square(3).area(), Geometry.extra, A.B.C.deep, (Geometry as any).hidden);
declare const outside: number;
{ enum Local { X = 3 } console.log(Local.X, Local[3]); }
