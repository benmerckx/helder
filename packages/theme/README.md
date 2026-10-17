# @hxmc/theme

The look of `@hxmc/ui`'s widgets, which ship unstyled (behaviour only,
docs/plans/theme.md): one theme, based on [shadcn/ui](https://ui.shadcn.com)
(MIT, see LICENSE). Its token names and values (the neutral theme, light
and dark, in `oklch()`), its slot names (`data-slot`), Radix's state
attributes, its variants and sizes, and its components' Tailwind class
lists, copied verbatim from shadcn's new-york-v4 registry into
`src/hxmc/theme/shadcn.json` (its `shadcn` field names the commit:
d2fba50, shadcn 4.22.0), become `hxmc.ui` rules at compile time.

The components: Button, Input, Checkbox, Switch, Label, Card, Badge,
Textarea, RadioGroup, Slider, Tabs, Select, DropdownMenu, Dialog, Popover,
Tooltip, Table, Progress, Accordion, Toggle, ToggleGroup, Separator,
Alert, Skeleton, Breadcrumb, Pagination, Calendar (react-day-picker's
parts as `calendar-<part>`), Command, Menubar, ContextMenu, and sonner's
toast (`toast`, `toast-title`, `toast-description`, `toast-icon`: sonner's
own stylesheet's values, written as classes). Slots are shadcn's
`data-slot` names; where shadcn styles an element without one, it is
named after its parent: `checkbox-icon`, `radio-group-icon`,
`select-trigger-icon`, `select-viewport`, `accordion-trigger-icon`,
`dropdown-menu-item-indicator` (and the context menu's and menubar's),
`tooltip-arrow`, `pagination-previous`, `pagination-next`; `body` is
the window's root (Tailwind's preflight, then globals.css's body).
AccordionContent's inner box is folded into `accordion-content`.

hxmc.ui's widgets that shadcn has no component for (Toolbar, Listbox,
Tree, ColorPicker, NumberField, TagInput, Collapsible, Sortable, the
resizable handle, the toast's action and close, the fields around a
checkbox, switch or radio, icons shadcn draws with a selector) are in
`src/hxmc/theme/extras.json`, in shadcn's manner (its tokens, sizes and
states; not copied from anywhere), which `shadcn.json` includes.

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
string, cn's several, cva's `{base, variant: {...}, size: {...}}`, or
another slot's, `{extends: "button", variant: "ghost", class: "..."}` as
`cn(buttonVariants({variant: "ghost"}), "...")`), `--radius`, CSS
variables a class may name (`size-(--cell-size)`) and the tokens into a
`StyleSheet` (`include`: other files beside it whose slots are added). Both run at compile time: no class is parsed when the
program runs. The rules are written as compact data (`RuleData.hx`: a
string table and a stream of small numbers) read when the sheet is first
used: shadcn's 449 rules add 23 KB to a native program (the reader, 19
KB, once), and half a second to a build. `-D hxmc.theme.dump` prints
them.

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
  `black`, `transparent`; `fill-*` (an icon's fill, as its colour);
- `shadow-*` (Tailwind's, and `shadow-[0_4px_12px_rgba(0,0,0,0.1)]`),
  `ring-*` (a ring is a box shadow outside the border box, drawn here as
  an outline at no offset, which has its shape), `ring-offset-*`,
  `outline-*`, `opacity-*`, `cursor-*`, `pointer-events-*`, `translate-*`
  (`[calc(100%-2px)]` too), `rotate-*`, `scale-*`;
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
`group` and `peer`, container queries, what Radix's popper measures
(`max-h-(--radix-…)`, `origin-(--radix-…)`), what has no property yet
(`underline-offset-*`, auto margins such as `ml-auto`, sizes by
`calc()`, `scroll-m*`), a table's own layout (`align-middle`,
`caption-bottom`), `text-balance`, `sr-only`; arbitrary selectors
(`[&_svg]:size-4`, `[a&]:hover:`, `[.border-b]:pb-6`, `has-[>svg]:px-3`),
children's and descendants' (`*:`, `**:`), pseudo-elements (`after:`)
and `file:`. Rings and outlines share hxmc's one outline: in a rule with
both (tabs' trigger), the ring wins.

## Checks

`make theme-check` (`test/ThemeTest.hx`, on Eval): class lists read as
rules, Tw's rules made at compile time, shadcn's sheet made, the
classes Tw rejects. `make theme-fidelity-check`: each themed widget drawn
headless against shadcn's own markup and CSS drawn by Chromium
(`test/ref/*.png`, 166 cases of every component but Calendar and the
toast: variants, sizes, hover, focus, disabled, invalid, checked, open,
light and dark; `test/ref.mjs` writes them with Tailwind 4.3.3), for the
widgets `hxmc.ui` has converted so far; the cases known to differ, for
what `hxmc.ui` lacks yet, reported, not failed (`FidelityTest.KNOWN`).
