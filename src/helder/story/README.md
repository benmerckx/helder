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
  `width` and `height` (its size in points, whole numbers: the studio's
  screen of it; a phone's, 390x844, without), `store: true` for a store
  screenshot with its `caption`, `background`
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
  signal a story sets false while it loads, which the renderers wait for;
  `play(seconds)`, a story that runs to a moment (a game mid-play):
  unsettled until its clock has run that long; `onDispose(f)`, what to let
  go with the story (a game's scene world).
- **A story's clock** (`Stories.settle`): each story is mounted in a
  ScreenContext of its own (its clock, timers, settings: what one leaves
  running is not the next one's). Settled as it is built, its transitions
  are finished. Not (`play`, a scene loading), its frames run on its clock
  instead, 1/60 s apart whatever the machine's speed: each tick runs its
  timers and steps (a game's frame, its physics), lays the tree out and
  paints it (a `<Scene>`'s controls and sizes stepped), until it is
  settled; that moment's frame is the one drawn. 120 s of its clock at
  most, then an error naming the story.

  ```haxe
  final hole8 = story({name: "Holes/Turnstile", store: true, caption: "Three islands in the sky", render: c -> {
    var game = new Game();
    game.demo(7, Rounds.rounds[7].shots);
    Clock.add(t -> { game.frame(t); true; });
    c.onDispose(game.dispose);
    c.play(4); // the moment: 4 s into the hole
    LittleSkies.view(game);
  }});
  ```

  TypeScript's the same: `c.play(4)`, `c.onDispose(...)`, the game on
  helder/ui's clock. In the studio a playing story runs live.
- **Tests**: `helder test` runs each story file's stories as tests: each
  mounted headless in a phone's size (390x844 points) with text laid out
  without fonts (`StoryText`: the same everywhere, wasm too), brought to
  its moment (its transitions finished, or played), its tree (tags, boxes,
  texts) against the snapshot in `Foo.story.snap` (`helder test -u`
  rewrites it).
- **Screenshots** (`StoreShots`, built and run by `helder.cli.Shots`):
  the stories with `store: true` are an app's screenshots, the stores'
  and helder.run's alike. `helder publish --screenshots` renders each
  offscreen on the GPU (Mesa's
  llvmpipe on Linux) at the stores' sizes as a real layout (iPhone 6.9"
  1320x2868 and 6.5" 1284x2778 at 3x, iPad 13" 2064x2752 at 2x, an
  Android phone 1080x1920; swapped for a landscape app), text in the
  system's fonts, its caption in a band over it (`StoreOptions`: caption,
  colours; the story's seed), written as opaque RGB PNGs (no alpha channel, Apple's
  rule) in `bin/store/<size>/`, with `shots.json` (each file's SHA-256 and
  MD5) and the review sheet `bin/store/review.html`. `helder publish
  --listing` sends the changed ones to Google Play's and App Store
  Connect's listings (src/helder/cli/README.md). `helder publish --run`
  renders the same stories as helder.run's screenshots (unless helder.json
  names `run.screenshots`): at a window's size, 1280x800 (390x844 at 2x
  for a portrait app), with no caption band, in their order, at most 8
  (`StoreShots.web`). One device draws every shot, each into a target of
  its size; each story in its own context and clock, let go after
  (`Controls.dispose`). A TypeScript program's are its `*.story.ts(x)`
  files' exported stories (`shots(stories)`, the generated main's).

- **Screens** (`Screens.run(stories)`; TypeScript's `screens`): the
  program helder studio builds of a project's stories (apps/studio/README.md,
  "Screens"): every story in one program, the preview host (`Host`: each
  story a root of its own with a ScreenContext of its own; only the
  screens in view draw). Natively one process (`NativeHost`: each screen's
  frame drawn into a GPU texture the studio opens, helder.gfx's shared
  textures, else through shared memory, `FrameFile`); for the web a worker
  (`web.Preview`: ImageBitmaps). The studio speaks the devtools protocol
  to it (`HostAgent`: Host.show, Host.frame, Host.release, Ui.getTree and
  Ui.nodesAt naming a screen; `Studio.screens` answers the screens).

Not yet: the stories' editor and panel (phase 3), a story kept across a
reload, image snapshots and scripted interactions in tests,
device frames.
