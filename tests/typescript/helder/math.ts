// helder's math types from TypeScript (tests/view's MathProbe): helder/gfx's
// Vec2, Vec3, Vec4, Mat4 and Quat given to Haxe and back, by value (a value
// given is the program's still, a value read a copy).
import { MathProbe } from "./test-renderer";
import { Vec2, Vec3, Vec4, Quat } from "helder/gfx";

const v = new Vec3(1, 2, 3);
const s = MathProbe.scaled(v, 2);
console.log(s.x, s.y, s.z, v.x, s instanceof Vec3);
console.log(MathProbe.sum(new Vec2(1, 2), new Vec4(3, 4, 5, 6)));
const m = MathProbe.translation(1, 2, 3);
console.log(m.c0.x, m.c1.y, m.c3.x, m.c3.y, m.c3.z, m.c3.w);
const p = MathProbe.apply(m, new Vec4(1, 1, 1, 1));
console.log(p.x, p.y, p.z, p.w, p.add(1).x);
const q = MathProbe.spin(Quat.axisAngle(new Vec3(0, 0, 1), Math.PI / 2), Quat.identity());
console.log(q.x, q.y, q.z.toFixed(4), q.w.toFixed(4));
const probe = new MathProbe(new Vec3(0, 0, 1));
const a = probe.at;
probe.moved(new Vec3(1, 0, 0));
console.log(a.x, probe.at.x, probe.at.z);
probe.at = new Vec3(5, 6, 7);
console.log(probe.at.y, probe.moved(new Vec3(1, 1, 1)).z);
probe.turn = Quat.fromEuler(0, Math.PI, 0);
console.log(probe.turn.y.toFixed(4), probe.turn.w.toFixed(4));
