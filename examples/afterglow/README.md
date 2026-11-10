# Afterglow: the look

One scene for look development (GAME.md is the game): a tiny white moth
on a ledge in overgrown ruins over still black water, lit only by what
lives there.

```sh
bun run helder run examples/afterglow
bun run helder run --headless examples/afterglow --size 1080x1920 --snap out.png --at 3
```

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
- **The glyph**: a hairline in the wall until the moth comes within about
  two units; then it lights from the moth's side first.
- **Water**: the ruins near (not the far planes) and the moth drawn
  mirrored into a half-size target, read back stirred by ripples and
  smeared downwards.
- **The moth** is the reference's: side on, standing, its pale wings
  folded down and back like a cape with lilac crescents and a scalloped
  hem, fern antennae in a V, a round head with a dark eye, thin legs;
  drawn from shapes in its shader, its wings breathing and its antennae
  swaying. A soft violet halo; motes drifting, moved by the GPU.
- **The finish**: helder.scene's HDR renderer (the injection points) and
  PostProcess (bloom, ACES) at half the screen (the shorter side about
  540 pixels), shown in 2 x 2 pixels with an ordered dither, brush dabs,
  and the darks pulled towards indigo (FinishShader): the same grain over
  everything.
- **Framing**: a phone's portrait view and a wide one share the scene;
  the camera and the roots in front (a stage's wings) change with the
  aspect.

A frame is 15 passes and 24 draws over about 400,000 triangles; nothing
is allocated per frame beyond the frame loop's own. On an M-series Mac
(Metal, headless) a 1080 x 1920 frame takes about 6.3 ms (the first pass
took 3.7 there); meshing the fields takes about 2 s at start. Neither has
been measured on a phone yet.
