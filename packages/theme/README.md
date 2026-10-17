# @hxmc/theme

The look of `@hxmc/ui`'s widgets, which ship unstyled (behaviour only,
docs/plans/theme.md): one theme, based on [shadcn/ui](https://ui.shadcn.com)
(MIT, see LICENSE). Its token names and values (the neutral theme, light
and dark, in `oklch()`), its slot names (`data-slot`), Radix's state
attributes, its variants and sizes, and its components' Tailwind class
lists, copied verbatim from shadcn's new-york-v4 registry into
`src/hxmc/theme/shadcn.json` (its `shadcn` field names the commit:
d2fba50, shadcn 4.22.0), become `hxmc.ui` rules at compile time.

```haxe
import hxmc.theme.Shadcn;

ui.theme = Shadcn.sheet;   // or node.theme, for a subtree
ui.dark = true;            // shadcn's .dark tokens, and dark: rules
```

`examples/Signup.hx`: a card with an input, a checkbox, a switch, badges
and buttons.

## Tw: Tailwind classes as rules

`Tw.rules(slot, classes, ?variant, ?size)` turns a class list into
`Array<Rule>`; `Tw.sheet(file)` a JSON file of slots' class lists (a
string, cn's several, or cva's `{base, variant: {...}, size: {...}}`),
`--radius` and the tokens into a `StyleSheet`. Both run at compile time:
no class is parsed when the program runs. The rules are written as
compact data (`Rules.hx`: a string table and a stream of small numbers)
read when the sheet is first used; shadcn's seven first components, 88
rules, add 4.8 KB to a native program (the reader, 19 KB, once).

The subset of Tailwind v4 shadcn's components use (`Tailwind.hx`), read
with Tailwind's default theme and shadcn's on top, 1rem = 16px:

- layout: `flex`, `inline-flex` (a row: CSS's default direction, not
  ui's column), `grid`, `hidden`, `block`; `flex-col`, `flex-wrap`,
  `flex-1`, `shrink-0`, `grow`, `items-*`, `justify-*`, `self-*`,
  `justify-self-*`, `place-content-center`, `place-items-center`,
  `grid-cols-*`, `grid-rows-[...]`, `auto-rows-*`, `col-*`, `row-*`;
  `relative`, `absolute`, `fixed` (as absolute), `inset-*`, `top-*`...,
  `z-*`, `overflow-*`;
- spacing and sizes: `p-*`, `px-*`, `m-*` (negative too), `gap-*`,
  `w-*`, `h-*`, `size-*`, `min-*`, `max-*` (the spacing scale, fractions,
  `full`, `fit`, `auto`, containers, `[1.15rem]`);
- borders and corners: `border`, `border-*` (widths, sides, colours),
  `rounded-*` (shadcn's multiples of `--radius`: sm 0.6, md 0.8, lg 1, xl
  1.4...), sides and corners;
- colours: shadcn's tokens as `var(--name)`, with an alpha in percent
  (`bg-primary/90` is `var(--primary)/90`), resolved by the engine when a
  rule applies, so that light and dark switch without new rules; `white`,
  `black`, `transparent`;
- `shadow-*` (Tailwind's), `ring-*` (a ring is a box shadow outside the
  border box, drawn here as an outline at no offset, which has its
  shape), `ring-offset-*`, `outline-*`, `opacity-*`, `cursor-*`,
  `pointer-events-*`, `translate-*` (`[calc(100%-2px)]` too), `rotate-*`,
  `scale-*`;
- text: `text-xs`...`text-4xl` (with their line heights), `text-[0.8rem]`,
  `font-*`, `leading-*` (beating `text-*`'s line height, as in CSS),
  `tracking-*` (em of the font size), `underline`, `uppercase`,
  `truncate`, `whitespace-nowrap`, `tabular-nums`, `text-center`...

Variants become the rule's `when` states, in Tailwind's order (the rule
of a later variant later, so that "later rules win" is CSS's cascade):
`hover`, `focus`, `focus-visible`, `active`, `disabled`, `placeholder`,
`dark`, `data-[state=checked]` (`data-state=checked`), `data-[disabled]`,
`data-placeholder`, `aria-invalid` (`aria-invalid=true`), `aria-selected`;
`data-[size=…]` and `data-[variant=…]` (also a group's) select the rule's
size and variant instead. Beyond the contract, for the engine to take up:
`group:<state>` (`group-data-[disabled=true]`: an ancestor's),
`peer:<state>` (`peer-disabled`: a previous sibling's), `has:<state>`
(`has-data-[slot=card-action]`: a descendant's), `md` and the other
breakpoints (the window's width, as the viewport's), `selection`.

A rule that sets part of a shorthand (`px-4`, `border-b`, `rounded-t-md`,
`translate-x-1`) takes the other parts from the rules that hold whenever
it does, as CSS's separate properties would. A class that is neither known
nor listed in `Tailwind.IGNORED` or `IGNORED_VARIANTS` is a compile error
at the class, in the JSON file or the string. Ignored: motion
(`transition-*`, `animate-*`, `duration-*`...), resets of what an
unstyled widget never draws (`outline-none`), `select-none`, the markers
`group` and `peer`, container queries, `underline-offset-*` (no property
yet), arbitrary selectors (`[&_svg]:size-4`, `[a&]:hover:`,
`[.border-b]:pb-6`, `has-[>svg]:px-3`) and `file:`.

## Checks

`make theme-check` (`test/ThemeTest.hx`, on Eval): class lists read as
rules, Tw's rules made at compile time, shadcn's sheet compiled, the
classes Tw rejects. `make theme-fidelity-check`: each themed widget drawn
headless against shadcn's own markup and CSS drawn by Chromium
(`test/ref/*.png`, 90 cases: variants, sizes, hover, focus, disabled,
invalid, checked, light and dark; `test/ref.mjs` writes them with
Tailwind 4.3.3); skipped until `hxmc.ui` has the rule engine.
