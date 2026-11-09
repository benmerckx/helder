# Afterglow: the look

One scene for look development (GAME.md is the game): a tiny white moth
on a ledge in overgrown ruins over still black water, lit only by what
lives there.

```sh
bun run helder run examples/afterglow
bun run helder run --headless examples/afterglow --size 1080x1920 --snap out.png --at 3
```

## How it is drawn

- **The ruins** (Ruins, Builder): boxes, arcades with arched openings,
  tubes for roots, veins and hanging moss, lathed mushrooms and lanterns,
  all built in code into one vertex buffer. One shader (PaintShader) paints
  each surface by its kind: stone blocks from the world's coordinates, moss
  on what faces up and over the edges, bark, glowing caps, gills, sprouts,
  the lanterns' lattice. Moss and lanterns sway in the vertex stage.
- **Light comes from life.** The glows are lights (a 2 x 32 RGBA16F
  texture, the lanterns' swaying with them); the moth's violet aura is one
  more, and reveals the glyph on the wall within its radius. Everything
  else is a dim indigo ambient and a cold rim from the mist behind.
- **Mist**: darker upwards, mottled, slanted beams, glowing low in the
  far distance, so each layer of arches stands darker against the next.
- **Water**: the ruins (and the moth) drawn mirrored into a target of
  their own, read back stirred by ripples and smeared downwards.
- **The moth**: a cutout drawn from shapes in its shader (quads and
  ellipses for wings, feathered antennae), its wings folding as they
  beat; a soft violet halo; motes drifting, moved by the GPU.
- **The finish**: helder.scene's HDR renderer (the injection points) and
  PostProcess (bloom, ACES) at a third of the screen (the shorter side
  about 360 pixels), shown in big pixels with an ordered dither, brush
  dabs, and the darks pulled towards indigo (FinishShader).
- **Framing**: a phone's portrait view and a wide one share the scene;
  the camera and the roots in front (a stage's wings) change with the
  aspect.

A frame is 15 passes and 23 draws; nothing is allocated per frame beyond
the frame loop's own. On an M-series Mac (Metal, headless) a 1080 x 1920
frame takes 3.7 ms (p95 4.8 ms); it has not been measured on a phone yet.
