// The greybox prototypes' playtests: each screen's moves in the board's
// cells (wx, wy: from its bottom left, y up; a drag's wdx, wdy), written as
// a headless script's points (x, y, dx, dy) for a window's size, as
// Greybox lays the board out (Greybox.view: the same numbers).
//
//   node examples/afterglow/play/greybox.mjs 390x844     (writes play/greybox/*.json)
import {writeFileSync} from 'node:fs'
import {dirname, join} from 'node:path'
import {fileURLToPath} from 'node:url'

const BAR = 56, FOOT = 44, EDGE = 14, COLS = 7, ROWS = 9
const dir = join(dirname(fileURLToPath(import.meta.url)), 'greybox')

function view(w, h) {
  const s = Math.min((w - EDGE * 2) / COLS, (h - BAR - FOOT - EDGE) / ROWS)
  return {s, x: (w - COLS * s) / 2, y: BAR + (h - BAR - FOOT - ROWS * s) / 2}
}

const tap = (t, wx, wy) => ({t, type: 'tap', wx, wy})
const drag = (t, wx, wy, wdx, wdy) => ({t, type: 'drag', wx, wy, wdx, wdy, dur: 0.4})
const mark = (t, name) => ({t, type: 'mark', name})

// (a cell's middle: i + 0.5, j + 0.5)
export const screens = {
  a1: [mark(0.4, 'start'), tap(0.5, 2.5, 2.5), tap(2.5, 2.5, 6.5), tap(3, 2.5, 6.5), mark(5, 'solved')],
  a2: [mark(0.4, 'start'), tap(0.5, 1.5, 1.5), tap(2, 4.5, 1.5), tap(2.4, 4.5, 1.5), drag(3, 4.5, 3.5, 1, 0),
    tap(4.2, 4.5, 6.5), mark(6, 'solved')],
  a3: [mark(0.4, 'start'), tap(0.5, 5.5, 7.5), tap(3.2, 3.5, 7.5), tap(3.6, 3.5, 7.5), drag(4.2, 3.5, 3.5, -1, 0),
    tap(5.2, 3.5, 1.5), mark(9, 'solved')],
  b1: [mark(0.4, 'start'), tap(0.5, 4.5, 1.5), tap(2.5, 2.5, 6.5), tap(5.5, 5.5, 7.5), mark(9, 'solved')],
  b2: [mark(0.4, 'start'), tap(0.5, 4.5, 3.5), tap(3.5, 5.5, 5.5), tap(6.5, 2.5, 7.5), mark(10, 'solved')],
  b3: [mark(0.4, 'start'), tap(0.5, 5.5, 2.5), tap(3, 1.5, 5.5), tap(6, 5.5, 7.5), tap(9, 1.5, 7.5), mark(12, 'solved')]
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [w, h] = (process.argv[2] ?? '390x844').split('x').map(Number)
  const v = view(w, h)
  const at = (wx, wy) => [Math.round(v.x + wx * v.s), Math.round(v.y + (ROWS - wy) * v.s)]
  for (const [name, events] of Object.entries(screens)) {
    const out = events.map(e => {
      if (e.wx === undefined) return e
      const [x, y] = at(e.wx, e.wy)
      return e.type === 'drag' ? {...e, x, y, dx: Math.round(e.wdx * v.s), dy: Math.round(-e.wdy * v.s)} : {...e, x, y}
    })
    const lines = out.map(e => '  ' + JSON.stringify(e).replace(/,"/g, ', "').replace(/":/g, '": '))
    writeFileSync(join(dir, name + '.json'), `{"events": [\n${lines.join(',\n')}\n]}\n`)
  }
}
