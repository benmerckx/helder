# Floating Greens

Mini golf on floating islands: helder's first game (the roadmap's phase 4),
nine short holes for a phone, in Haxe. Play it on the examples site
(site/, deployed by the pages workflow: its Full screen button; on Android
its card has the APK), or:

```sh
bun run helder dev examples/golf/Golf.hx                    # a window, live-reloaded
bun run helder build examples/golf/Golf.hx --target web     # bin/web/Golf.html
bun run helder run examples/golf/Golf.hx --target android   # a phone or an emulator
bun run helder run examples/golf/Golf.hx --target ios-sim   # the iOS simulator
```

## Controls

- **Shoot**: put a finger (or the mouse) on the ball, drag back, let go.
  The dots show where it goes, the bar under the course how hard: the
  farther you pull, the harder, up to a full pull of 150 points; let go
  within 14 points of the ball and nothing is played.
- **Look around**: drag anywhere else to turn the camera round the ball;
  pinch to zoom, twist with two fingers to turn (the mouse: drag, the
  wheel). While the ball rolls the camera eases round behind it, and when
  it stops it turns to face the cup, unless you moved it a moment ago.
- **Holes**: the hole's pill (top left) opens the menu: every hole with
  its par, stars and your best. After a hole-in: Retry or Next hole.
- **Stars**: three for par or better, two for one over, one for finishing.
  Falling off an island puts the ball back where you hit it from, a
  stroke more. Best scores are saved (helder.os's `Store`: a file in the
  app's data directory, localStorage on the web).

## How it is built

- `Course.hx`: the holes as data, each a list of kit pieces (`Flat`,
  `RampZ`/`RampX`, `Wall`, `Block`, `Post`, `Mover`) with a tee, a cup and
  a par; `Course.rails` draws a rail round a rectangle. A new hole is an
  entry there and nothing else.
- `Sim.hx`: one hole on helder.physics at 120 steps a second: the ball a
  sphere sliding with a little Coulomb friction (standing for a roll's
  resistance; the view rolls it), a drag in proportion to its speed, rails
  and posts bouncing it, moving blocks as static bodies moved each step with
  their velocity set (contacts see it), a gentle funnel round the cup and
  a capture below 1.9 m/s, a fall putting it back with a stroke. No sin,
  cos or exp in a step: the same shots give the same bits natively and as
  wasm32-wasi (`GolfReplay.hx`, the examples lane).
- `ShotGesture.hx`: a recogniser in ui's gesture arena that, pressed near
  the ball, wins the pointer at once, before any slop, so the
  `<OrbitControls>` on the same `<Scene>` box only get presses elsewhere.
- `Game.hx`: the scene's nodes made from the pieces (`Kit.hx`'s unit
  meshes, flat shaded, scaled per piece: drawn instanced), the camera
  (`<OrbitControls>` driven by the game too: following, facing the cup, a
  look ahead of the ball on a tall screen), and the juice: a trail, a
  squash along each hit's direction (a spring back), a shake on hard ones,
  slow motion, confetti, a ring and the flag rising on a hole-in. A frame
  of play allocates nothing (`GOLF_DEMO=4 bin/golf` prints the frames'
  GcStats natively).
- `Golf.hx`: the window (`<Surface>`, a sky gradient), the `<Scene>` and
  the HUD and menu in ui's markup on helder.view's graph, clear of a
  phone's bars (`env(safe-area-inset-*)`).
- `Sounds.hx`: a tock, a knock, the cup's rattle and plunk, a whoosh and
  a chime, made procedurally and mixed by helder.os's `Sfx` (desktop and
  the web; silent on phones, which have no audio back end yet).

Tests: `GolfReplay.hx` (six recorded rounds holed in their strokes,
natively and as wasm32-wasi; the examples lane), the site check
(`bun run site && bun run site:check`: golf played, full screen and
expanded at 390x844, a touch drag from the ball shooting it), CI's
emulator and simulator (tests/pack/android.sh, ios.sh: built, started, its
first frames, a screenshot).
