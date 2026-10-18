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
`chart-1`...`chart-5`, `sidebar-*`; and `--radius` (0.625rem, 10px), a
length token (`StyleSheet.lengths`, `Length.token`): `Shadcn.withTokens(null,
null, 6)` rounds every corner less. shadcn's scale multiplies it
(`rounded-sm` 0.6, `-md` 0.8, `-lg` 1, `-xl` 1.4...); the rules hold
`--radius` plus what each multiple adds at 10px (`rounded-md` is
`var(--radius)-2`), the same at shadcn's radius, another moving them all
by as much (as shadcn's earlier `calc(var(--radius) - 2px)`).

## Rules of one's own

A sheet is data, `{rules: Array<Rule>, light, dark}`, later rules
winning. `Tw.rules(slot, classes, ?variant, ?size)` turns a Tailwind class
list into rules at compile time; add them after shadcn's:

```haxe
ui.theme = {
	rules: Shadcn.sheet.rules.concat(Tw.rules("button", "rounded-full px-6"))
		.concat(Tw.rules("button", "bg-destructive/80 hover:bg-destructive", "danger")),
	light: Shadcn.sheet.light,
	dark: Shadcn.sheet.dark,
	lengths: Shadcn.sheet.lengths
};
```

or a sheet of one's own, `Tw.sheet("my-theme.json")` (beside the calling
module), in shadcn.json's format: `slots`, each a class list (a string, a
list as cn's, cva's `{base, variant: {...}, size: {...}}`, another slot's
`{extends: "button", variant: "ghost", class: "..."}`, classes under a
state the widget sets `{states: {"data-[side=right]": "..."}}`), `include`
(other files whose `slots` replace these), `radius`, `vars` (CSS variables a class names:
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
Dialog, AlertDialog, Sheet, Popover, HoverCard, Tooltip, Table, Progress, Accordion,
Toggle, ToggleGroup, Separator, Alert, Skeleton, Breadcrumb, Pagination,
Calendar (react-day-picker's parts as `calendar-<part>`, its range too), Command (cmdk's parts),
Resizable, Avatar, Kbd, Spinner, Drawer (vaul's), InputOTP, Field, ButtonGroup,
InputGroup, Empty, Item, Carousel (Embla's track as `carousel-track`),
NavigationMenu, Sidebar (its desktop parts), Chart (recharts' tooltip and
legend as `chart-tooltip`, `-tooltip-label`, `-tooltip-item`,
`-tooltip-name`, `-tooltip-value`, `chart-legend`, `-legend-item`,
`-legend-swatch`), ScrollArea, NativeSelect, and sonner's toast (in
extras.json: sonner's own stylesheet's values written as classes, `toaster`,
`toast`, `toast-title`, `toast-description`, `toast-icon`, `toast-action`,
`toast-close`).
Where shadcn styles an element without a slot, it is named after its
parent: `checkbox-icon`, `radio-group-icon`, `select-trigger-icon`,
`select-viewport`, `accordion-trigger-icon`, `dialog-close-icon`,
`sheet-close-icon`, `tooltip-arrow`, `pagination-previous`,
`pagination-next`, `drawer-handle`, `input-otp-caret`,
`navigation-menu-trigger-icon`, `carousel-track`, `field-separator-content`,
`input-group-text`, `button-group-text`; in extras.json, the
menus' `-item-indicator-icon` and `-sub-trigger-icon` (lucide's `size-4`,
`ml-auto size-4`) and `input-otp-separator-icon`. AccordionContent's inner box is folded into
`accordion-content`.

`src/hxmc/theme/extras.json` is ours, not shadcn's (shadcn.json stays a
transcription of shadcn's registry and includes it): class lists written
in shadcn's style from its own patterns and tokens, for what hxmc has and
shadcn has not, or has otherwise:

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
  `data-focused`); `pagination-link` (shadcn's
  `isActive` outline variant as `data-active`); `command-group-heading`
  (the group's `[&_[cmdk-group-heading]]:` classes); the rows of a
  checkbox, a switch and a radio option with their labels
  (`checkbox-field`, `switch-field`, `radio-group-option`: shadcn's
  examples' `flex items-center gap-3`, `gap-2`); `select-value` (the
  trigger's `*:data-[slot=select-value]:` classes);
  `dropdown-menu-trigger-icon`, `collapsible-icon`, `table-sort-icon`,
  `date-picker-value`, `tag-input-entry`; sonner's toast;
- hxmc's Chart, which is not recharts': its parts in flow (`chart`:
  `flex flex-col text-xs`), each series coloured by its `data-series`
  (1 to 5: `chart-1`...`chart-5`) on `chart-bar`, `chart-dot`, `chart-line`,
  `chart-area` and `chart-slice` (their text colour), `chart-legend-swatch`
  and `chart-tooltip-indicator`, the
  grid `bg-border/50`, ticks `text-muted-foreground` (recharts' `stroke-border/50`,
  `fill-muted-foreground` in shadcn's container);
- a scroll area's scrollbar as Radix shows it: thin, in `border`, on
  hover only (`[scrollbar-width:none] hover:[scrollbar-width:thin]`);
  a navigation menu's content in flow (shadcn's `md:absolute` in a
  viewport Radix sizes to it: here the viewport sizes itself);
- the calendar day's range classes (react-day-picker's day button's
  `data-[range-start=true]:`, `-middle`, `-end`, on the one day node).

Not transcribed (no hxmc part for them): FieldTitle (shadcn's second
`field-label`), InputGroupButton and InputGroupTextarea, NavigationMenu's
indicator, Sidebar's rail, input, group action, menu action, badge,
skeleton and sub-menus, the mobile sidebar (a sheet), Field's `responsive`
container query (kept, dropped by Tw, CSS's `@container`).

## Tw: Tailwind classes as rules

`Tw.rules` and `Tw.sheet` run at compile time. The rules are written as
compact data (`RuleData.hx`: a string table and a stream of small numbers)
read when the sheet is first used: shadcn's 1036 rules are 30 KB of data
(18 KB of rules, 13 KB of strings); a native program grows 99 KB over one
with an empty sheet (the data, its reader, and the colour, transform and
transition parsers it brings), and a build by under a second.
`-D hxmc.theme.dump` prints them and their size.

The subset of Tailwind v4 shadcn's components use (`Tailwind.hx`), read
with Tailwind's default theme and shadcn's on top, 1rem = 16px:

- layout: `flex`, `inline-flex` (a row: CSS's default direction, not
  ui's column), `grid`, `hidden`, `block` (a sheet's slot without a
  display one too: CSS's block box, its children at their own heights); `flex-col`, `flex-wrap`,
  `flex-1`, `shrink-0`, `grow`, `items-*`, `justify-*`, `self-*`,
  `justify-self-*`, `place-content-center`, `place-items-center`,
  `grid-cols-*`, `grid-rows-[...]`, `auto-rows-*`, `col-*`, `row-*`;
  `relative`, `absolute`, `fixed` (as absolute), `inset-*`, `top-*`...,
  `z-*`, `order-*` (`first`, `last`), `overflow-*`, `overflow-x-*`, `overflow-y-*`;
- spacing and sizes: `p-*`, `px-*`, `m-*` (negative and `auto` too),
  `gap-*`, `w-*`, `h-*`, `size-*`, `min-*`, `max-*` (the spacing scale,
  fractions, `full`, `fit`, `auto`, containers, `[1.15rem]`, calc() of
  lengths, the sheet's vars and `--spacing(n)`: `w-[calc(var(--sidebar-width-icon)+(--spacing(4)))]`); a side's
  class is that side's property (`paddingLeft`), as CSS's longhands;
- borders and corners: `border`, `border-*` (widths, sides, colours),
  `rounded-*` (`--radius` live, as above), sides and corners;
- colours: shadcn's tokens as `var(--name)`, with an alpha in percent
  (`bg-primary/90` is `var(--primary)/90`), `white`, `black`,
  `transparent`; `fill-*` (an icon's fill, as its colour);
- a scroller's scrollbar as arbitrary properties: `[scrollbar-width:thin]`,
  `[scrollbar-color:var(--border)_transparent]`;
- `shadow`, `shadow-*`, `ring-*`, `ring-offset-*`, `ring-inset` (rings as the
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
  `font-*`, `underline-offset-*`, `leading-*` (beating `text-*`'s line height, as in CSS: px as
  `lineHeightPx`), `tracking-*` (`letterSpacingEm`), `underline`,
  `uppercase`, `truncate`, `whitespace-nowrap`, `tabular-nums`,
  `text-center`...

Variants become the rule's `when` states, ordered as CSS's cascade
orders Tailwind's rules, so that "later rules win" is it: by specificity
(a pseudo-class, attribute, group, peer, `has-`, `not-` or shadcn's `dark`
variant one each, `data-[size=sm]` selecting a size too; a breakpoint,
`rtl`, `starting` none: `group-data-[...]:text-center` over `md:text-left`),
then Tailwind's order (the rule of a later variant later):
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
`group` and `peer`, container queries (`@container`, `@md/name:`),
viewport units (`h-svh`), native appearance and list markers, dashed
borders and a side's border colour, `nth-*`, what Radix's popper measures,
what has no property yet (`scroll-m*`, `touch-none`), a table's own layout, `text-balance`,
`sr-only`; arbitrary selectors (`[&_svg]:size-4`, `[a&]:hover:`; but
`has-[>svg]:`, and a slot's children's `[&>*]:`, `[&>*:not(:first-child)]:`,
`[&>*:not(:last-child)]:`: rules of any slot whose parent is the slot,
Rules' `parent:`, a side they leave the child's own; and `has-[...]` of
attributes and states, `has-[[data-slot=x]:focus-visible]`, not of an
element's type), children's and descendants' (`*:`, `**:`, given to
the part's own slot where hxmc has one), pseudo-elements (`after:`) and
`file:`.

## CSS

The same sheet as CSS, for the DOM's widgets (packages/web,
`hxmc.web.widgets`), or any markup with shadcn's `data-slot`s:

```sh
haxe -lib hxmc.theme --run hxmc.theme.Css shadcn.json app.css   # a sheet's path, or a bare name: this package's
```

`Css.sheet(path)` (natively or on Eval) reads the same JSON as `Tw.sheet`
(`Sheet.hx`: one reader for both) and writes each class as the CSS
Tailwind v4 writes for it (`test/tailwind.txt` holds Tailwind's own for
every class of shadcn.json and extras.json, from `test/css-ref.mjs`;
`CssTest` compares them rule by rule), with the slot's selector for the
class's: `[data-slot=button]`, a cva variant or size as
`:where([data-variant=outline])` (as specific as the class it stands
for), a group or a peer as the slots whose class lists mark them
(`group/tabs`: `[data-slot=tabs]`), an icon's `[class*='size-']` as an
icon with a slot of its own. A slot's rules are grouped by selector, in
Tailwind's order (by their variants; a variant's or size's after the
base's, as tailwind-merge keeps the later); theme values written out
(`calc(var(--spacing) * 4)` is `1rem`). Around them: Tailwind's preflight,
the tokens (`:root`; `.dark`; and the system's dark unless `.light`, the
`dark:` rules again under `prefers-color-scheme`), shadcn's globals
(border and outline colours, the body's), breakpoints as media queries,
`rtl:` as `[dir=rtl]`, transitions, tw-animate-css's enter animations as
transitions from `@starting-style`. Unlike the rules, nothing is ignored:
arbitrary selectors (`[&_svg]`), children's (`*:`), `after:`, `sr-only`,
keyframe animations (`animate-spin`, `animate-pulse`). shadcn's sheet is
188 KB, 18 KB gzipped (the sheet's vars, `--sidebar-width`, in `:root`).

`Css.classes(selector, "rounded-lg border shadow-md")`: classes of one's
own as CSS, at run time too (an instance's, as cn's className).

## Checks

`make theme-check` (`test/ThemeTest.hx`, on Eval): class lists read as
rules, Tw's rules made at compile time, shadcn's sheet made, the
classes Tw rejects. `make theme-fidelity-check`: each themed widget drawn
headless against shadcn's own markup and CSS drawn by Chromium
(`test/ref/*.png`, 252 cases of every shadcn component: variants, sizes,
hover, focus, disabled, invalid, checked, open, light, dark and right to
left; `test/ref.mjs` writes them with Tailwind 4.3.3 and sonner 2.0.8),
popups compared in their box; the cases known to differ, for what
`hxmc.ui` lacks yet, reported, not failed (`FidelityTest.KNOWN`, each with
its reason). `make theme-dom-check`: the DOM's widgets under the CSS in
Chromium against the same references (`test/dom-fidelity.mjs`,
`DomFidelity.hx`), the state forced and the popups opened as ref.mjs
does: all 252 within a mean difference of 1 and 0.5% of the pixels apart
by more than 64, most of them identical.
