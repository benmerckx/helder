# helder.sprite

2D sprites on helder.gfx: a batcher of textured quads, TexturePacker's
atlases, and a box in ui's layout to draw them in. A first slice of the
roadmap's 2D package (sprite batches; tilemaps later), made for a game
of sprites from an atlas (benmerckx/expansion's).

```haxe
import helder.sprite.*;
import helder.sprite.SpriteTags.*;

var atlas = Atlas.parse(json);                         // TexturePacker: JSON (Array) or JSON (Hash)
var batch = new SpriteBatch(device);
var sheet = batch.add(image);                          // a helder.image.Image, uploaded premultiplied
batch.begin(width, height);                            // drawing units, x right, y down
batch.sprite(sheet, atlas.get("ship"), x, y, angle, 1, 1, 0.8);        // about its source's centre
batch.sprite(sheet, atlas.get("glow"), x, y, 0, 2, 2, 1, true);        // added (canvas's "lighter")
batch.image(sheet, sx, sy, sw, sh, x, y, w, h);        // a part of a texture over a rectangle
enc.beginPass(pass); batch.flush(enc); enc.endPass();

// in ui's markup: a box of its own size, drawn into a texture before ui's pass
<Sprites grow={1} animate onReady={b -> sheet = b.add(image)} onDraw={(b, w, h) -> draw(b, w, h)}/>
```

- `SpriteQuads` is the CPU half: four vertices a quad (`SpriteShader`'s
  position, texel and premultiplied colour), any affine transform,
  a rotated frame's texels read a quarter turned, and the runs (one
  draw each: the quads in order with one texture). Kept between frames,
  so a steady frame allocates nothing.
- `SpriteBatch` uploads them into one vertex buffer and draws each run in
  one pipeline (Blend.Premultiplied): an alpha sprite's colour carries its
  alpha, an additive one's none, which that blend adds, so both mix in one
  run. Layers are the order drawn in.
- `Atlas` reads a sheet's frames: the rectangle, `rotated`, the trim
  (`spriteSourceSize` in `sourceSize`): a sprite is placed about the
  centre of its untrimmed source, as it was drawn.
- `SpriteBox` (`<Sprites>`): a ui node whose `onDraw` fills its batch at
  its size each frame it paints (every frame while `animate`), drawn into
  a render target of its pixel size and shown as its content, as a
  `<Scene>`'s box is; its gestures and listeners are a ui node's (put
  them on a `<view>` around it).

Tests: `Atlas.test.hx` and `SpriteQuads.test.hx` (natively and as
wasm32-wasi: the test lane), `bun run test sprite` (a headless GPU frame
read back: placed, scaled, faded, added, two textures; tests/sprite/SpriteFrame.hx).

Later: mip maps or pre-scaled frames chosen by scale (a game's own today),
a sprite's tint in markup, tilemaps, nine-slices, sprites as scene nodes.
