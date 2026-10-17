# @hxmc/theme

The look of `@hxmc/ui`'s widgets, which ship unstyled (behaviour and
semantics only, docs/plans/theme.md): one theme, based on
[shadcn/ui](https://ui.shadcn.com) (MIT, see LICENSE). Its token names and
values (the neutral theme, light and dark, in `oklch()`), its slot names
(`data-slot`), Radix's state attributes, its variants and sizes, and its
components' Tailwind class lists, copied verbatim from shadcn's
new-york-v4 registry into `src/hxmc/theme/shadcn.json` (its `shadcn` field
names the commit: d2fba50, shadcn 4.22.0), become `hxmc.ui` rules at
compile time.

## Usage

```haxe
import hxmc.theme.Shadcn;

ui.theme = Shadcn.sheet;   // the window's; node.theme for a subtree
```

Give the page's surface the `body` slot (shadcn's `body`: `bg-background
text-foreground`, Tailwind's `font-sans text-base`):

```haxe
Render.render(<view slot="body" grow={1} padding={24}>...</view>, w.root);
```

Then every widget of `hxmc.ui.widgets.Widgets` looks as shadcn's:
`<Button variant="outline" size="sm" label="Cancel"/>`, `<Badge
variant="secondary"/>`, `<Switch size="sm"/>`, `<Alert
variant="destructive">`... An instance's own style wins over every rule:
`<Button style={s -> {radius: s.hovered.value ? 0 : 999}}/>` (a function of
its states, as React Aria's render props).

`examples/Signup.hx`: a card with an input, a checkbox, a switch, badges
and buttons, the switch turning dark mode on.

## Dark mode

`ui.dark = true` picks the sheet's dark tokens (shadcn's `.dark`) and
makes the `dark:` rules hold; switching re-resolves every colour without
new rules. A window follows the system's appearance unless set.

## Tokens of one's own

The rules name tokens (`var(--primary)`, `var(--ring)/50`), resolved
when a rule applies. `Shadcn.withTokens` makes a sheet of the same rules
with some tokens replaced, light and dark (names without the dashes, CSS
colours):

```haxe
ui.theme = Shadcn.withTokens(
	["primary" => "oklch(0.546 0.245 262.881)", "ring" => "oklch(0.623 0.214 259.815)"],
	["primary" => "oklch(0.707 0.165 254.624)"]);
```

The tokens: `background`, `foreground`, `card`, `card-foreground`,
`popover`, `popover-foreground`, `primary`, `primary-foreground`,
`secondary`, `secondary-foreground`, `muted`, `muted-foreground`,
`accent`, `accent-foreground`, `destructive`, `border`, `input`, `ring`,
`chart-1`...`chart-5`, `sidebar-*`. `--radius` (0.625rem) is read at
compile time: its multiples (`rounded-sm` 0.6, `-md` 0.8, `-lg` 1,
`-xl` 1.4...) are in the rules; another radius takes a JSON file of one's
own (below).

## Rules of one's own

A sheet is data, `{rules: Array<Rule>, light, dark}`, later rules
winning. `Tw.rules(slot, classes, ?variant, ?size)` turns a Tailwind class
list into rules at compile time; add them after shadcn's:

```haxe
ui.theme = {
	rules: Shadcn.sheet.rules.concat(Tw.rules("button", "rounded-full px-6"))
		.concat(Tw.rules("button", "bg-destructive/80 hover:bg-destructive", "danger")),
	light: Shadcn.sheet.light,
	dark: Shadcn.sheet.dark
};
```

or a sheet of one's own, `Tw.sheet("my-theme.json")` (beside the calling
module), in shadcn.json's format: `slots`, each a class list (a string, a
list as cn's, cva's `{base, variant: {...}, size: {...}}`, another slot's
`{extends: "button", variant: "ghost", class: "..."}`, classes under a
state the widget sets `{states: {"data-[side=right]": "..."}}`), `ours`
(slots replacing them), `radius`, `vars` (CSS variables a class names:
`size-(--cell-size)`), `global` (classes before every slot's that has
borders: shadcn's `* { border-border }`), and the `light` and `dark`
tokens. A class Tw does not know is a compile error at the class, in the
JSON file or the string; nothing is parsed when the program runs.

Or hand-written: `{slot: "button", variant: "danger", when: ["hover"],
style: {background: Color.parse("var(--destructive)")}}`; `when` holds
states (`hover`, `focus-visible`, `data-state=checked`, `aria-invalid=true`,
`dark`, `md`, `rtl`, `starting`, `group/name:hover`, `has:data-slot=x`...).

## The components

shadcn's: Button, Input, Checkbox, Switch, Label, Card, Badge, Textarea,
RadioGroup, Slider, Tabs, Select, DropdownMenu, ContextMenu, Menubar,
Dialog, Sheet, Popover, HoverCard, Tooltip, Table, Progress, Accordion,
Toggle, ToggleGroup, Separator, Alert, Skeleton, Breadcrumb, Pagination,
Calendar (react-day-picker's parts as `calendar-<part>`), Command,
Resizable, Avatar, Kbd, Spinner, and sonner's toast (sonner's own
stylesheet's values written as classes: `toast`, `toast-title`,
`toast-icon`, and in `ours` `toaster`, `toast-action`, `toast-close`).
Where shadcn styles an element without a slot, it is named after its
parent: `checkbox-icon`, `radio-group-icon`, `select-trigger-icon`,
`select-viewport`, `accordion-trigger-icon`, `dialog-close-icon`,
`sheet-close-icon`, `tooltip-arrow`, `pagination-previous`,
`pagination-next`. AccordionContent's inner box is folded into
`accordion-content`.

`ours` in shadcn.json: not shadcn's, written in its style from its own
patterns and tokens, for what hxmc has and shadcn has not, or has
otherwise:

- hxmc's widgets shadcn lacks: Tree (`tree`, `tree-item`, `tree-toggle`:
  a bordered list as `select-content`, its rows as `command-item`),
  Listbox (`listbox`, `listbox-option`: the same, `aria-selected` the
  accent), Sortable (`sortable`, `sortable-item` as a small card,
  `sortable-handle`, `sortable-indicator` a primary line), NumberField
  (`number-field`, `number-field-steppers`, `number-field-increment` and
  `-decrement` as small outline buttons), TagInput (`tag-input` as
  `input`, chips as secondary badges, `tag-input-field`,
  `tag-input-remove`), ColorPicker (`color-picker-*`: bordered and ringed
  as an input), Toolbar (as `menubar`), Collapsible (shadcn styles none:
  its trigger as `accordion-trigger`);
- hxmc's parts that are not shadcn's: the calendar's `calendar-nav` (the
  caption between its buttons, in flow), `calendar` (its month's column)
  and `calendar-day` (react-day-picker's day and day button in one, its
  modifiers as `data-today`, `data-outside`, `data-selected`,
  `data-focused`); `command-list` (the combobox's popup: shadcn's
  popover-content and command around it); `pagination-link` (shadcn's
  `isActive` outline variant as `data-active`); `select-value` (the
  trigger's `*:data-[slot=select-value]:` classes);
  `dropdown-menu-trigger-icon`; sonner's `toaster`, `toast-action`,
  `toast-close`.

## Tw: Tailwind classes as rules

`Tw.rules` and `Tw.sheet` run at compile time. The rules are written as
compact data (`RuleData.hx`: a string table and a stream of small numbers)
read when the sheet is first used: shadcn's 705 rules are 21 KB of data
(12 KB of rules, 9 KB of strings); a native program grows 98 KB over one
with an empty sheet (the data, its reader, and the colour, transform and
transition parsers it brings), and a build by under a second.
`-D hxmc.theme.dump` prints them and their size.

The subset of Tailwind v4 shadcn's components use (`Tailwind.hx`), read
with Tailwind's default theme and shadcn's on top, 1rem = 16px:

- layout: `flex`, `inline-flex` (a row: CSS's default direction, not
  ui's column), `grid`, `hidden`, `block`; `flex-col`, `flex-wrap`,
  `flex-1`, `shrink-0`, `grow`, `items-*`, `justify-*`, `self-*`,
  `justify-self-*`, `place-content-center`, `place-items-center`,
  `grid-cols-*`, `grid-rows-[...]`, `auto-rows-*`, `col-*`, `row-*`;
  `relative`, `absolute`, `fixed` (as absolute), `inset-*`, `top-*`...,
  `z-*`, `overflow-*`, `overflow-x-*`, `overflow-y-*`;
- spacing and sizes: `p-*`, `px-*`, `m-*` (negative and `auto` too),
  `gap-*`, `w-*`, `h-*`, `size-*`, `min-*`, `max-*` (the spacing scale,
  fractions, `full`, `fit`, `auto`, containers, `[1.15rem]`); a side's
  class is that side's property (`paddingLeft`), as CSS's longhands;
- borders and corners: `border`, `border-*` (widths, sides, colours),
  `rounded-*` (shadcn's multiples of `--radius`), sides and corners;
- colours: shadcn's tokens as `var(--name)`, with an alpha in percent
  (`bg-primary/90` is `var(--primary)/90`), `white`, `black`,
  `transparent`; `fill-*` (an icon's fill, as its colour);
- `shadow-*`, `ring-*`, `ring-offset-*`, `ring-inset` (rings as the
  engine's ring, drawn over the shadow as Tailwind composes them),
  `outline-*`, `outline-none` and `outline-hidden` (outline-style none:
  no focus ring of the window's either), `opacity-*`, `cursor-*`,
  `pointer-events-*`, `select-*`, `translate-*`, `rotate-*`, `scale-*`;
- motion: `transition`, `transition-*` (colours, opacity, shadow,
  transform, `[color,box-shadow]`...), `duration-*`, `ease-*`, `delay-*`;
  tw-animate-css's enter animations (`animate-in` with `fade-in-*`,
  `zoom-in-*`, `slide-in-from-*`, `spin-in-*`) as the `starting` state
  (CSS's `@starting-style`) the node's transition eases from, a side's
  slide and the open state's zoom composed into one transform;
- text: `text-xs`...`text-4xl` (with their line heights), `text-[0.8rem]`,
  `font-*`, `leading-*` (beating `text-*`'s line height, as in CSS: px as
  `lineHeightPx`), `tracking-*` (`letterSpacingEm`), `underline`,
  `uppercase`, `truncate`, `whitespace-nowrap`, `tabular-nums`,
  `text-center`...

Variants become the rule's `when` states, in Tailwind's order (the rule
of a later variant later, so that "later rules win" is CSS's cascade):
`hover`, `focus`, `focus-visible`, `active`, `disabled`, `placeholder`,
`selection`, `first`, `last`, `sm`...`2xl` (the window's width), `rtl`,
`ltr`, `starting`, `dark`, `data-[state=checked]`
(`data-state=checked`), `data-[disabled]`, `aria-invalid`
(`aria-invalid=true`), `aria-[orientation=vertical]`, `group-*`
(`group-data-[disabled=true]` is `group:data-disabled=true`, named groups
`group/name:`), `peer-*`, `has-*` (`has-data-[slot=card-action]` is
`has:data-slot=card-action`), `not-*`; `data-[size=…]` and
`data-[variant=…]` (also a group's) select the rule's size and variant.
A group or a peer is a node with a `group` or `peer` attribute: the theme
cannot mark one, the widget does.

A rule that sets part of a shorthand (`border-b`, `rounded-t-md`,
`translate-x-1`, `duration-200` of a transition) takes the other parts
from the rules that hold whenever it does, as CSS's separate properties
would. A class that is neither known nor listed in `Tailwind.IGNORED` or
`IGNORED_VARIANTS` is a compile error. Ignored, each with its reason
there: exit animations (ui removes a closed popup), keyframe animations
(`animate-pulse`, `animate-spin`, `animate-accordion-*`), the markers
`group` and `peer`, container queries, what Radix's popper measures,
what has no property yet (`underline-offset-*`, sizes by `calc()`,
`scroll-m*`, `touch-none`), a table's own layout, `text-balance`,
`sr-only`; arbitrary selectors (`[&_svg]:size-4`, `[a&]:hover:`,
`has-[>svg]:px-3`), children's and descendants' (`*:`, `**:`, given to
the part's own slot where hxmc has one), pseudo-elements (`after:`) and
`file:`.

## Checks

`make theme-check` (`test/ThemeTest.hx`, on Eval): class lists read as
rules, Tw's rules made at compile time, shadcn's sheet made, the
classes Tw rejects. `make theme-fidelity-check`: each themed widget drawn
headless against shadcn's own markup and CSS drawn by Chromium
(`test/ref/*.png`, 193 cases of every shadcn component: variants, sizes,
hover, focus, disabled, invalid, checked, open, light, dark and right to
left; `test/ref.mjs` writes them with Tailwind 4.3.3 and sonner 2.0.8),
popups compared in their box; the cases known to differ, for what
`hxmc.ui` lacks yet, reported, not failed (`FidelityTest.KNOWN`, each with
its reason).
