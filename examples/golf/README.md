# Floating Greens

Mini golf on floating islands: helder's first game, in Haxe. Eighteen
holes on three islands, each island bringing in its own pieces and then
twisting them, so that on the later holes the puzzle is finding the route,
not only aiming. Play it at https://floating-greens.helder.run, on the
examples site (site/; on Android its card has the APK), or:

```sh
bun run helder dev examples/golf                    # a window, live-reloaded
bun run helder dev examples/golf --target web       # the browser
bun run helder run examples/golf/Golf.hx --target android   # a phone or an emulator
bun run helder run examples/golf/Golf.hx --target ios-sim   # the iOS simulator
```

## The islands

| | Hole | Par | Brings in |
|---|---|---|---|
| **Meadowdrift** (spring day) | 1 First Putt | 2 | the shot |
| | 2 The Bend | 2 | banking off a rail |
| | 3 Uphill | 2 | slopes |
| | 4 Pinball | 2 | bumpers, kicking the ball away |
| | 5 Sandy Shortcut | 2 | sand: the straight line, or round by the fast lane |
| | 6 The Leap | 2 | a kicker over a gap |
| **Copperwind Cliffs** (sunset) | 7 Sliders | 2 | blocks sliding across the lane |
| | 8 Turnstile | 2 | turnstiles, turning opposite ways |
| | 9 Crosswind | 2 | wind on a bridge without rails (in the air too) |
| | 10 Booster Run | 2 | boosters up a slope too steep for a putt |
| | 11 Lift Off | 3 | a lift: stop on it, ride up, shoot off |
| | 12 Roundabout | 3 | a one-way gate: the cup's pen opens only from the far side |
| **Lanternwater** (dusk) | 13 Skipping Stone | 2 | water (a stroke): over the pool, or down round it |
| | 14 Wormhole | 2 | a portal to an island with no bridge |
| | 15 Flip Switch | 3 | a switch in a bay opening the gate across the lane |
| | 16 Brittle Bridge | 4 | crumbling tiles to the switch; back by the portal through the gate it opened |
| | 17 Two Doors | 3 | one switch group: as one gate opens the other shuts, a plate between them |
| | 18 Moonrise | 4 | portal, turnstile, switch and a gated pen together |

Stars: three for par or better, two for one over, one for finishing. Every
hole has a recorded round at or under par (GolfReplay).

## Controls

- **Shoot**: put a finger (or the mouse) on the ball, drag back, let go.
  The dots show where it goes: the ball's own path, played ahead by the
  simulation, bending off the rails, clear up to the first bounce (a gold
  dot) and fading soon after, ending in a red dot at a bumper, gate,
  turnstile or sliding block in the way. The band behind the ball and the
  readout beside it show how hard: the farther you pull, the harder, up
  to a full pull of 150 points; let go within 14 points of the ball and
  nothing is played.
- **Look around**: drag anywhere else to turn the camera round the ball;
  pinch to zoom, twist with two fingers to turn (the mouse: drag, the
  wheel). While the ball rolls the camera eases round behind it, and when
  it stops it turns to face the cup, unless you moved it a moment ago. As
  a hole starts the camera flies from the cup back to the tee under the
  hole's card (a press skips it).
- **Holes**: the hole's pill (top left) opens the scorecard: each island's
  holes with par, stars and your best. After a hole-in: Retry or Next.
  Falling off, or into the water, puts the ball back where you hit it
  from (the last place it rested on fixed ground), a stroke more; cracked
  tiles are whole again. Best scores are saved (helder.os's `Store`).

## How it is built

- `Course.hx`: the islands (`worlds`: their sky, colours, sun, fog) and the
  holes as data, each a list of pieces: `Flat`, `RampZ`/`RampX`, `Wall`,
  `Block`, `Post`, `Bumper`, `Mover`, `Spinner`, `Lift`, `Boost`, `Wind`,
  `Sand`, `Ice`, `Water`, `Portal`, `Switch`, `Gate`, `OneWay`, `Crumble`,
  with a tee, a cup, a par and a tip for the hole's card. A new hole is an
  entry there and nothing else.
- `Sim.hx`: one hole on helder.physics at 120 steps a second: the ball a
  sphere sliding with a little Coulomb friction (standing for a roll's
  resistance; the view rolls it) and a drag in proportion to its speed;
  rails, posts and bumpers bounce it; movers, lifts, turnstiles and gates
  are static bodies placed each step with their velocities set (contacts
  see them). The pieces' own rules run after the physics' step: bumpers
  kick, boosters and wind push, sand and ice change the going, portals
  move the ball keeping its speed, switches swap their group's gates
  (which slide into the green), one-way lines bounce a ball coming the
  wrong way, tiles fall once rolled off. No sin, cos or exp in a step
  (`Sim.yaw` turns a turnstile by series and doublings): the same shots
  give the same bits natively and as wasm32-wasi.
- `GolfReplay.hx`: every hole's recorded round (each shot a direction, a
  speed and how many steps to wait once the ball rests), replayed on the
  simulation alone, natively and as wasm32-wasi (the examples lane); each
  must hole in its strokes and allocate only while the physics' buffers
  grow; before each shot the aim's preview, played to the end, must leave
  the ball where the shot does, bit for bit, and a fan of previews from
  each tee must allocate nothing. `GolfReplay search N [shots] [x z]` finds
  the next shot after the given ones; `trace N shots` follows the ball;
  `preview N dx dz speed` shows where a shot's preview bounces and ends.
- `Aim.hx`: the aim's preview: a ghost of the hole's simulation set to
  the live one's state (`Sim.mirror`: the same step, so the turnstiles,
  lifts and gates are where they will be) and played on with the shot
  being aimed, at most 360 steps and only as far as is shown; its buffers
  made once, worked again only when the aim changes (or, on a hole with
  moving pieces, the step).
- `Game.hx`: the scene's nodes made from the pieces (`Kit.hx`'s unit
  meshes, flat shaded, scaled per piece: drawn instanced), each island's
  light, colours and fog, the camera (`<OrbitControls>` driven by the game:
  the fly-over, following, facing the cup, in close round the cup on a
  hole-in), the pieces' motion between steps, and the juice: particles
  (`Particles.hx`: one InstancedMesh a pool: dust, a trail, splashes,
  sparks, confetti, fireflies at dusk), ripples, birds, lanterns, a squash
  along each hit, a shake on hard ones, slow motion. A frame of play
  allocates nothing (`GOLF_DEMO=<hole>` plays the recorded round and prints
  the frames' GcStats and draw count natively; `GOLF_PLAY=<hole>` starts a
  hole, `GOLF_AIM=<hole>,<dx>,<dz>,<power>` holds an aim on it, the
  preview shown and the frames' GcStats printed, `GOLF_MENU` opens the
  scorecard).
- `Golf.hx`: the window (`<Surface>`, the island's sky), a `<Scene hdr>`
  (bloom, a light vignette: emissive portals, switches and lanterns glow)
  and the title, hole card, HUD, card and scorecard in ui's markup, clear
  of a phone's bars, laid out for a phone upright and a window on its side.
  Set in Nunito (the numbers, labels, tips, buttons and scorecard), the
  title and the holes' names in Fredoka at a medium weight (fonts/, both
  SIL Open Font License), embedded. Nunito is its variable font cut to
  Latin, its legacy family name set to "Nunito".
- `Sounds.hx`: a tock, knocks, a thud, a boing, a warp, a click and a
  rumble, a crumble, a splash, a whoosh, the cup's plunk and a chime, all
  made procedurally and mixed by helder.os's `Sfx` (desktop and the web).

Tests: `GolfReplay.hx` (the examples lane), the site check (`bun run site
&& bun run site:check`: golf full screen and expanded at 390x844, Play
pressed, the fly-over skipped, a touch drag from the ball shooting it),
CI's emulator and simulator (tests/pack/android.sh, ios.sh).
