# helder.story

Stories, as Storybook's: a component shown in a state, with controls, a
test of it, and (marked for the store) a store screenshot.

```haxe
// tests/story/Card.story.hx
package story;

import helder.story.Story;

function stories() {
  story("Card/plain", c -> card(c.text("title", "Fleet"), c.number("ships", 3)));
  story("Store/fleet", c -> card(c.text("title", "Your fleet"), c.number("ships", 10 + Std.int(c.random() * 90))))
    .store({caption: "Command a fleet", seed: 7});
}
```

- **Files**: `*.story.hx` anywhere a test file may be (src/, tests/, the
  project's class paths), a module-level `stories()` registering them;
  linked as test files are (`Foo_story.hx`), so the app's own builds never
  contain them.
- **Controls** (`Controls`): `number`, `bool`, `text`, `choice`, `color`,
  each a signal of helder.view's with its name and kind recorded (an
  editor's later); `random()`, the seed's numbers (xorshift); `settled`, a
  signal a story sets false while it loads, which the renderers wait for.
- **Tests**: `helder test` runs each story file's stories as tests: each
  mounted headless in a phone's size (390x844 points) with text laid out
  without fonts (`StoryText`: the same everywhere, wasm too), transitions
  finished (helder.ui's Clock), its tree (tags, boxes, texts) against the
  snapshot in `Foo.story.snap` (`helder test -u` rewrites it).
- **Store screenshots** (`StoreShots`, `helder publish --screenshots`):
  each story marked `.store()` rendered offscreen on the GPU (Mesa's
  llvmpipe on Linux) at the stores' sizes as a real layout (iPhone 6.9"
  1320x2868 and 6.5" 1284x2778 at 3x, iPad 13" 2064x2752 at 2x, an
  Android phone 1080x1920; swapped for a landscape app), text in the
  system's fonts, its caption in a band over it (`StoreOptions`: caption,
  colours, seed), written as opaque RGB PNGs (no alpha channel, Apple's
  rule) in `bin/store/<size>/`, with `shots.json` (each file's SHA-256 and
  MD5) and the review sheet `bin/store/review.html`. `helder publish
  --listing` sends the changed ones to Google Play's and App Store
  Connect's listings (src/helder/cli/README.md).

Not yet: the stories' editor and panel (phase 3), a story kept across a
reload, image snapshots and scripted interactions in tests, a virtual
clock beyond finishing transitions, device frames.
