// classes with layouts another module constructs (imported-classes/main.ts)
export class Vec {
	constructor(readonly x: number, readonly y: number) {}
	add(b: Vec): Vec { return new Vec(this.x + b.x, this.y + b.y); }
	get length(): number { return Math.sqrt(this.x * this.x + this.y * this.y); }
}
export class Named extends Vec {
	constructor(readonly name: string, x: number, y: number) { super(x, y); }
}
class Hidden { tag = "hidden"; }
export { Hidden as Shown };
export default class Plain { kind = "default"; }
