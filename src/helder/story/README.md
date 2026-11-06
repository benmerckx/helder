# helder.story

Stories, as Storybook's: a component shown in a state, with controls, a
test of it, and (marked for the store) a store screenshot.

```haxe
// tests/story/Card.story.hx
package story;

import helder.story.Story;

final plain = story({name: "Card/plain", render: c -> card(c.text("title", "Fleet"), c.number("ships", 3))});
final fleet = story({
  name: "Store/fleet", store: true, caption: "Command a fleet", seed: 7,
  render: c -> card(c.text("title", "Your fleet"), c.number("ships", 10 + Std.int(c.random() * 90)))
});
```

```tsx
// TypeScript: helder/story, the same definition
import {story, tree} from "helder/story";

export const plain = story({name: "Card/plain", render: (c) => <Card title={c.text("title", "Fleet")}/>});
console.log(tree(plain));
```

- **`story({...})`** is a definition (src/helder/compiler/DESIGN.md 4;
  its handler `StoryDefinition`, one for both languages): `name`, `render`
  (a function of the story's controls), `seed` (Controls.random's, 1),
  `store: true` for a store screenshot with its `caption`, `background`
  and `color`. Each is a literal, checked where it is written (a caption
  without `store: true`, a seed that is not an integer, a name that is not
  static: the same diagnostic in both languages). A release build (`-D
  helder.release`, helder build's) has no stories: the call is null there
  and what only a story uses is not linked.
- **Files**: `*.story.hx` anywhere a test file may be (src/, tests/, the
  project's class paths), its stories the module-level values made by
  `story` (`Stories.of(module)`, in the order written); linked as test
  files are (`Foo_story.hx`), so the app's own builds never contain them.
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
  each story with `store: true` rendered offscreen on the GPU (Mesa's
  llvmpipe on Linux) at the stores' sizes as a real layout (iPhone 6.9"
  1320x2868 and 6.5" 1284x2778 at 3x, iPad 13" 2064x2752 at 2x, an
  Android phone 1080x1920; swapped for a landscape app), text in the
  system's fonts, its caption in a band over it (`StoreOptions`: caption,
  colours; the story's seed), written as opaque RGB PNGs (no alpha channel, Apple's
  rule) in `bin/store/<size>/`, with `shots.json` (each file's SHA-256 and
  MD5) and the review sheet `bin/store/review.html`. `helder publish
  --listing` sends the changed ones to Google Play's and App Store
  Connect's listings (src/helder/cli/README.md).

Not yet: the stories' editor and panel (phase 3), a story kept across a
reload, image snapshots and scripted interactions in tests, a virtual
clock beyond finishing transitions, device frames.
