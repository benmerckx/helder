# Afterglow: the game

A short, calm puzzle game (about ten minutes) in the spirit of Monument
Valley: handmade rooms that are readable mechanisms, each with one clear
solution, no failure, and the pleasure of watching the world click into
place.

A tiny white moth wakes in overgrown ruins under water and stone: arches
layered into mist, still black water, roots, hanging lanterns, and life
that glows (moss, mushrooms, sprouts) in the dark. Its own soft light wakes
what it touches. A small snail, afraid of the dark, needs to get home; the
moth lights and rebuilds its way.

## Rules

- **Deterministic.** The same actions give the same result. A room is
  solved in 3 to 6 moves; there is no failure, and anything done can be
  undone by acting again.
- **Readable.** What can be touched looks like it (a glyph, a sprout, a
  notch), and what it will do is visible before it happens.
- **Physics for feel, never for outcomes.** Vines sway, lanterns swing,
  spores drift, the snail's shell rolls with weight (helder.physics), but
  where things end up is designed: every mechanism has a few fixed states.

## Verbs

On a phone: drag to fly, press and hold to glow brighter, a quick flick for
a gust. With a mouse: the same with the pointer and the button.

- **Fly.** The moth goes anywhere; distance is never the puzzle.
- **Glow.** Things within the moth's light wake: hovering by a glyph lights
  it (a short, visible charge), and hidden glyphs, paths and creatures
  appear only in its light.
- **Gust.** A flap pushes a light thing (a lily pad, a hanging lantern) to
  its next notch: an explicit position, never free physics.

## Mechanisms

- **Glyphs drive the ruins.** A lit glyph moves something to its next
  state: an arch rotates a quarter turn, a bridge slides out, a stair
  unfolds, the water drops a step. Each move snaps into place with weight
  (springs, a little dust, a sound).
- **Sprouts grow** at fixed spots into one fixed shape when lit: a vine
  bridge, a mushroom step, a root stair. Some need two glyphs lit together,
  so the moth must choose where to hover.
- **Notches.** Lily pads and lanterns have marked positions; a gust moves
  them one notch along.

## The snail

It walks on its own along connected paths toward home, like Ida in
Monument Valley, and stops where the path ends or the dark begins. The
player's work is connecting its path. Where a path is a slope the design
marks it as a roll: the snail pulls into its shell and rolls down
(predetermined, with physics for the feel). It never falls or dies.

## Rooms

1. **First light.** Light a glyph; a bridge slides out; the snail crosses.
   (Glow, glyphs.)
2. **Overgrowth.** Grow a vine bridge across a gap; then a mushroom step
   up a ledge. (Sprouts; two at once.)
3. **The turning arch.** A glyph rotates an arch between two levels; the
   right order lets the snail climb, then roll down. (Rotation, order.)
4. **Still water.** Gust lily pads along their notches into a path; light
   a glyph to lower the water a step. (Gust, notches, water.)
5. **Home.** Everything together; lighting the last glyph rebuilds the
   ruin around the snail's home.

## Feel

- Calm: no timers, no score; music and sound respond to light and to
  mechanisms settling.
- Each room is one diorama seen at once, portrait on phones and framed
  wider on desktop; the camera drifts slightly, never needs controlling.
- Reduced motion keeps every mechanism's result and shortens its motion.

## What lives where

In the example: the rooms, their mechanisms and states, the snail's path
walking, the glyph and sprout logic, the look's own shaders. In Helder,
only what is general and missing: the 2D vector animation with a state
machine (the moth and the snail), and scene or physics features the look
needs (fog, water reflection, emissive control), each with a test.
