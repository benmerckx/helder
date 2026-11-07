# The UI in one draw call (helder.ui's renderer)

helder.ui's renderer (src/helder/ui/draw: `Renderer`, `UiShader`) before
and after it became one instanced pass (Rune's uber-quad,
anomalyco/rune, MIT): every rect, border, shadow (outer and inset),
glyph and image an instance of one quad, its kind, clip and corners in
the instance; small images (up to 256 px a side: paths, SVGs, gradients,
colour glyphs) in 1024 px atlas pages; the instances in a ring of three
buffers, each written where it changed. Measured 2026-11-07 with
`helder run --headless --stats` (its `passes`, `draws`, `textures`,
`quads`, `uiMs`, `encodeMs`, `uploaded`: src/helder/cli/README.md) on
Mesa's llvmpipe (a GPU in software), a 4-core VM shared with other
builds; medians over the frames drawn.

The screens: AccessApp's (tests/ui: GuideTest's widgets, todo with two
items, mail) under a script of 180 pointer moves (a hover a frame); the
studio (apps/studio on a copy of examples/todo, tests/studio/edit.json,
zoomed with three previews shown); MotionStress (the motion-bench lane:
1,000 boxes under motion); examples/million (tests/headless/million.json);
examples/code-editor (tests/headless/code-editor.json).

| screen | quads | passes | draw calls (max) | textures bound | renderer CPU ms | of it draw calls | renderer without draw calls | uploaded KB |
|---|---|---|---|---|---|---|---|---|
| GuideTest's screen | 82 | 1 → 1 | 3 (3) → 1 (1) | 6 → 2 | 0.116 → 0.110 | 0.059 → 0.061 | 0.059 → 0.048 | 46 → 0 |
| todo | 89 | 1 → 1 | 1 (1) → 1 (1) | 2 → 2 | 0.110 → 0.110 | 0.065 → 0.073 | 0.043 → 0.035 | 50 → 0 |
| mail | 300 | 1 → 1 | 1 (1) → 1 (1) | 2 → 2 | 0.250 → 0.231 | 0.153 → 0.151 | 0.096 → 0.079 | 169 → 23 |
| the studio (three previews) | 167 | 1 → 1 | 10 (12) → 4 (5) | 20 → 5 | 0.237 → 0.218 | 0.154 → 0.148 | 0.080 → 0.068 | 94 → 16 |
| motion-bench (1,000 boxes moving) | 1001 | 1 → 1 | 1 (1) → 1 (1) | 2 → 2 | 0.715 → 0.747 | 0.474 → 0.581 | 0.237 → 0.162 | 563 → 188 |
| million | 750 | 1 → 1 | 1 (1) → 1 (1) | 2 → 2 | 0.570 → 0.471 | 0.369 → 0.316 | 0.183 → 0.150 | 422 → 135 |
| code-editor | 1281 | 1 → 1 | 1 (1) → 1 (1) | 2 → 2 | 0.683 → 0.704 | 0.400 → 0.482 | 0.273 → 0.212 | 721 → 17 |

- **Draw calls**: one a frame on every screen but the studio's. Before,
  each path or image (an icon) split the run (GuideTest's search icon:
  3 draws); now they share an atlas page. The studio's previews are
  larger than a page takes (about 490 x 570 px each), each a texture of
  its own, so the draw splits where one is bound: 4 draws, from 10.
- **Passes**: one a frame on every screen. helder.ui has no opacity
  groups, filters or backdrop effects (opacity multiplies each quad's
  colour; a blur transition fades), so nothing needs a pass of its own;
  a `<Scene>`'s passes come before the frame's (`beforePass`), none on
  these screens.
- **CPU**: "renderer CPU" is from the renderer's begin, through
  helder.ui's painting, to its pass encoded; "of it draw calls" is the
  driver's work inside the encoder's calls, which on llvmpipe includes
  the vertex stage (instanced draws cost it more per quad: 0.58 ms for
  1,000). The renderer's own work, without them, is 0.035 to 0.21 ms a
  frame, against Rune's 0.13 ms (its 174 instances, on Apple silicon).
- **Upload**: an instance is 192 bytes against four 144-byte vertices,
  and only the bytes that differ from what the ring's buffer held are
  written: a hover's frame uploads nothing or a few instances.
- **Allocation**: the renderer allocates nothing in a steady frame
  (motion-bench: 0 bytes from its begin to its end, painting included).
  What todo's and mail's frames still allocate is helder.ui's painting
  of hovered nodes, outside the renderer.
- **Pixels**: the corners are still placed by the CPU in doubles, so the
  goldens are unchanged: ui-draw's draw, window, todo and emoji exact,
  headless-run's and the studio's exact, ui-web's todo the same 618
  pixels off on WebGPU and WebGL2 as before; BoxTest (within a tolerance)
  1 pixel 1 level from before.
