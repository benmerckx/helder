// A swipe on the emulator's touchscreen as a finger's: the kernel's input
// events of its multi-touch device (virtio_input_multi_touch_1, display 0's),
// written as root (the emulator's userdebug image: su), a step at a time,
// each a write of its own, so InputReader reads them as the hardware's,
// timed by the kernel as they come. Its last move and its lift are one
// write: let go moving, as a flick is. `adb shell input swipe` is no
// fling: each of its events waits until the window finished it, so its
// moves come as the system's frames allow and its lift a pause after the
// last of them (on CI's emulator over 100 ms now and then: the cube held,
// not flicked), at the end point however far the moves got.
//   node tests/os/android-swipe.mjs <x0> <y0> <x1> <y1> [moves]   (the display's pixels)
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const [x0, y0, x1, y1] = process.argv.slice(2, 6).map(Number);
const moves = Number(process.argv[6] ?? 8);
const adb = (...args) => execFileSync('adb', args, { encoding: 'utf8' });

// (the device's node and its axes' ranges, from getevent's list)
const blocks = adb('shell', 'getevent', '-lp').replace(/\r/g, '').split(/^add device \d+: /m).slice(1);
const touch = blocks.map((b) => ({ node: b.split('\n')[0].trim(), name: (b.match(/name:\s+"([^"]*)"/) ?? [])[1], text: b }))
	.filter((d) => /ABS_MT_POSITION_X/.test(d.text));
const dev = touch.find((d) => d.name === 'virtio_input_multi_touch_1') ?? touch[0];
if (!dev) {
	console.log('android-swipe.mjs: no touchscreen among the input devices');
	process.exit(1);
}
const range = (axis) => {
	const m = dev.text.match(new RegExp(axis + '\\s*:.*min (-?\\d+), max (-?\\d+)'));
	return m ? [Number(m[1]), Number(m[2])] : null;
};
const [xmin, xmax] = range('ABS_MT_POSITION_X'), [ymin, ymax] = range('ABS_MT_POSITION_Y');
const [W, H] = adb('shell', 'wm', 'size').match(/(\d+)x(\d+)\s*$/).slice(1).map(Number);
// (a pixel's raw value: TouchInputMapper scales the axis's min..max + 1 to the display)
const rx = (x) => Math.round(xmin + (x * (xmax - xmin + 1)) / W), ry = (y) => Math.round(ymin + (y * (ymax - ymin + 1)) / H);

// struct input_event (x86-64: a timeval the kernel fills, type, code, value)
const EV_SYN = 0, EV_ABS = 3, SLOT = 0x2f, TRACKING_ID = 0x39, X = 0x35, Y = 0x36, PRESSURE = 0x3a;
const events = (list) => {
	const b = Buffer.alloc(24 * list.length);
	list.forEach(([type, code, value], i) => {
		b.writeUInt16LE(type, 24 * i + 16);
		b.writeUInt16LE(code, 24 * i + 18);
		b.writeInt32LE(value, 24 * i + 20);
	});
	return b;
};
const at = (k) => [[EV_ABS, X, rx(x0 + ((x1 - x0) * k) / moves)], [EV_ABS, Y, ry(y0 + ((y1 - y0) * k) / moves)], [EV_SYN, 0, 0]];
const pressure = range('ABS_MT_PRESSURE');
const steps = [events([[EV_ABS, SLOT, 0], [EV_ABS, TRACKING_ID, 1], ...(pressure ? [[EV_ABS, PRESSURE, pressure[1] >> 1]] : []), ...at(0)])];
for (let k = 1; k < moves; k++) steps.push(events(at(k)));
steps.push(events([...at(moves), [EV_ABS, TRACKING_ID, -1], [EV_SYN, 0, 0]]));

const dir = mkdtempSync(path.join(tmpdir(), 'swipe-'));
steps.forEach((b, i) => writeFileSync(path.join(dir, String(i)), b));
const remote = '/data/local/tmp/helder-swipe';
adb('shell', 'rm', '-rf', remote);
adb('push', dir, remote);
rmSync(dir, { recursive: true });
console.log(`android-swipe.mjs: ${dev.node} (${dev.name}), ${x0},${y0} to ${x1},${y1} in ${moves} moves`);
const script = steps.map((_, i) => `cat ${remote}/${i} > ${dev.node}`).join('; sleep 0.016; ');
adb('shell', 'su', '0', 'sh', '-c', `'${script}'`);
