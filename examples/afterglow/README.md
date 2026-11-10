# Afterglow

A calm puzzle in overgrown ruins over still black water, lit only by
what lives there: a tiny white moth whose light wakes glyphs that move
the stone, leading a snail home. GAME.md is the game as designed and
built; this is the code.

```sh
bun run helder run examples/afterglow          # drag or tap to fly; 1, 2, 3: a screen
bun run helder run --headless examples/afterglow --size 1080x1920 --snap out.png --at 3
bun run helder run --headless examples/afterglow --size 405x720 --scale 2 \
  --script examples/afterglow/play/first.json --snap home.png --at mark:home
```

## How it plays

- **Screens** (Screens.hx): each screen as data: its stone (boxes,
  worn and with flat tops where something walks), its walks (x0, x1, y,
  z), its pieces (the stone that moves: a few poses each, dx, dy and a
  turn about a pivot; what carries the snail, what a pair of eyes holds
  open, what bars the way while shut, a lantern hung from another
  piece), its glyphs (what each moves), where the snail starts and its
  home.
- **Puzzle** (Puzzle.hx): one screen's play, stepped at a fixed 60 a
  second from where the moth is. Distances to the moth are taken as seen:
  each point brought along the line of sight to the plane the moth flies
  in. A glyph charges while a light is within reach and moves its pieces
  when full, then waits to go dark; eyes hold a piece open while all are
  lit; a woken lantern is a light. The snail crawls to the point of its
  way nearest the moth: the walks at its height joined, cut by shut
  gates, pieces that move left out (it rides the one carrying it).
  Pieces ease between poses with a little weight; a glyph near the moth
  stirs its stone towards its next pose and edges it violet (the hint).
- **Flight** (Flight.hx): the moth flies to where it is led (steered
  towards it, wings beating, facing its way, leaning into a climb), hovers
  a moment when it stops (long enough to wake what it stopped by), then
  drops to the walk below and stands, riding what it stands on.
- **Game** (Game.hx): the screens in turn, the pointer, the fixed steps,
  the pause and the fade into the mist between screens.
- **Playtests** (play/*.json): headless scripts that solve each screen,
  one that does the lift's in the wrong order first (no failure: the
  lift goes up empty, the snail waits), and all three in a row.

## How it is drawn

- **The ruins** (Stones, Sdf, Builder): stone is signed distance fields,
  meshed once at start (surface nets, Builder.field), so nothing is a box:
  walls and arcades whose top courses have fallen in steps, some bays
  broken through from above, ends crumbling away, edges rounded and worn
  by noise at their own scale, footings sunk in rubble; slabs with ragged
  outlines and bites out of their lips; towers tapering to a slanted
  break. Each vertex carries how open it is (the field probed along its
  normal, so crevices are dark), how much moss covers it, and how far
  below a ledge's top it is. Roots are knotted strands twisting about a
  path; mushrooms and lanterns are lathed, strands and veins are tubes
  (veins hug the arch's face). One shader (PaintShader) paints each
  surface by its kind: blocks in wavering hand-drawn courses, moss on what
  faces up, and moss hanging below each top in strands of uneven length,
  in clumps, their tips glowing.
- **Depth**: planes one behind another, each larger and paler: the moth's
  ledge and its cliff, the great arch, a low bridge, then aqueducts at 16,
  26, 42 and 60 units, towers further off. The mist is thick over the
  water and thinner higher up (bases dissolve, tops stay readable), teal
  at the horizon, blue above, violet high up, so each plane stands lighter
  than the one in front. Shafts of light fall slanted through it between
  the planes (BeamShader, additive), and dark vines hang from the arch's
  crown against it.
- **Light comes from life.** The glows are lights (a 2 x 32 RGBA16F
  texture, the lanterns' swaying with them; the far planes skip them); the
  moth's violet aura is one more. Everything else is a dim indigo ambient
  and a cold rim from the mist behind.
- **A screen's stone** is meshed when the screen is first shown (Ruins.screen,
  its own buffers): screen 1's at start, the others under the mist
  between screens. Its pieces are meshed as built and posed in
  PaintShader's vertex stage (the view's pose and pivot: a draw each,
  with the moth's hint and a lantern's light).
- **Glyphs** (GlyphShader): a sigil, an eye, the home's door, quads on
  the stone's faces (kept flat there when meshed); carved hairlines that
  breathe faintly, lit from the moth's side as it comes near, filling as
  they charge. Their states are an array in one uniform block: one draw.
- **Water**: the ruins near (not the far planes) and the moth drawn
  mirrored into a half-size target, read back stirred by ripples and
  smeared downwards.
- **The moth** is the reference's: side on, standing, its pale wings
  folded down and back like a cape with lilac crescents and a scalloped
  hem, fern antennae in a V, a round head with a dark eye, thin legs;
  drawn from shapes in its shader, its wings breathing and its antennae
  swaying; in flight its legs tuck up and its wings beat about the
  shoulder. A soft violet halo; motes drifting, moved by the GPU.
- **The snail** is drawn the same way (MothShader's third shape): a
  spiral shell with a faint glowing line, so it reads in the dark, its
  body out of it by how awake it is, rippling as it crawls.
- **The finish**: helder.scene's HDR renderer (the injection points) and
  PostProcess (bloom, ACES) at half the screen (the shorter side about
  540 pixels), shown in 2 x 2 pixels with an ordered dither, brush dabs,
  and the darks pulled towards indigo (FinishShader, the chain's own last
  stage: `post.add`, read Nearest, into the frame): the same grain over
  everything, and the fade into the mist between screens. The mist stays
  the shaders' own (Mood.haze): its colour follows the view (teal low,
  violet high, shafts in it), which helder.scene's Fog, one colour, can't.
- **Framing**: a phone's portrait view and a wide one share the scene;
  the camera and the roots in front (a stage's wings) change with the
  aspect.

A frame is 15 passes and 33 to 35 draws over about 400,000 triangles;
the play allocates a few small arrays a step (about 4.5 KB a frame, the
look alone 2.8). On an M-series Mac (Metal, headless) a 1080 x 1920 frame
takes about 7.5 ms (the look alone 6.4; the first pass took 3.7 there);
meshing takes about 2.9 s at start and about 1 s for each later screen,
under the mist. None of it has been measured on a phone yet.
