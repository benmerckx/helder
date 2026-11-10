// The play scripts' taps are in the world's coordinates on the moth's
// plane (wx, wy); this writes their window points (x, y) for a window's
// size, as Afterglow frames it (Afterglow.hx: stage, the same numbers).
//
//   node examples/afterglow/play/aim.mjs 405x720            (rewrites play/*.json)
//   node examples/afterglow/play/aim.mjs 390x844 first.json out.json
import {readFileSync, writeFileSync, readdirSync} from 'node:fs'
import {dirname, join} from 'node:path'
import {fileURLToPath} from 'node:url'

const FLY = -1.25
const dir = dirname(fileURLToPath(import.meta.url))

const sub = (a, b) => a.map((v, k) => v - b[k])
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
const unit = a => a.map(v => v / Math.hypot(...a))

export function stage(aspect) {
  const half = Math.max(3.9, 3.3 / aspect)
  const wide = Math.min(Math.max((aspect - 0.5625) / (1.7778 - 0.5625), 0), 1)
  const bottom = -0.9 - (half - 3.9) * 0.37
  const to = [-0.05 + 0.35 * wide, bottom + half, -2.3]
  const d = 6.5 + half * 0.6
  const from = [to[0] + 0.2, 2.4 + (to[1] - 3) * 0.2, to[2] + d]
  return {from, to, tan: half / Math.hypot(...sub(to, from))}
}

export function project(size, wx, wy) {
  const [w, h] = size, aspect = w / h
  const {from, to, tan} = stage(aspect)
  const back = unit(sub(from, to)), right = unit(cross([0, 1, 0], back)), up = cross(back, right)
  const r = sub([wx, wy, FLY], from), z = -dot(r, back)
  const nx = dot(r, right) / z / (tan * aspect), ny = dot(r, up) / z / tan
  return [Math.round((nx + 1) / 2 * w), Math.round((1 - ny) / 2 * h)]
}

function rewrite(size, file, out) {
  const script = JSON.parse(readFileSync(file, 'utf8'))
  for (const e of script.events)
    if (e.wx !== undefined) [e.x, e.y] = project(size, e.wx, e.wy)
  const lines = script.events.map(e => '  ' + JSON.stringify(e).replace(/,"/g, ', "').replace(/":/g, '": '))
  writeFileSync(out, `{"events": [\n${lines.join(',\n')}\n]}\n`)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [size, file, out] = process.argv.slice(2)
  const wh = (size ?? '405x720').split('x').map(Number)
  if (file) rewrite(wh, join(dir, file), out ?? join(dir, file))
  else
    for (const f of readdirSync(dir))
      if (f.endsWith('.json')) rewrite(wh, join(dir, f), join(dir, f))
}
