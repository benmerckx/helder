// Small objects and methods: a particle system on a 2D vector class.
class Vec {
	constructor(public x: number, public y: number) {}
	add(o: Vec): Vec { return new Vec(this.x + o.x, this.y + o.y); }
	scale(k: number): Vec { return new Vec(this.x * k, this.y * k); }
	dot(o: Vec): number { return this.x * o.x + this.y * o.y; }
}
class Particle {
	constructor(public at: Vec, public velocity: Vec) {}
	step(dt: number, gravity: Vec) {
		this.velocity = this.velocity.add(gravity.scale(dt));
		this.at = this.at.add(this.velocity.scale(dt));
		if (this.at.y < 0) this.velocity = new Vec(this.velocity.x, -this.velocity.y * 0.9);
	}
}
const particles: Particle[] = [];
for (let i = 0; i < 1000; i++) particles.push(new Particle(new Vec(i, 100 + i % 7), new Vec(1, 0)));
const gravity = new Vec(0, -9.81);
for (let t = 0; t < 2000; t++) for (const p of particles) p.step(0.001, gravity);
let energy = 0;
for (const p of particles) energy += p.velocity.dot(p.velocity);
console.log(energy.toFixed(6));
