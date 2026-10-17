# Unstyled widgets and a shadcn theme

`@hxmc/ui`'s widgets ship unstyled, as React Aria Components do: only
behaviour (pointer, keyboard, focus, selection, popups, drag), semantics
(roles, states, labels for assistive technology) and the structure of
parts; no colours, borders, radii, shadows, padding, sizes or fonts, and
no fallback look. Each widget exposes its states (hover, pressed,
focus-visible, selected, disabled, open, …) as signals and as attributes
on its parts, and an instance's style may be a function of them. Looks
come from a theme. One theme ships, `@hxmc/theme`, based on
[shadcn/ui](https://ui.shadcn.com) (MIT): its components, token names,
slot names, variants and sizes, and its class lists copied verbatim.

## The contract

Both halves build against this; neither waits for the other.

- **Slots.** Every node a widget makes that a theme may style carries a
  slot, named as shadcn's `data-slot`: `button`; `input`; `textarea`;
  `checkbox`, `checkbox-indicator`; `switch`, `switch-thumb`; `slider`,
  `slider-track`, `slider-range`, `slider-thumb`; `radio-group`,
  `radio-group-item`, `radio-group-indicator`; `tabs`, `tabs-list`,
  `tabs-trigger`, `tabs-content`; `select-trigger`, `select-value`,
  `select-content`, `select-item`, `select-item-indicator`;
  `dropdown-menu-content`, `dropdown-menu-item`, `dropdown-menu-shortcut`,
  `dropdown-menu-separator`; `dialog-overlay`, `dialog-content`,
  `dialog-header`, `dialog-title`, `dialog-description`, `dialog-footer`,
  `dialog-close`; `popover-content`; `tooltip-content`; `card`,
  `card-header`, `card-title`, `card-description`, `card-content`,
  `card-footer`; `table`, `table-header`, `table-body`, `table-row`,
  `table-head`, `table-cell`; `badge`; `progress`, `progress-indicator`;
  `accordion-item`, `accordion-trigger`, `accordion-content`; `toggle`;
  `toggle-group`, `toggle-group-item`; `separator`; `label`; and the
  others' as shadcn names them (breadcrumb, pagination, calendar,
  command, menubar, context-menu, sonner). A widget shadcn lacks (Tree,
  Split, Listbox, Sortable, ColorPicker, TagInput) takes names in the same
  style.
- **States**, as Radix's attributes: `data-state` (`open`/`closed`,
  `checked`/`unchecked`/`indeterminate`, `active`/`inactive`, `on`/`off`),
  `data-disabled`, `data-highlighted`, `data-selected`,
  `data-orientation`, `data-side`, `aria-invalid`, `aria-selected`; and
  the interaction states `hover`, `active`, `focus`, `focus-visible`,
  `disabled`, `placeholder`.
- **Variants and sizes** are widget props with shadcn's names: Button
  `variant` `default|destructive|outline|secondary|ghost|link`, `size`
  `default|sm|lg|icon`; Badge, Toggle, Alert likewise.
- **Names follow shadcn** where a widget has a shadcn counterpart:
  `Toggle`→`Switch` (shadcn's Toggle is a pressable button, added as
  such), `Field`→`Input`, `Area`→`Textarea`, `Radio`→`RadioGroup`,
  `SegmentedControl`→`ToggleGroup`, `Disclosure`→`Collapsible`,
  `Menu`→`DropdownMenu`, `Breadcrumbs`→`Breadcrumb`. Card, Badge, Label,
  Separator, Alert, Skeleton are added.
- **Rules.** A theme is data: `Array<Rule>`, with
  `Rule = {slot:String, ?variant:String, ?size:String, ?when:Array<String>, style:StyleProps}`.
  `when` holds states (`"hover"`, `"data-state=checked"`,
  `"focus-visible"`, `"dark"`); all must hold. Later rules win, as in
  CSS source order; an instance's own `style` wins over every rule.
  Colour values may name tokens, `var(--primary)`, with an alpha,
  `var(--ring)/50`, resolved when applied, so switching light and dark
  re-resolves without rebuilding rules.
- **Tokens** are shadcn's: `background`, `foreground`, `card`,
  `card-foreground`, `popover`, `popover-foreground`, `primary`,
  `primary-foreground`, `secondary`, `secondary-foreground`, `muted`,
  `muted-foreground`, `accent`, `accent-foreground`, `destructive`,
  `border`, `input`, `ring`, `chart-1`…`chart-5`, the `sidebar-*` set, and
  `radius` (with `radius-sm|md|lg|xl` derived as shadcn does). Values are
  shadcn's default neutral theme in `oklch()`, light and dark.

## Who builds what

- **The UI session** (`packages/ui`):
  - the rule engine: slots and states on nodes, rules matched and applied
    reactively as states change, token resolution (`var()`, alpha,
    `oklch()` in colours), a theme installed per window and overridable
    per subtree;
  - every widget converted: styling removed, slots, states, variants and
    sizes added, the renames, the added widgets; `Theme.hx` removed. In
    this order, so the theme can be checked early: Button, Input,
    Checkbox, Switch, Label, Card, Badge; then the rest.
  - unstyled means behaviour only: no built-in look to fall back on; the
    checks for an unstyled widget are behaviour and semantics (events,
    keyboard, focus order, the accessibility tree), not pixels.
- **Here** (`packages/theme`, new):
  - a compile-time macro that turns Tailwind class lists into `Rule`s:
    the subset shadcn's components use (spacing, sizing, flex, radius,
    borders, colours with `/alpha`, shadows, rings, typography, `hover:`,
    `focus-visible:`, `disabled:`, `data-[state=…]:`, `aria-invalid:`,
    `dark:`, `[&_svg]` dropped); no class parsing at run time;
  - the theme: shadcn's tokens, and each component's class lists copied
    from shadcn's source (the new-york style, Tailwind v4) through the
    macro;
  - fidelity checks: each themed widget drawn by hxmc against shadcn's
    own markup and CSS rendered in Chromium, per state and variant, as
    the layout checks do;
  - the gallery and the site: widgets shown unstyled and themed.

## Order

1. This contract (here).
2. In parallel: the rule engine and Button through Badge (UI session); the
   macro, tokens and those components' rules (here).
3. Integration on those seven, then the remaining widgets in batches, each
   batch converted there and themed here, merged together.

## Built

### Unstyled vs themed

Unstyled, a widget is behaviour and semantics only: its parts are laid
out as the interaction needs (a slider's thumb along its track, a popup
by its trigger) and carry their slots, variants, sizes and states, but
draw nothing, no colour, border, radius, padding or font of their own;
checked by events, keys, focus order and the accessibility tree. The
examples and tests that want something visible without shadcn use
`packages/ui/examples/Plain.hx`, a few rules in the text's colour.

Themed, `ui.theme = Shadcn.sheet` (or a subtree's `node.theme`): 769
rules made at compile time from shadcn's class lists (`packages/theme`,
README) style every slot by its variant, size and states, light and dark
(`ui.dark`), with rings, outline-style, transitions and enter animations
(`starting`) as Tailwind draws them; a widget shadcn lacks (Tree, Listbox,
Sortable, NumberField, TagInput, ColorPicker, Toolbar) has rules in
shadcn's style, ours (`packages/theme/src/hxmc/theme/extras.json`). An instance's own style, or a function of
its states, wins over every rule. Checked against shadcn's markup drawn by
Chromium (`make theme-fidelity-check`, 203 cases), what still differs
listed with its reason in `FidelityTest.KNOWN`.
