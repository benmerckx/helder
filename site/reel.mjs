// The site's videos (bun run site:reel, after bun run site): the showreel
// and a clip of each showcase demo, recorded headless (helder run
// --headless: the virtual clock, frame n at n / 60 s, so every frame is
// exact whatever the machine's speed) and encoded by ffmpeg into
// <out>/media/<id>.mp4, with a poster (<id>.jpg) from a frame chosen for
// it. The frames stream into ffmpeg as the run writes them and are deleted
// as they go, so a minute of 1280×720 needs a few frames' disk, not
// gigabytes (REEL_TMP: where they pass through, bin/reel by default; a
// tmpfs such as /dev/shm on a full disk). Not in git: pages.yml runs this
// before deploying, and the page shows a note where a video is missing.
//
//   node site/reel.mjs [out] [ids...]      (default bin/site; every clip)
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
const [outArg, ...only] = process.argv.slice(2);
const out = path.join(outArg ?? 'bin/site', 'media');
const FPS = 60;

// each clip: the program, how long, its arguments, a script driving it (the
// pointer and keys drawn over the frames), the poster's time
export const CLIPS = [
	{ id: 'showreel', entry: 'examples/showreel', seconds: 60.6, args: [], poster: 16.4 },
	{ id: 'fx', entry: 'examples/fx', seconds: 26.5, args: ['--tour'], poster: 1.4 },
	{ id: 'literal', entry: 'examples/literal', seconds: 16, script: 'examples/literal/demo.json', poster: 12.9 },
	{ id: 'notes', entry: 'examples/notes', seconds: 14.5, script: 'examples/notes/demo.json', poster: 3.3 }
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function ffmpeg(args) {
	const p = spawn('ffmpeg', ['-y', '-loglevel', 'error', ...args], { stdio: ['pipe', 'inherit', 'inherit'] });
	const done = new Promise((resolve) => p.on('close', resolve));
	return { p, done };
}

async function record(clip) {
	const t0 = Date.now();
	const frames = path.join(process.env.REEL_TMP ?? 'bin/reel', clip.id);
	fs.rmSync(frames, { recursive: true, force: true });
	fs.mkdirSync(frames, { recursive: true });
	fs.mkdirSync(out, { recursive: true });
	const count = Math.round(clip.seconds * FPS), poster = Math.round(clip.poster * FPS);
	const args = ['src/helder/cli/run.mjs', 'run', '--headless', clip.entry, '--frames', String(count), '-o', frames];
	if (clip.script) args.push('--script', clip.script, '--pointer', '--keys');
	if (clip.args?.length) args.push('--', ...clip.args);
	const run = spawn(process.execPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });
	let log = '';
	run.stdout.on('data', (d) => (log += d));
	run.stderr.on('data', (d) => (log += d));
	let exited = null;
	run.on('close', (code) => (exited = code));
	const video = path.join(out, clip.id + '.mp4');
	const enc = ffmpeg(['-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20',
		'-preset', 'slow', '-movflags', '+faststart', video]);
	const name = (k) => path.join(frames, 'frame_' + String(k).padStart(4, '0') + '.png');
	let k = 0;
	// (a frame is whole once the next exists, or the run has ended)
	while (k < count) {
		if (fs.existsSync(name(k + 1)) || (exited !== null && fs.existsSync(name(k)))) {
			const b = fs.readFileSync(name(k));
			if (k === poster) fs.writeFileSync(path.join(frames, 'poster.png'), b);
			if (!enc.p.stdin.write(b)) await new Promise((r) => enc.p.stdin.once('drain', r));
			fs.unlinkSync(name(k));
			k++;
		} else if (exited !== null) break;
		else await sleep(15);
	}
	enc.p.stdin.end();
	const code = await enc.done;
	while (exited === null) await sleep(50);
	if (exited !== 0 || code !== 0 || k < count) {
		console.error(`reel: ${clip.id}: the run exited ${exited}, ffmpeg ${code}, ${k} of ${count} frames\n` + log.slice(-2000));
		return false;
	}
	if (fs.existsSync(path.join(frames, 'poster.png'))) {
		const p = ffmpeg(['-i', path.join(frames, 'poster.png'), '-q:v', '3', path.join(out, clip.id + '.jpg')]);
		p.p.stdin.end();
		await p.done;
	}
	fs.rmSync(frames, { recursive: true, force: true });
	const mb = fs.statSync(video).size / 1048576;
	console.log(`${clip.id.padEnd(10)} ${count} frames  ${mb.toFixed(1)} MB  ${((Date.now() - t0) / 1000).toFixed(0)}s`);
	return true;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const which = CLIPS.filter((c) => only.length === 0 || only.includes(c.id));
	let failed = 0;
	for (const c of which) if (!(await record(c))) failed++;
	process.exit(failed ? 1 : 0);
}
