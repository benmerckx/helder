// helder/scene without a GPU: a World's nodes (helder/scene's Node over a
// node's handle, its transforms helder/gfx's values), a camera's matrices, a
// light, a material's fields and its constructor's defaults, a fixed step.
// (InputMap's is examples/ts-scene's: it reaches the windows' code, which a
// static build does not link)
import { World, Node, Camera, Light, Material, FixedStep } from "helder/scene";
import { vec3, vec4, Quat } from "helder/gfx";

const world = new World("test");
const arm = world.node("arm");
arm.position = vec3(2, 0, 0);
arm.rotation = Quat.axisAngle(vec3(0, 0, 1), Math.PI / 2);
const hand = world.node("hand", arm);
hand.position = vec3(1, 0, 0);
const p = hand.worldPosition();
console.log(world.count, arm.name, hand.name, hand.parent.equals(arm), hand.parent === arm, arm instanceof Node);
console.log(p.x.toFixed(3), p.y.toFixed(3), p.z.toFixed(3));
console.log(world.root.find("hand").equals(hand), world.root.find("nobody").isNone, world.root.parent.isNone);
console.log(arm.children().map(c => c.name).join(","), world.root.children().length);
hand.visible = false;
console.log(hand.visible, hand.shown(), arm.shown());
hand.scale = vec3(2, 2, 2);
console.log(hand.scale.y, hand.localMatrix().c0.x);

const eye = world.node("eye");
const camera = Camera.attach(eye, Camera.perspective(Math.PI / 3, 0.1, 100));
eye.position = vec3(0, 0, 5);
eye.lookAt(vec3(0, 0, 0));
const e = camera.eye();
console.log(camera.node.equals(eye), Camera.of(eye) !== null, Camera.of(arm) === null, e.z, camera.fovY.toFixed(4));
const clip = camera.viewProjection(1).mul(vec4(0, 0, 0, 1));
console.log((clip.z / clip.w).toFixed(4), clip.x, clip.y);

const lamp = Light.attach(world.node("lamp"), Light.pointLight(vec3(1, 0.8, 0.6), 6, 8));
console.log(lamp.point, lamp.range, lamp.color.y, Light.of(arm) === null);

const m = new Material("orb", vec4(0.35, 0.3, 0.5, 1), 0, 0.4);
m.emissive = vec3(0.5, 0, 0);
console.log(m.name, m.baseColor.z, m.roughness, m.emissive.x, m.shader === null);
const plain = new Material("plain");
console.log(plain.roughness, plain.baseColor.x, plain.doubleSided);

const step = new FixedStep(0.25);
let steps = 0;
step.advance(0.6, dt => steps += dt);
console.log(step.steps, steps, step.alpha.toFixed(2));

hand.dispose();
console.log(hand.valid, arm.valid, world.count);
