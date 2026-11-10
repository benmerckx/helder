# Afterglow: the game

A short, calm puzzle game in the spirit of Monument Valley: dioramas that
are readable mechanisms, a handful of moves each, no failure, and the
pleasure of watching the stone click into place.

A tiny white moth in overgrown ruins over still black water. Its soft
light wakes what it comes near. Its young, a small pale caterpillar,
crawls towards that light; the moth lights its way to an empty cocoon
hung in a niche of the stone and rebuilds the ruin under it. Once the
caterpillar is in, the cocoon lights: one more of the lanterns that hang
all through the ruins.

## Restarting the puzzle: two greybox prototypes

Played on desktop, flying the moth worked; three things did not: waking
glyphs by hovering (slow, accidental, hard to repeat), not knowing what
to do (what reacts, what it moves, what the goal is), and leading the
caterpillar by the light (fiddly). The puzzle starts again as two
greyboxes to play side by side: flat shapes on a 7 x 9 grid, the moth's
flight as it was (Flight), no art. The game opens on a title: **A:
Light**, **B: Way**, and **The old game** (what follows the prototypes
here). `-- --proto a|b|game` and `-- --screen n` start there; on the web,
`?proto=a&screen=2`.

Both: **a tap is the act, never hovering**; a press anywhere else leads
the moth (drag: it follows; tap: it flies there), as before. What can be
touched has a shape of its own and a slow pulsing ring; what it will do
shows before you touch it (a dotted beam where light would go, a
crystal's point, coloured wires from a lever to its gates). Anything done
is undone by doing it again; nothing fails. The bar: MENU, the screen,
RESET (keys: 1-3 a screen, R again, Esc the title); a solved screen
moves on after three seconds (or NEXT).

### A: Light (route the light to the one dark thing)

The goal is one dark, waiting thing (a cocoon, a dead lantern, a closed
flower) with a pip for each light it needs; lit, it wakes and the screen
is solved. The moth is the light: on a **perch** (a socket with an arrow)
it shines the perch's way. Light is a beam traced cell by cell: stone
stops it, a **crystal** sends it on the way its point faces (tap: a
quarter turn clockwise), a **shutter** stops it (drag it along its
groove, or tap it: to its other slot), a **lantern** catches it and stops
it. Tap a dark lantern: the moth flies there and kindles it; it then
shines its own way, without the moth (the relay: two lights at once).

1. **One crystal** (3 moves). Fly to the perch: its beam goes up into
   the crystal, which points left at the wall. Tap it twice (up, right):
   the beam crosses to the cocoon.
2. **Two crystals** (5 moves). The perch shines right into a crystal
   pointing at the floor: tap it twice (left, up). Its beam stops at a
   shutter: drag it aside into its alcove. The second crystal points up:
   tap it once, at the dead lantern.
3. **Two lights** (5 moves). The flower needs two. Tap the lantern: the
   moth kindles it; its beam goes left into a crystal pointing at the
   ceiling: tap it twice (right: back at the lantern, then down: the
   flower's first light). Drag the shutter off the perch's column, fly to
   the perch: the second.

### B: Way (the moth alone opens its way to the exit)

The moth must reach the screen's exit (an arch of pale light) through
stone, shut **gates** (bars across the way) and **dark passages**
(hatched black) it will not fly into. Tap a **lever** or a **lamp**: the
moth flies to it, round what is in its way, and pulls it; out of reach,
it flies as near as it can and the lever shakes. A lever flips every gate
wired to it: a dashed wire in its colour and a dot of its colour on the
gate (one lever may open a gate and shut another); a lamp lights its dark
passage, or puts it out. A press anywhere else leads the moth there (or
as near as it can get).

1. **Lamp and lever** (3 moves). Tap the lamp: the passage up lights.
   Tap the lever in the room above: the gate beside it lifts. Tap the
   exit.
2. **One lever, two gates** (3 moves). The upper gate is open, the lower
   shut. The lever opens the lower and shuts the upper (both have its
   amber dot). Through, the second lever (cyan) opens the upper again.
   Tap the exit.
3. **Three rooms** (4 moves). Each lever moves two gates: the first opens
   the way up and shuts the exit's; the second, up there, opens the way
   on and shuts the one behind; the third opens the exit's again (and
   shuts the one behind). Each lever only moves its own room's doors, so
   the moth is never shut in.

### Playtests

`play/greybox.mjs` holds each screen's moves in cells and writes them as
headless scripts for a window (`node examples/afterglow/play/greybox.mjs
390x844`: play/greybox/a1.json ... b3.json, marks `start` and `solved`):

```sh
bun run helder run --headless examples/afterglow --size 390x844 --scale 2 \
  --script examples/afterglow/play/greybox/a3.json \
  --snap a3.png --at mark:solved -- --proto a --screen 3 --log
```

`--log` prints what happens (`greybox: a3: kindled at 2 s`, `... solved
at 6.5 s`).

## The old game

This is what is built (three screens). The first plan, and what came of
each part of it, is at the end.

## Rules

- **Deterministic.** The puzzle steps at a fixed rate (60 a second, the
  same whatever the frame rate) from where the moth is: nothing random,
  no physics deciding anything. The same moves give the same result.
- **No failure.** Anything done can be done again: a glyph moves its
  stone on to its next state and back. A move in the wrong order only
  means no progress.
- **Readable.** What can be woken breathes faintly (a carved glyph, an
  eye, a lantern's ember); as the moth comes near it lights from the
  moth's side, and the stone it moves gets a violet edge and stirs
  towards where it will go. The caterpillar's home is a cocoon in a niche,
  an amber ember in its lattice (the lanterns are magenta: home is the
  one warm light) that brightens as the caterpillar comes.

## Verbs

One: **fly.** On a phone, touch and drag: the moth follows the finger (a
little above it, so it stays in sight); a tap sends it there. With a
mouse, the same with the button. When it stops it hovers a moment, then
drops to the ground below and stands (where there is none it hovers).

Its light does the rest:

- **Wake.** A glyph within the moth's light charges (about half a second
  of hovering by it) and, once full, moves its stone to the next state.
  To use it again the glyph must go dark first: fly off and come back.
- **Lead.** The caterpillar crawls towards the moth's light, as far as the way
  it is on goes: walks joined end to end at one height, through no shut
  gate, over no stone that is moving. A stone that carries takes the
  caterpillar with it.

## The screens

1. **First light** (4 moves). Wake the caterpillar, asleep in a ball (fly
   to it). Light the glyph on the wall: the near half of a bridge slides
   out of the ledge. Light the glyph on the stele: the far half slides out
   of the pillar. Lead the caterpillar across to its cocoon.
   *Introduces: light wakes; a glyph moves its stone; the caterpillar follows.*
2. **Two lights** (4 moves). A gate between two
   carved eyes opens only while both are lit, and the moth is one light.
   Wake the lantern (an ember high on a stone arm), light the glyph that
   turns the arm (the lantern swings down by the left eye, which lights),
   then light the right eye: the gate rises and the caterpillar crawls through
   to its cocoon. The gate never shuts on the caterpillar, and a caterpillar
   led to a shut one waits before it.
   *Introduces: light left behind; two at once.*
3. **The lift** (5 moves). The caterpillar is below, its cocoon on a shelf high
   up. Lower the lift (the glyph on the tower); the caterpillar climbs on,
   following the moth. Fly off and back: the lift rises with the caterpillar.
   Light the glyph above the shelf: a bridge slides out to the lift. Lead
   the caterpillar home. Raising the lift before the caterpillar is on only means
   lowering it again.
   *Introduces: stones carry the caterpillar; order matters.*

After a screen is solved there is a pause, a fade into the mist and the
next one. The last one stays.

## Design notes

- Glyphs stand at least about one and a half of the moth's reaches (as
  seen) from anywhere the moth must rest to lead the caterpillar: resting by
  one wakes it. (The lift's screen first had its bridge glyph by the
  cocoon: leading the caterpillar home slid the bridge back in.)
- Glyphs are spaced so that the moth, between two, lights neither; the
  two eyes are more than two reaches apart.
- A screen fits a phone held upright (the play area is about 5.5 by 8
  units at the moth's depth); a wide window shows more of the ruin about
  the same play. What is played with stays in the frame at any shape
  from a narrow phone (9:21) to a wide window (16:9): Afterglow.frame.

## The companion

It was a snail at first, walking home to a warm door. A snail is brown
and round in a world of indigo and living light, and has nothing to do
with a moth. The caterpillar is the moth's own young: dark and segmented, a
row of small lights along its side and violet in the creases of its
back (it is seen in the dark by its own light), bristles, a glossy head,
a horn on its tail with an ember of its cocoon's amber; asleep it is
wound into a ring. (It was a cartoon first, as the moth was: a round head with one
large eye, flat cream, a line about it. Neither is now: both are drawn
as lit forms, the way Dead Cells lights its characters, at full
resolution: dark bodies, crisp rims in the colour of what glows by
them, the moth's wings alone kept pale, both left crisp against the
painted world: README, The characters.) It follows the light
for the reason a moth does. Its home explains the lanterns: each is a
cocoon, and each screen solved lights one more. The play is the same
(it crawls along walks, rides what carries it, waits at a shut gate).

## The first plan, and what came of it

- **Kept:** flying, the light waking things, glyphs moving the ruin (a
  bridge sliding out, the lift, an arm turning), a companion and its
  connected paths, no failure, one diorama a screen.
- **Changed: the companion follows the light** instead of walking home on
  its own. Walking to "the reachable point nearest home" went wrong at
  once: on the lift's screen it would not step onto the lowered
  lift, its ledge's end being nearer home as the crow flies. Following
  the light gives the player one obvious way to steer it, makes where the
  moth rests matter twice (waking and leading), and makes "afraid of the
  dark" literal.
- **Changed: hovering is glowing.** Press and hold to glow brighter
  wasn't needed: a glyph charges while the moth hovers by it, and the
  moth hovers a moment before it lands.
- **Changed: "two at once"** is a gate held by two eyes and a lantern
  that keeps one lit, instead of two sprouts lit together.
- **Dropped for now:** the gust (a flick reads as a drag on a touch
  screen, and three screens need no third verb), lily pads and notches,
  sprouts growing (a one-way glyph by another look: a candidate for a
  later screen), the water dropping a step, the companion rolling down
  slopes, sound and music, reduced motion, the fifth room.
- **Not yet in:** helder.physics for the feel (a lantern swinging after
  its arm stops, dust as a stone settles); stones settle with an eased,
  slightly weighted motion for now.
