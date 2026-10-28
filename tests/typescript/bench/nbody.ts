class Body {
	constructor(public x: number, public y: number, public z: number, public vx: number, public vy: number, public vz: number, public mass: number) {}
}
function advance(bodies: Body[], dt: number) {
	for (let i = 0; i < bodies.length; i++) {
		const a = bodies[i];
		for (let j = i + 1; j < bodies.length; j++) {
			const b = bodies[j];
			const dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
			const d2 = dx * dx + dy * dy + dz * dz;
			const mag = dt / (d2 * Math.sqrt(d2));
			a.vx -= dx * b.mass * mag; a.vy -= dy * b.mass * mag; a.vz -= dz * b.mass * mag;
			b.vx += dx * a.mass * mag; b.vy += dy * a.mass * mag; b.vz += dz * a.mass * mag;
		}
	}
	for (const b of bodies) { b.x += dt * b.vx; b.y += dt * b.vy; b.z += dt * b.vz; }
}
function energy(bodies: Body[]): number {
	let e = 0;
	for (let i = 0; i < bodies.length; i++) {
		const a = bodies[i];
		e += 0.5 * a.mass * (a.vx * a.vx + a.vy * a.vy + a.vz * a.vz);
		for (let j = i + 1; j < bodies.length; j++) {
			const b = bodies[j];
			const dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
			e -= a.mass * b.mass / Math.sqrt(dx * dx + dy * dy + dz * dz);
		}
	}
	return e;
}
const bodies = [new Body(0, 0, 0, 0, 0, 0, 39.47), new Body(4.84, -1.16, -0.10, 0.60, 2.81, -0.02, 0.037), new Body(8.34, 4.12, -0.40, -1.01, 1.82, 0.008, 0.011), new Body(12.89, -15.11, -0.22, 1.08, 0.86, -0.01, 0.0017), new Body(15.37, -25.91, 0.17, 0.97, 0.59, -0.03, 0.002)];
console.log(energy(bodies).toFixed(9));
for (let i = 0; i < 1000000; i++) advance(bodies, 0.01);
console.log(energy(bodies).toFixed(9));
