# helder.ui

A UI toolkit for hxmc in pure Haxe: a node tree laid out with flexbox,
drawn with the GPU (`helder.gfx`), written in markup with fine-grained
signals, Solid's way (`helder.view`, which renders into its nodes).

```haxe
import helder.ui.draw.UiWindow;
import helder.view.*;
import helder.view.Reactive.*;

class Counter implements Markup {
	static function main() {
		var count = signal(0);
		var w = new UiWindow("Counter", 320, 200);
		Render.render(<view grow={1} padding={24} row-gap={12} align-items="center" justify="center">
			<text font-size={32}>{count}</text>
			<view:button role="button" focusable padding="8 16" radius={6} background="#18181b" color="#fafafa" cursor="pointer"
				onPress={_ -> count.value++}>+1</view:button>
		</view>, w.root);
		UiWindow.run();
	}
}
```

```hxml
-lib helder
-main Counter
--custom-target hxmc=counter
-D hxmc.libc=glibc   # Linux: the GPU drivers are glibc libraries
```

[GUIDE.md](GUIDE.md) walks through building an app: components, state,
lists, popups, your own nodes, each platform, tests.
`examples/todo/Todo.hx` is a complete app (a text field, a keyed
list, checkboxes, filters), `examples/mail/Mail.hx` a larger one (a
toolbar, folders, messages sorted by column, search, shortcuts, undo, dark
mode), both styled by a small `StyleSheet` of their own. They run natively on Linux, macOS and Windows, and in a browser
(wasm32-wasi on WebGPU or WebGL2).

## The parts

- **`helder.ui`**, the core, plain Haxe (it runs on any target; its tests
  run on Eval): `Node` and `TextNode`, `Style`, `Layout`, `Ui`.
  - Layout is CSS flexbox, column by default: `direction`, `wrap`,
    `justify`, `alignItems`, `alignSelf` (`Baseline`: a row's items on their
    first baselines, a text's first line's, a box without one on its bottom
    edge; a column's on their start edges), `alignContent`, `grow`,
    `shrink`, `basis`, `width`, `height`, min and max (widths also
    `min-content`, `max-content`, `fit-content`: CSS's intrinsic sizes;
    `"calc(100% - 2px)"`, `Calc(100, -2)`: a percentage plus pixels),
    `aspectRatio`,
    `padding`, `margin` (`auto`, `Edges.AUTO`: CSS's auto margins, along and
    across flex lines, in grid areas, on absolute boxes), `borderWidth`,
    `rowGap`, `columnGap` (`gap` both; `flex`, `inset`: CSS's shorthands,
    `flex="none"`, `inset="0 10"` in markup), `position`
    (Absolute with `left`, `top`, `right`, `bottom`; both offsets and a
    size on an axis: placed between them by `justifySelf` and `alignSelf`;
    an auto width shrinks to fit), `overflow` (Hidden,
    Scroll), `dir` (Rtl: rows from the right, columns' items across
    from the right, grids' columns from the right, text aligned right by
    default, paragraphs in that direction; inherited; margins and padding
    stay physical; a scroller's content overflowing to the left scrolled to
    by negative `scrollX` from 0 at its right end, as Chromium's
    scrollLeft, its vertical bar on the left), `order` (laid out,
    painted and hit in it; Tab keeps the tree's order), `zIndex` (painted
    and hit over or under siblings; no stacking contexts across levels).
    Sizes are border boxes. Items get CSS's automatic minimum
    size, so content is not squashed (their content's, not their own
    `height`: an empty box of a fixed height shrinks in a column it
    overflows, as in CSS; `shrink: 0` keeps it; a scroll container's is 0,
    in grid tracks too). A column's auto height is its content's, however tall: a
    flex item holding a scroller wants `minHeight: 0`, as in CSS, else it
    grows to all of the scroller's content. `display: Block` is CSS's block
    layout: a column whose children neither grow nor shrink (a row
    direction given makes it a flex row). `display: Grid` lays children out
    on CSS grid tracks instead: `gridTemplateColumns` and
    `gridTemplateRows` (px, %, fr, auto, min-content, max-content,
    minmax(), repeat()), `gridAutoRows`, `gridAutoColumns`,
    `gridAutoFlow`, `gridTemplateAreas` ("'head head' 'side main'"), items
    placed by `gridColumn` and `gridRow` ("1 / 3", "span 2", negative
    lines, an area's name) or `gridArea`, or auto-placed (`gridAutoFlow`:
    by rows or columns, sparse or dense), aligned by `justifyItems`,
    `justifySelf`, `alignItems`, `alignSelf`, the tracks by `justify` and
    `alignContent` (no other named lines, no subgrid). Checked against
    Chromium on 143 cases, 39 of them grids, 8 right to left.
  - Text properties inherit: `color`, `fontFamily`, `fontSize`,
    `fontWeight`, `italic`, `lineHeight` (a multiple of the font size;
    `lineHeightPx`: pixels, inherited as pixels), `letterSpacing`
    (`letterSpacingEm`: a multiple of the node's font size, inherited as
    the pixels it comes to), `wordSpacing`,
    `textAlign` (left, center, right, justify: the room shared among the
    spaces as Chromium shares it; spacing added as Chromium adds it),
    `textWrap` (`NoWrap`, CSS's text-wrap-mode: each line kept whole, past
    its box, its min-content width that wide), `overflowWrap` (`BreakWord`
    by default, where CSS's is `Normal`: a word too wide is cut, not
    overflowing; `Anywhere`: its min-content width too), `wordBreak`
    (`BreakAll`, `KeepAll`; soft hyphens break as in CSS: lines as
    Chromium breaks them), `textTransform` (`Uppercase`,
    `Lowercase`, `Capitalize`: letter for letter; a span its own; a text
    field's text as typed), `textOverflow` (`Ellipsis`, not inherited: a
    line too wide for its box ends in one within it). `textDecoration`
    (underline, line-through, overline) draws its lines with the text inside
    the node, in its colour (`textDecorationColor`: another), as thick as
    `textDecorationThickness` says (a tenth of the font size by default), an
    underline `textUnderlineOffset` below the baseline, where Chromium
    draws them. `textShadow`
    (`"1px 2px 4px #0006"`, several, inherited, `none`) draws the text's
    and its lines' shadows under them (a text field's and its placeholder's
    too), blurred as Chromium blurs them
    (BoxTest compares them). `fontFeatureSettings` (`"'tnum'"`,
    `"'liga' 0, 'ss01'"`, inherited) asks for OpenType features as CSS's
    font-feature-settings does; `fontVariantNumeric` (`"tabular-nums"`,
    `"oldstyle-nums slashed-zero"`) as font-variant-numeric does, under it.
    `maxLines` cuts a
    text to so many lines, the last ending in an ellipsis where Chromium's
    line-clamp puts it.
  - Paint: `background`, `borderColor`, `radius` (`corners`, or markup
    `radius="12 12 0 0"`: each corner's, as CSS's border-radius; `borders`,
    or `border-width="0 0 2 0"`: each side's width, laid out and drawn, the
    inner corners quarter ellipses as Chromium draws them), `opacity`, `shadow`
    (CSS's box-shadow: `"0 2px 8px rgba(0, 0, 0, 0.25)"`, x, y, blur, spread,
    colour; `inset`; several, comma-separated; blurred by a Gaussian as
    Chromium blurs them, within a few levels of its pixels), `outlineWidth`,
    `outlineOffset`, `outlineColor` (or markup `outline="2px solid red"`: a
    solid line around the border box over the content, its corners the
    box's grown, as Chromium draws it; BoxTest compares them), `outlineStyle`
    (`Auto`, the default: the window's focus ring while focused by the
    keyboard; `Solid`: only the outline; `None`: neither, as CSS's
    `outline-style: none`), `ringWidth`, `ringColor`, `ringOffsetWidth`,
    `ringOffsetColor`, `ringInset` (Tailwind's ring: spread shadows of no
    blur over the node's own `shadow`, the offset over the ring, each from
    its own property or rule), `paddingTop`...`paddingLeft`, `marginTop`...
    `marginLeft` (one side each, a margin's may be `Edges.AUTO`: rules for
    `pt-2` and `px-4` combine), `userSelect` (inherited: `None`, `Text`, `All`:
    whether a drag selects its text, as CSS's user-select), `overflowX` and
    `overflowY` (both clip when either does, as CSS's; an axis scrolls by the
    wheel, keys and scrollbar only where it is `Scroll`), `fieldSizing`
    (`Content`: a text area as tall as its lines, as CSS's field-sizing), `scrollbarWidth` (`Thin`, `None`:
    CSS's scrollbar-width), `scrollbarColor` and `scrollbarTrackColor` (inherited,
    CSS's scrollbar-color), corner radii scaled down together where a side's
    two add up to more than it (as CSS: `9999` a pill), `cursor`,
    `visibility` (inherited; `Hidden` keeps the node's place but draws,
    hits, focuses and shows it to assistive technology no more, while a
    `Visible` descendant still is), `pointerEvents` (inherited; `None` lets
    the pointer through to what is under it, an `Auto` descendant still
    found). Colours are
    CSS's (`Color.parse`: hex, `rgb()`, `hsl()`, the 148 names, as Chromium
    computes them); `backgroundImage` (markup: `background="linear-gradient(...)"`)
    is a CSS gradient, linear or radial, repeating or not (`Gradient`: within
    two levels of Chromium's pixels on 19 cases), under the border.
  - `position: Sticky` (Style only for now, markup to come with helder.view):
    laid out in the flow, then kept its `top`, `left`, `right` or `bottom`
    inside its nearest scroller's content box as it scrolls, within its
    parent's content box, drawn and hit over its siblings, where Chromium
    sticks it.
  - Transforms: `transform` (CSS's: `translate`, `scale`, `rotate`,
    `skew`, `matrix`, composed left to right; `Transform.parse`, or
    `Transform.rotate(45)`) about `transformOrigin` (`"left top"`, `"50% 0"`;
    the centre by default) moves how a node and its subtree are drawn and
    hit, not their layout; pointer events' `localX`/`localY` and
    `Node.localX` go through it. The renderer turns quads on the GPU,
    their edges anti-aliased over a pixel, and rasterizes glyphs at the
    scaled size (on the pixel grid when the transform only moves and
    scales evenly), within half a level of Chromium's pixels on average.
    Under a turning transform a clip is its bounds.
  - Transitions: `transition` (CSS's shorthand, `"background-color
    150ms ease-in-out, opacity 0.2s"`; `Transition.parse`): once a node
    has been drawn, a change of a property it names (colours, opacity,
    transform, box-shadow; `all`) eases on the `Clock` from where it is,
    along CSS's timing functions (cubic Béziers), colours with their
    alphas premultiplied, transforms function by function, shadows shadow
    by shadow, as Chromium interpolates them; `style.target(name)` is
    where it goes. A theme's rules set it as any property.
  - Images: `Image` (RGBA8 pixels; `Image.decode` reads PNG files of every
    colour type, depth and interlacing, JPEG files, baseline or
    progressive, decoded as browsers do, the EXIF orientation applied,
    GIF files' first frame, and WebP files, lossless or lossy, with alpha
    (pixel-exact with libwebp's decoding), an animation's first frame; `AnimatedImage` plays a GIF's,
    WebP's or animated PNG's frames, each composed as Chromium composes it, on the clock), shown by an `ImageNode` at its own
    size or the style's (keeping its aspect ratio), fitted as `Fill`,
    `Contain`, `Cover` or `None`, placed by `position` (CSS's object-position:
    `"right 10px top"`, markup `object-position`; centred by default, the
    part outside cut), its corners rounded with the node's.
  - SVG: `Svg.parse` reads the static subset icon sets use (shapes, all of
    path data, fills and strokes with their joins, caps and dashes, linear
    and radial gradients, opacities, transforms, use and symbol, clip-path,
    nested viewports, CSS colours, currentColor); `render` draws it at any
    size, checked against Chromium's pixels on 30 cases. An `ImageNode`'s
    `svg` (markup: `src={svg}`) is drawn at the window's pixel size in the
    node's colour. Not drawn: text, images, patterns, masks, filters, markers.
  - A `TextNode` that is `selectable` takes a selection from the pointer (a
    drag, a double click: a word, a triple: all), painted under its text
    (`Ui.textSelection`, `Ui.selectionColor`) and copied by Mod+C.
  - `Ui` dispatches pointer, wheel, key and text events to nodes (bubbling
    to ancestors), tracks hover and press, moves the focus (click, Tab,
    Shift+Tab; a ring shows when the keyboard moved it) and scrolls
    `Overflow Scroll` nodes (the wheel or a trackpad, by the pixels it
    moved, Shift turning a wheel sideways; in a browser a finger's drag,
    gliding on when let go moving, a tap a click; their scrollbars'
    thumbs; or the keys a browser scrolls with, when the focus took none of
    them: the arrows by 40 pixels, Page Up, Page Down and Space by seven
    eighths of the view, Home and End, eased over `Ui.scrollDuration`;
    `Ui.scrollBy` eases the same way). A node's key handler calls
    `preventDefault` (or `stop`) on the keys it takes.
- **`helder.ui.draw`**: the GPU renderer. One shader draws rounded rectangles
  with borders, soft shadows and glyphs from an atlas, every fragment
  clipped by a rounded rectangle (one draw call a frame); `UiWindow` puts a
  `Ui` in an `helder.os` window, shows the hovered node's cursor and runs
  the loop. On macOS the app has the usual menu bar (Hide, Quit, the Window
  menu); Quit asks each window to close, as its close button does.
- **`helder.ui.view`**: `helder.view`'s renderer for these nodes
  (`NodeRenderer`; `-lib helder` names it with `-D
  helder.view.renderer.ui`), the markup's attributes (`StyleAttrs`, generated
  from `Style`'s properties: a property added to `Style` is an
  attribute), and what is ui's own: the control flow components
  `VirtualList` (only the rows in view made: a list of 100000 rows scrolls
  as one of 20), `Popover` and `Hotkey` (`UiFlow`), and `Motion`:
  `transition`, `spring` and `color` are signals moving toward a target
  as the `Clock` ticks (a window ticks it each frame and keeps drawing
  while anything moves; `Clock.finish()` ends every animation, for tests). Signals (`signal`,
  `memo`, `effect`, `batch`, `untrack`, contexts), `Render` and the
  control flow components `For`, `Index`, `Show`, `Switch`,
  `ErrorBoundary` are `helder.view`'s ([its README](../view/README.md)).
- **`helder.ui.widgets`**: text editing, `TextField` (caret, selection,
  keyboard editing, `cut`, `copy`, `paste`, `selectAll`) and `TextArea`
  (lines: wrapping, Up and Down, scrolling), both on `EditableText`, with
  an input method's composition shown at the caret (markup's `<field/>`
  and `<field:textarea/>`); `Icons`, lucide's icons by name (markup's
  `<icon/>`). Other controls (buttons, checkboxes, menus) are views with a
  role, `focusable` and `onPress`, as in the examples and `GUIDE.md`. A
  `UiWindow`'s `Ui.dark` follows the system's appearance
  (`helder.os.App.prefersDark`: the browser's colour scheme, macOS's,
  Windows', GTK's settings).
- **Popups**: `Popup` nodes are layers over the tree (`Ui.open`, `Ui.close`:
  children of `Ui.overlay`, drawn and hit after the tree, not clipped by
  it), anchored to a node (below, above, beside; flipped and kept in the
  window), in a corner of the window (notifications), at a point (a context menu) or modal (a backdrop, the focus kept inside); a press outside or
  Escape asks them to close. In markup, `UiFlow.Popover` puts its children
  in one while `open` is true.
- **Shortcuts**: `Ui.shortcut("Mod+S", action, ?scope)` (`Shortcut`: Mod is
  Control or Command; labels in each platform's notation), run when the
  focused node does not take the key, scoped to a subtree or to a modal
  popup; `UiFlow.Hotkey` in markup, and menu items' `shortcut`.

## Markup

Intrinsic elements: `view` (a box), `text` (a run of text), `scroll` (a box
that scrolls), `image` (an `ImageNode`: `src={image}` or `src={svg}`, `fit="cover"`, `object-position="left top"`).
Inside a `text`, elements are spans of rich text: `span`, `b`, `i` or
`text` again, each with its own style (colour, weight, size...) and
handlers (a link: `<span color="#2563eb" onClick={...}>`); lines are as
high as CSS makes them, their spans on one baseline.
Attributes:

- any Style property, in camelCase or kebab-case, with values as CSS
  writes them: `direction="row"`, `justify="space-between"`,
  `padding="8 12"`, `width="50%"`, `background="#3b82f6"`, `radius={6}`;
  `style={...}` takes a typed `StyleProps` object;
- events: `onClick`, `onPointerDown`, `onPointerUp`, `onPointerMove`,
  `onPointerEnter`, `onPointerLeave`, `onWheel`, `onKeyDown`, `onKeyUp`,
  `onTextInput`, `onFocus`, `onBlur`, `onFocusIn`, `onFocusOut` (bubbling) (an `Event -> Void`);
  `onPress` (`Node.onActivate`: a click, or Enter or Space unless `onKeyDown`
  took it, as a DOM button's click);
- `focusable`, `ref={n -> ...}` (the node), `tag="name"` (for `Node.find`);
  `id` none here (a page's element's, where a page's renderer realises
  the element).

The elements are also the neutral ones of single-source components
(`@:neutral`, src/helder/view/README.md): `view:button`, `view:label`... and
`text:p`, `text:h2`... are a view and a text here, the element of that name
in a page; `<icon name="check"/>` draws lucide's icon of that name
(`helder.ui.widgets.Icons`, an inline SVG in a page; `mirrored` flips it
right to left, `data-mirrored` in a page); `<field/>` and
`<field:textarea/>` are a text field (`TextField`, `TextArea`: native
where `Ui.policy` says; a page's `<input>`, `<textarea>`): `value`,
`placeholder`, `type` (`password`: dots), `rows`, `readonly`,
`maxlength`, `inputmode` and `autocomplete` (a page's), `onInput` (its
text changed by its user: `e.text`), its own editing after the markup's
`onKeyDown`... unless that prevented the default; a ref of theirs gets an `helder.ui.Part` (Node is one: `focus`,
`rect`, `scrollIntoView`, `contains`, `attr`, `rtl`, `capture`: a press's
moves and release to it; `select`: a field's selection).
- drag and drop: `drag-data={value}` makes a node draggable; `onDragStart`,
  `onDragEnd` (`e.dropped`) on the source, `onDragOver` (`e.preventDefault()`
  accepts), `onDragLeave` and `onDrop` (`e.data`) on targets; Escape cancels.

A value that is a signal, a memo or a function is reactive: the attribute,
text or region follows it. In a `view`, text and text-valued holes next to
each other become one `TextNode`.

Tags and attribute names are resolved at compile time, so a program links
only the nodes, attributes and value parsers its markup names (a gradient
parser only with a gradient, image nodes only with `image`). A name none of
them has, a spread (`{...props}`) or `NodeRenderer.setAttribute` looks the
name up at run time and links them all.

## Themes

A node's look is its style, or a theme's: a `StyleSheet` of `rules`, each
a `Rule` `{slot, ?variant, ?size, ?when, style}`, and the colours its
token references name, `light` and `dark`. A node takes the rules of its
`slot` (the name of the part it is: `"button"`, `"switch-thumb"`),
`variant` and `size` whose states all hold: `hover`, `active`,
`focus`, `focus-visible`, `disabled`, `dark`, `rtl` and `ltr` (its direction), `starting` (until it is first drawn, as CSS's `@starting-style`: its transition then eases from there), `sm`, `md`, `lg`, `xl`, `2xl` (the window at least Tailwind's breakpoint wide), `placeholder` (an
input's placeholder colour), `selection` (its selection's background), attributes (`data-state=checked`, a bare
`data-disabled`; `node.setAttr`, markup `data-state="checked"`;
`data-slot=x` is the slot), and other nodes' states, as Tailwind's
variants: `group:hover` (an ancestor with a `group` attribute hovered;
`group/item:` one whose attribute names `item`), `peer:data-state=checked`
(an earlier sibling with a `peer` attribute), `has:focus` (a descendant;
`has:>x` a child), `first`, `last`, `not:x`, nested as
`group:has:focus`. Later
rules win, property by property; the node's own style wins over them
(a value still its default counts as none: `Rules.keep(node, ["padding"])`
holds its own at any value, as an instance's `p-0` over its slot's `p-4`).
Lengths may be token references too: `Length.token("radius", -4)` is
`calc(var(--radius) - 4px)`, resolved with the sheet's `lengths` (radii).
Colours may be token references, `Color.parse("var(--primary)")`,
`"var(--ring)/50"`, resolved with the sheet's colours when applied;
`oklch()` and `oklab()` parse as CSS converts them (Chromium's pixels).
`ui.theme = sheet` installs one for a window, `node.theme` for a subtree,
`ui.dark` picks the dark colours and the `dark` rules; every change of a
state, attribute, variant, sheet or of dark applies them again, at the
window's next update (several changes, one restyle). Without a sheet a
node has no look but its own style, unless a program adds base rules
(`Rules.addBase`: where no sheet applies). The examples' sheets are their
own (`Todo.sheet`, `Mail.sheet`). A part's states are signals (`helder.ui.view.States.of(node)`:
`hovered`, `pressed`, `focused`, `focusVisible`, `disabled`,
`attr("data-state")`...), and a node's `states` attribute is a function of
them, as React Aria's render props: `<view:button states={(s:States) ->
(s.pressed.value ? {opacity: 0.8} : {} : StyleProps)}>` (typed: a function
literal markup cannot type is a reactive value; over the theme's rules;
what it stops giving, the theme's again). The system colours `Canvas` and `CanvasText` are a sheet's colours of those
names, else Chromium's, light or dark; a page's slot `"body"` takes them
(a page's background and text colour), and the layers
(popups, dialogs: `ui.overlay`) inherit its text, as a page's popups in
its body do (`ui.body`).

## Fonts

Text is shaped and rasterized by `helder.text` with the system's fonts
(`sans-serif` by default). Colour emoji come from the system's emoji font,
drawn from its bitmaps (scaled down as a browser does) or colour layers. In a browser, give the page's fonts to `run`
(`fonts: [...]` with `src/helder/text/imports.mjs`).

## Native controls

`helder.ui.native` puts the platform's own controls in the same node tree:
a `NativeHost` window whose `Control` nodes (button, checkbox, text field,
slider, progress bar) are native widgets and whose `TextNode`s are native
labels, measured by the platform, laid out by helder.ui's flexbox and placed
absolutely; the markup and signals are the same (`import
helder.ui.native.Controls.*`: `Button`, `Checkbox`, `Field`, `Slider`,
`Progress`). The backends: GTK 3 on Linux (glibc mode; tested under Xvfb by
`NativeTest`) and the DOM in a browser (the page's own controls in a
container, `nativeContainer` in run's options, with
`src/helder/ui/imports.mjs`; tested in Chromium by `native-web.mjs`); the
same `examples/NativeForm.hx` runs on both. Plain nodes only lay out (no
backgrounds), and nothing scrolls yet. Win32 (the standard controls,
comctl32 5's classic look until a visual styles manifest) and AppKit run
`NativeTest` in CI. On Android the controls are `android.widget`'s views
(through JNI; `NativeHost.run` hands the steps to Java's main thread),
checked on an emulator by `AndroidNativeTest` with taps, text typed
through the input method and the accessibility tree; a `GpuView`
(`helder.ui.native.android`) is a GPU view among them, where gfx draws
(`AndroidMixTest`).

### Native or drawn, per widget

In a drawn window a widget can also be the platform's own control
(docs/plans/native-or-drawn.md): `host` on a node (`Auto`, `Native`,
`Drawn`; markup's `host="native"`) holds for its subtree, and where the
tree leaves it `Auto` the window's `Ui.policy` decides per kind of widget
(`"text-field"`, `"text-area"`, `"context-menu"` and `"menubar"`: native, the plan's defaults). Native
needs the window's `Ui.platform` (`PlatformViews`); without one, or for a
kind it lacks, the widget is drawn. Text fields and areas first: the
platform's editor sits over the field's content box, borderless and
transparent in the field's font, colour and alignment, the theme drawing
the box, ring and placeholder's colour; its text, selection and focus
follow the node's both ways, the keys it leaves to the program (Tab,
Escape; Enter, Up and Down on one line) go to the window, and the field is
drawn again while a popup covers it or a scroller clips it. In the
browser the editors are the page's input and textarea over the canvas
(`WebViews`; `web-field.mjs` drives them in Chromium); on Windows EDIT
controls, children of the window, coloured through WM_CTLCOLOREDIT with the
background behind them (`WinViews`; `WinAccessTest`); on macOS
NSTextFields over the window's content view (a password's an
NSSecureTextField) in the field's font, colour and alignment, a text area an
NSTextView in a borderless NSScrollView (`MacViews`; `MacAccessTest`). Linux (X11, no toolkit)
and Android draw them still. The platform's menus are there for a
program's own: `PlatformViews.menu` shows a context menu (its items,
separators, checked and disabled ones, submenus and shortcuts' labels):
Windows' popup menu, macOS's NSMenu; `PlatformViews.menuBar` a menu bar,
the system's on macOS (its menus after the application's) and the
window's own on Windows (SetMenu: its items' commands the window's
WM_COMMAND).

## Accessibility

`helder.ui.access` builds the tree assistive technology sees (AccessKit's
model: roles, names, states, actions) from the nodes: each node's
`semantics` (in markup: `role`, `label`, `description`, `checked`,
`selected`, `expanded`, `disabled`, `value-now`, `value-min`,
`value-max`, `value-text`, `multiselectable`, `live`, `current`), text as labels,
focusable nodes as groups; the text fields declare theirs. A `navigation`
role is a landmark (ARIA's navigation, AT-SPI's landmark, UI Automation's
navigation landmark type, macOS's AXLandmarkNavigation); `current` marks
the current one of a set (aria-current="page"; AT-SPI's current
attribute, UI Automation's AriaProperties; macOS has no property for it). A live region
(`live="polite"` or `"assertive"`) has its changes announced
(`AccessTree.announcements`: its new text): ARIA's aria-live, AT-SPI's
Announcement, UI Automation's LiveRegionChanged, macOS's announcement
request. `Ui.accessTree()` gives it, `AccessTree.changes`
the incremental update, `Ui.accessAction` does what a screen reader asks
(click, focus, increment, decrement, set a value). In a browser the window
mirrors it as ARIA elements inside its canvas (the canvas's fallback
content: in the page's accessibility tree, not drawn): load
`src/helder/ui/imports.mjs` with the others. On macOS the window gives it to
NSAccessibility (`MacAccess`: an element per node, its role, label, value
and frame; press, increment and decrement come back as actions), which
VoiceOver reads; on Windows to UI Automation (`WinAccess`: a COM
provider per node, made here: navigation, properties, bounds, the
invoke, toggle, range value and value patterns), which Narrator reads; on
Linux to AT-SPI over D-Bus (`LinuxAccess`, libdbus loaded at run time:
Accessible, Component, Action, Value, Text), which Orca reads. On macOS, Windows
and Linux the tree is built only once a client first asks for it, so a
program nobody reads pays nothing for it.

## Hosts, canvases and documents

A `Ui` is a tree's host: its size and scale (the display's pixels per UI
pixel), its text engine and fonts, the events it is given, the clock,
the focus, the accessibility tree (`ui.accessTree()`: roles, names, states,
a link's `href`, each node's box). A `UiWindow` feeds it a window's
events; without one (`new Ui(engine, width, height)`, `update`, `paint`) it
is a host of a fixed size and no events, first-class: headless tests,
thumbnails, documents ([docs/plans/document.md](../../docs/plans/document.md)).
`ui.paint(canvas)` draws through a `Canvas`: the GPU renderer's, or a
writer's. What a writer gets: rectangles with their borders and corners,
shadows and inset shadows (calls of their own, not pixels), opacity groups,
clips, transforms, images (`Image.source`: the file decoded, to embed as it
is; `Image.drawing`: the SVG an icon was rendered from, to draw as vectors),
vector paths (`canvas.path(path, fill, ?stroke)`: `Path`'s moves, lines,
curves, arcs, even-odd; a `Paint`, a colour or a CSS gradient; a `Stroke`'s
width, caps, joins, miter and dashes), and text as paragraphs whose
`runs(width, align)` give the glyphs as placed: the face's file, the size,
the glyph ids and each glyph's source text. `breakBefore`, `breakAfter`,
`breakInside` and `page` are kept for a paged layout; a window has none.

## Text input

Keys come as `KeyDown` and characters as `TextInput` (Shift, the
keyboard layout, dead keys and compose sequences applied: on X11 through
the input method, `XMODIFIERS`'s or Xlib's own). While a text field has
the focus the window takes text at its caret (`helder.os.Window.startTextInput`):
an input method's composition (Japanese, Chinese, Korean) shows in the
field, underlined, until committed. In the browser keys then go through a
transparent textarea at the caret, which input methods compose in
(`TextEditing` events), on macOS through a text view at the caret
(`NSTextInputClient`: input methods and dead keys); on Windows the IME's
own windows are placed at the caret; X11's input method draws its
composition itself.

## Performance

A frame does the work of what changed and what is seen. `Ui.update` lays
out nothing on a clean tree; after a change it lays out again the dirty
path (a node's measures are cached per constraints) and rounds only the
subtrees that moved. A changed node whose parent's measures of it come out
as they were (a checkbox toggled, a field typed into: its size its own) is
laid out again in place, its ancestors not (`Layout.inPlace`; UiTest checks
it against layouts from scratch of random trees changed at random). Paint and hit tests skip subtrees whose bounds
(their ink: the box, overflowing text, children unless clipped, widened
by shadows and the focus ring) miss the window or their scrollers. The
accessibility tree is built again only when something it reads changed.
The renderer draws a quad as four vertices and six indices, batched by
texture.

Memory per node is kept small: leaves share one empty children array; event
handlers and the rarely set style properties (grid, transforms, shadows,
offsets...) are allocated when first set; paragraphs share their font sets.

`StressTest [rows]` (`npm test -- ui-draw` runs it) prints the times of the
first layout, of the frames after a change, a scroll and an append, and of
a steady frame; `RT_STATS=1` adds the collector's figures and the RSS, and
a build with `-D hxmc.census` run with `RT_CENSUS=1` lists the live heap by
type. At 5000 rows (40000 nodes) a steady frame paints in about 1.5 ms and a
change to one row is laid out in about 3.
The first layout of 1000 rows (8000 nodes) takes about 30 ms, 60% of it
laying out text and nearly half of that the collector copying the
paragraphs' glyphs, which all survive: a compact glyph store in
`helder.text` (arrays, not an object per glyph) is what would cut it next.

## Tests

`npm test -- ui` (Eval: layout against Chromium, events, markup rendered into nodes, the guide),
`npm test -- ui-draw` (natively, golden images), `npm test -- ui-web`
(Chromium, WebGPU and WebGL2, real input events). See `docs/testing.md`.
