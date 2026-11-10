# Afterglow: the game

A short, calm puzzle game in the spirit of Monument Valley: dioramas that
are readable mechanisms, a handful of moves each, no failure, and the
pleasure of watching the stone click into place.

A tiny white moth in overgrown ruins over still black water. Its soft
light wakes what it comes near. A small snail, afraid of the dark,
crawls towards that light; the moth lights its way home and rebuilds the
ruin under it.

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
  towards where it will go. The snail's home is a warm door, always lit,
  brighter as the snail comes.

## Verbs

One: **fly.** On a phone, touch and drag: the moth follows the finger (a
little above it, so it stays in sight); a tap sends it there. With a
mouse, the same with the button. When it stops it hovers a moment, then
drops to the ground below and stands (where there is none it hovers).

Its light does the rest:

- **Wake.** A glyph within the moth's light charges (about half a second
  of hovering by it) and, once full, moves its stone to the next state.
  To use it again the glyph must go dark first: fly off and come back.
- **Lead.** The snail crawls towards the moth's light, as far as the way
  it is on goes: walks joined end to end at one height, through no shut
  gate, over no stone that is moving. A stone that carries takes the
  snail with it.

## The screens

1. **First light** (4 moves). Wake the snail, asleep in its shell (fly
   to it). Light the glyph on the wall: the near half of a bridge slides
   out of the ledge. Light the glyph on the stele: the far half slides out
   of the pillar. Lead the snail across to its door.
   *Introduces: light wakes; a glyph moves its stone; the snail follows.*
2. **Two lights** (4 moves). A gate between two
   carved eyes opens only while both are lit, and the moth is one light.
   Wake the lantern (an ember high on a stone arm), light the glyph that
   turns the arm (the lantern swings down by the left eye, which lights),
   then light the right eye: the gate rises and the snail crawls through
   to its door. It never shuts on the snail.
   *Introduces: light left behind; two at once.*
3. **The lift** (5 moves). The snail is below, its door on a shelf high
   up. Lower the lift (the glyph on the tower); the snail climbs on,
   following the moth. Fly off and back: the lift rises with the snail.
   Light the glyph above the shelf: a bridge slides out to the lift. Lead
   the snail home. Raising the lift before the snail is on only means
   lowering it again.
   *Introduces: stones carry the snail; order matters.*

After a screen is solved there is a pause, a fade into the mist and the
next one. The last one stays.

## Design notes

- Glyphs stand at least about one and a half of the moth's reaches (as
  seen) from anywhere the moth must rest to lead the snail: resting by
  one wakes it. (The lift's screen first had its bridge glyph by the
  door: leading the snail home slid the bridge back in.)
- Glyphs are spaced so that the moth, between two, lights neither; the
  two eyes are more than two reaches apart.
- A screen fits a phone held upright (the play area is about 5.5 by 8
  units at the moth's depth); a wide window shows more of the ruin about
  the same play.

## The first plan, and what came of it

- **Kept:** flying, the light waking things, glyphs moving the ruin (a
  bridge sliding out, the lift, an arm turning), the snail and its
  connected paths, no failure, one diorama a screen.
- **Changed: the snail follows the light** instead of walking home on
  its own. Walking to "the reachable point nearest home" went wrong at
  once: on the lift's screen the snail would not step onto the lowered
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
  later screen), the water dropping a step, the snail rolling down
  slopes, sound and music, reduced motion, the fifth room.
- **Not yet in:** helder.physics for the feel (a lantern swinging after
  its arm stops, dust as a stone settles); stones settle with an eased,
  slightly weighted motion for now.
