# Afterglow

A calm puzzle in overgrown ruins over still black water, lit only by
what lives there: a tiny white moth whose light wakes glyphs that move
the stone, leading its young, a caterpillar, to its cocoon. GAME.md is
the game as designed and built; this is the code.

```sh
bun run helder run examples/afterglow          # drag or tap to fly; 1, 2, 3: a screen
bun run helder run --headless examples/afterglow --size 390x844 --scale 3 --snap out.png --at 3
bun run helder run --headless examples/afterglow --size 405x720 --scale 2 \
  --script examples/afterglow/play/first.json --snap home.png --at mark:home -- --log
bun run helder run --headless examples/afterglow --size 1920x1080 --snap sheet.png --at 2 -- --sheet
```

`-- --log` prints what happens as it does (`afterglow: screen 1: home at
12.3 s`: a script solved its screen), `-- --sheet` draws the two
characters alone under a lantern's light (standing, taking off, landing,
turning, six moments of a wingbeat; the caterpillar curled, waking and
crawling; both at a few sizes), `-- --detail 0.7` draws
the scene at that share of the screen's pixels each way (a slow device).

## How it plays

- **Screens** (Screens.hx): each screen as data: its stone (boxes,
  worn and with flat tops where something walks), its walks (x0, x1, y,
  z), its pieces (the stone that moves: a few poses each, dx, dy and a
  turn about a pivot; what carries the larva, what a pair of eyes holds
  open, what bars the way while shut, a lantern hung from another
  piece), its glyphs (what each moves), where the larva starts and its
  home.
- **Puzzle** (Puzzle.hx): one screen's play, stepped at a fixed 60 a
  second from where the moth is. Distances to the moth are taken as seen:
  each point brought along the line of sight to the plane the moth flies
  in. A glyph charges while a light is within reach and moves its pieces
  when full, then waits to go dark; eyes hold a piece open while all are
  lit; a woken lantern is a light. The larva crawls to the point of its
  way nearest the moth: the walks at its height joined, cut a little
  before a shut gate (it waits there), pieces that move left out (it
  rides the one carrying it). Pieces ease between poses with a little
  weight; a glyph near the moth stirs its stone towards its next pose and
  edges it violet (the hint).
- **Flight** (Flight.hx): the moth flies to where it is led (steered
  towards it, wings beating, facing its way, leaning into a climb), hovers
  a moment when it stops (long enough to wake what it stopped by), then
  drops to the walk below and stands, riding what it stands on. Beside
  what the play goes by it keeps what is only shown: turning to face its
  way, what trails behind it (antennae, abdomen and legs swing back from
  its speed and its change), reaching for the ground, having just landed.
- **Game** (Game.hx): the screens in turn, the pointer, the fixed steps,
  the pause and the fade into the mist between screens.
- **Playtests** (play/*.json): headless scripts that solve each screen,
  one that does the lift's in the wrong order first (no failure: the
  lift goes up empty, the larva waits), one that leaves the larva
  waiting at the shut gate first (gate.json: it once opened for it), and
  all three in a row. Their taps are in the world's coordinates on the
  moth's plane (wx, wy); `node examples/afterglow/play/aim.mjs 405x720`
  writes the window's points (x, y) for a window's size, as Afterglow
  frames it.

## How it is drawn

- **Stone** (Stones, Sdf, Builder): signed distance fields, meshed once
  (surface nets, Builder.field). Masonry is laid in blocks that stand in
  and out of its faces, a few gone, its courses in pairs whose middle
  joint is higher or lower, a block now and then as long as two
  (Stones.brick); PaintShader draws the
  joints of the same blocks (Mood.bricks: both from sequences that come
  out the same in a shader's floats), so relief and paint agree. A ledge
  has a lip over its top course and steps back under it (a corbel), its
  top courses fallen in steps, bites out of its lip; an arcade's broken
  bays open in steps; the great arch has two orders of voussoirs. Each
  vertex carries how open it is (crevices dark), how much moss covers it,
  how far below a ledge's top it is (only where that top is open above
  it), and the light of the glows about it (Builder.bake: nothing is
  summed a pixel). Faces that look away from the eye are never meshed.
- **Moss**: on what faces up; from each lip a fringe and drips of uneven
  length in clumps, bright where they start, their tips glowing
  (PaintShader, from the height below the top). Under the arch it hangs
  in strands, and dark vines from its crown.
- **Depth**: the screen's stone in front; the great arch over it all,
  veins glowing on its face, lanterns hung in it; through it a cliff of
  ledges and a bridge's last bays; behind them six planes of far ruins
  (FarShader): each one upright quad whose silhouette is worked out a
  pixel (tiers of arcades, tall arches under small ones, tops fallen in
  steps, posts left standing, a pier's thickness seen in each opening, a
  small glow here and there), its edge a pixel soft at any resolution,
  nothing to mesh. The mist is thick over the water and thinner higher
  up, so each plane stands paler than the one in front; shafts of light
  fall slanted between them (BeamShader).
- **Light comes from life.** The glows that stay light the stone through
  its vertices; those of the moment (a woken lantern, the cocoon as the
  caterpillar comes) are four of the view's; the moth's violet aura is
  one more. Everything else is a dim indigo ambient and a cold rim from
  the mist behind.
- **Lanterns**: a long drop of lattice about a heart of light seen
  through its lower cells, a knot over it, a tassel under it; small ones
  hang high under the arch's crown, with vines and moss (what a tall
  phone shows at its top). They are cocoons: the caterpillar's home is an
  empty one in a niche (GlyphShader), amber where the lanterns are
  magenta: an ember that brightens as it comes, lit once it is in.
- **The characters** (MothShader): no outline and no flat fill; form
  through light, as a lit model would have it, at the screen's own
  resolution. Each is one quad on which its parts are laid back to front,
  every part with a surface of its own: a colour, a normal as if modelled
  (domes for the body's segments, the head and the eye; a membrane for a
  wing, cambered between its veins, its lip turned to catch a rim), how
  hard it glints, how much light passes through it, how much rim it
  catches. Then it is lit once: every glow in reach is summed on the CPU
  (Afterglow.lights, some 150 of them, nothing a pixel) into six lights
  along the camera's axes, so nothing pops as a character moves, and one
  key light, where most of it comes from. The key falls in two hard
  steps; a wing lets light through; what lies over something shades it.
  Bodies are dark, so that the rim shows: a crisp band of what glows
  beside and behind, in its own colour and more (a lantern's pink, the
  cocoon's amber, the moss's green, the moth's violet). What is pale
  (the wings, the antennae) takes a light's tint and never its flood: by
  a lantern the moth is still a pale moth, with a pink rim on its body.
  They are left out of the finish: drawn once more into the target's
  alpha alone (the same shader, its shapes and no light: 1 everywhere
  else, over 1 where a character is), which the finish reads to leave
  those pixels as drawn, crisp against the paint. Where a quad is empty
  nothing is worked out.
  - *The moth* is the reference's: side on, pale wings swept back like a
    cape, feathered antennae in a V, a small dark body (fur combed back
    along it, seen by its paler strands; a pale collar behind the head;
    short jointed legs, the body low over them), a dark eye that only
    glints; it is lit from within (violet between its abdomen's
    segments, through its wings, most by the body). It is drawn 1.3 times
    the size it plays at, about its feet (Afterglow.DRAW: some 190 pixels
    with its antennae on a phone). A wing is one plan
    (root, apex, tornus: veins from the root, two wavering lines, a
    ringed spot, a scalloped hem with a fringe) laid on the screen along
    the body and out from it by how far it is raised: folded it lies
    back; beating it goes from over the back through edge on to under
    the body, quick down and slower up, its tip late, the hindwing after
    the forewing, the far pair a little ahead (its tip never through
    edge on before its root: no fold), the body bobbing against the
    stroke. At rest the wings breathe and now and then fan; taking
    off it dips first; landing it reaches down, dips on its legs and its
    wings flutter shut; turning it swings through edge on.
  - *The caterpillar*: fourteen segments, each a dome shorter than it
    is tall, so they part at deep creases; a dark hide with a paler
    gritty plate on each back and a wart where two bristles root; thin
    legs under the three by its head, four pairs of thick feet, a
    clasper; a dark glossy head with three small eyes and a pale shield
    behind it (the moth's collar); a horn on its tail with an amber ember
    (its cocoon's colour). Its own light keeps it seen in the dark: a
    spot on each segment's side, running from tail to head, and violet
    deep in the creases of its back (the moth's abdomen). It crawls as a hump running up its length, its
    front raised to the light when it waits; asleep it is wound into a
    ring.
- **Water**: the scene drawn mirrored into a target a third the size,
  read back stirred by ripples and smeared downwards.
- **The finish** (FinishShader, the last stage of PostProcess's chain:
  `post.add`): the scene is drawn multisampled (4 samples) in HDR at the
  screen's own resolution, bloomed and tone mapped, then finished at the
  screen's resolution in points (pixels over the window's scale), so a
  phone and a 5K screen show the same picture: edges wander half a point
  as a hand's would, strokes smear a little along their way, tone lies
  in soft bands whose borders wander, a brush's dabs and a paper's tooth
  lie over it, darks are pulled towards indigo. Its noise is one small
  tiling texture. No big pixels, no dither.
- **Resolution**: all of the screen's pixels up to a budget (6.6
  million: a 2880 x 1800 screen whole, a 5K one at two thirds each way,
  the finish always at the screen's own); `--detail` lowers it for a slow
  device. The bloom starts from a quarter on large targets, so it is as
  wide on any screen.
- **Framing** (Afterglow.frame): what is played with (3.3 units either
  side, 3.9 up and down on the stage's plane) is always in the frame: a
  narrow phone (9:21) sees more of the arch above and the water below, a
  wide window more of the ruin beside it; the roots in front (a stage's
  wings) change with it.

A frame is 15 passes and 36 draws over about 300,000 triangles (the
ruins 205,000, a screen about 95,000; 400,000 before faces looking away
were left out). Meshing the ruins takes about 1.1 s at start; the first frame, which
meshes the first screen and makes the pipelines, 1.3 s more (later
screens are meshed under the mist between screens). Start to first
frame was 2.9 s when the far ruins were meshes. Headless on an M-series Mac
(Metal), a frame's work with the harness reading every frame back:

| window | frame | of it, the scene at a tenth |
| --- | --- | --- |
| 1080 x 1920 | 11 ms | 6 ms |
| 1170 x 2532 (a phone) | 15 ms | 10 ms |
| 1920 x 1080 | 13 ms | |
| 2880 x 1800 | 22 ms | 15 ms |
| 5120 x 2880 | 40 ms | 33 ms |

The characters (two quads whose every pixel lays down some forty
shapes and is lit once) and their lights' sums added about 0.5 ms to a
phone's frame (alternating runs, the same script: 9.1 against 8.5 ms at
1170 x 2532; the table's figures are an earlier day's). The larger
moth, their second draw into the alpha and the finish reading it add
about 0.9 ms more (three alternating pairs at 1170 x 2532: 8.7, 9.1 and
10.2 against 7.8, 8.2 and 8.5 ms; of it the second draw 0.2, the
finish 0.15).

The second column is the same run with the scene drawn at a tenth each
way: the harness's reading back, the play and the finish; the difference
is the scene at full size (5 to 7 ms). The half-size, 2 x 2 pixel
version took 7.5 ms at 1080 x 1920. None of it has been measured on a
phone yet.
