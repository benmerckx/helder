interface Point { x: number; label: string }
function show(p: Point): string { return p.label + ":" + p.x; }
const point: Point = { x: 42, label: "answer" };
console.log(show(point));
const a = [1, 2, 3];
console.log(a.length, a[1], "😀".length);
