# @hxmc/ui

A UI toolkit for hxmc in pure Haxe: a node tree laid out with flexbox,
drawn with the GPU (`@hxmc/gfx`), written in markup with fine-grained
signals, Solid's way (`@hxmc/view`, which renders into its nodes).

```haxe
import hxmc.ui.draw.UiWindow;
import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.ui.widgets.Widgets.*;

class Counter implements Markup {
	static function main() {
		var count = signal(0);
		var w = new UiWindow("Counter", 320, 200);
		Render.render(<view grow={1} padding={24} row-gap={12} align-items="center" justify="center">
			<text font-size={32}>{count}</text>
			<Button label="+1" primary onClick={() -> count.value++}/>
		</view>, w.root);
		UiWindow.run();
	}
}
```

```hxml
-lib hxmc.ui
-main Counter
--custom-target hxmc=counter
-D hxmc.libc=glibc   # Linux: the GPU drivers are glibc libraries
```

[GUIDE.md](GUIDE.md) walks through building an app: components, state,
lists, popups, your own nodes, each platform, tests.
`packages/ui/examples/Todo.hx` is a complete app (a text field, a keyed
list, checkboxes, filters), `examples/Mail.hx` a larger one (a menu bar,
a toolbar, folders in a tree, messages in a sortable table, search,
undo). They run natively on Linux, macOS and Windows, and in a browser
(wasm32-wasi on WebGPU or WebGL2).

## The parts

- **`hxmc.ui`**, the core, plain Haxe (it runs on any target; its tests
  run on Eval): `Node` and `TextNode`, `Style`, `Layout`, `Ui`.
  - Layout is CSS flexbox, column by default: `direction`, `wrap`,
    `justify`, `alignItems`, `alignSelf` (`Baseline`: a row's items on their
    first baselines, a text's first line's, a box without one on its bottom
    edge), `alignContent`, `grow`,
    `shrink`, `basis`, `width`, `height`, min and max, `aspectRatio`,
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
    grows to all of the scroller's content. `display: Grid` lays children out
    on CSS grid tracks instead: `gridTemplateColumns` and
    `gridTemplateRows` (px, %, fr, auto, min-content, max-content,
    minmax(), repeat()), `gridAutoRows`, `gridAutoColumns`,
    `gridAutoFlow`, `gridTemplateAreas` ("'head head' 'side main'"), items
    placed by `gridColumn` and `gridRow` ("1 / 3", "span 2", negative
    lines, an area's name) or `gridArea`, or auto-placed (`gridAutoFlow`:
    by rows or columns, sparse or dense), aligned by `justifyItems`,
    `justifySelf`, `alignItems`, `alignSelf`, the tracks by `justify` and
    `alignContent` (no other named lines, no subgrid). Checked against
    Chromium on 140 cases, 39 of them grids, 8 right to left.
  - Text properties inherit: `color`, `fontFamily`, `fontSize`,
    `fontWeight`, `italic`, `lineHeight`, `letterSpacing`, `wordSpacing`,
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
    the node, in its colour, where Chromium draws them. `maxLines` cuts a
    text to so many lines, the last ending in an ellipsis where Chromium's
    line-clamp puts it.
  - Paint: `background`, `borderColor`, `radius` (`corners`, or markup
    `radius="12 12 0 0"`: each corner's, as CSS's border-radius; `borders`,
    or `border-width="0 0 2 0"`: each side's width, laid out and drawn, the
    inner corners quarter ellipses as Chromium draws them), `opacity`, `shadow`
    (CSS's box-shadow: `"0 2px 8px rgba(0, 0, 0, 0.25)"`, x, y, blur, spread,
    colour; `inset`; several, comma-separated; blurred by a Gaussian as
    Chromium blurs them, within a few levels of its pixels), `cursor`,
    `visibility` (inherited; `Hidden` keeps the node's place but draws,
    hits, focuses and shows it to assistive technology no more, while a
    `Visible` descendant still is), `pointerEvents` (inherited; `None` lets
    the pointer through to what is under it, an `Auto` descendant still
    found). Colours are
    CSS's (`Color.parse`: hex, `rgb()`, `hsl()`, the 148 names, as Chromium
    computes them); `backgroundImage` (markup: `background="linear-gradient(...)"`)
    is a CSS gradient, linear or radial, repeating or not (`Gradient`: within
    two levels of Chromium's pixels on 19 cases), under the border.
  - `position: Sticky` (Style only for now, markup to come with @hxmc/view):
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
  - Images: `Image` (RGBA8 pixels; `Image.decode` reads PNG files of every
    colour type, depth and interlacing, JPEG files, baseline or
    progressive, decoded as browsers do, the EXIF orientation applied,
    GIF files' first frame, and WebP files, lossless or lossy, with alpha
    (pixel-exact with libwebp's decoding), an animation's first frame; `AnimatedImage` plays a GIF's,
    WebP's or animated PNG's frames, each composed as Chromium composes it, on the clock), shown by an `ImageNode` at its own
    size or the style's (keeping its aspect ratio), fitted as `Fill`,
    `Contain`, `Cover` or `None`, its corners rounded with the node's.
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
    `Ui.scrollBy` eases the same way). A widget's key handler calls
    `preventDefault` (or `stop`) on the keys it takes.
- **`hxmc.ui.draw`**: the GPU renderer. One shader draws rounded rectangles
  with borders, soft shadows and glyphs from an atlas, every fragment
  clipped by a rounded rectangle (one draw call a frame); `UiWindow` puts a
  `Ui` in an `hxmc.os` window, shows the hovered node's cursor and runs
  the loop. On macOS the app has the usual menu bar (Hide, Quit, the Window
  menu); Quit asks each window to close, as its close button does.
- **`hxmc.ui.view`**: `@hxmc/view`'s renderer for these nodes
  (`NodeRenderer`; `-lib hxmc.ui` names it with `-D
  hxmc.view.renderer.ui`), the markup's attributes (`StyleAttrs`, generated
  from `Style`'s properties: a property added to `Style` is an
  attribute), and what is ui's own: the control flow components
  `VirtualList` (only the rows in view made: a list of 100000 rows scrolls
  as one of 20), `Popover` and `Hotkey` (`UiFlow`), and `Motion`:
  `transition`, `spring` and `color` are signals moving toward a target
  as the `Clock` ticks (a window ticks it each frame and keeps drawing
  while anything moves; `Clock.finish()` ends every animation, for tests);
  the widgets' colours and the switch's knob use them. Signals (`signal`,
  `memo`, `effect`, `batch`, `untrack`, contexts), `Render` and the
  control flow components `For`, `Index`, `Show`, `Switch`,
  `ErrorBoundary` are `@hxmc/view`'s ([its README](../view/README.md)).
- **`hxmc.ui.widgets`**: `TextField` (caret, selection, keyboard editing,
  `cut`, `copy`, `paste`, `selectAll`; `Field` and `Area` add an edit menu
  on a right click or the menu key),
  `TextArea` (lines: wrapping, Up and Down, scrolling; both on
  `EditableText`, with an input method's composition shown at the caret), and the components `Button`, `Checkbox`, `Toggle` (a switch), `Radio`, `Slider`, `RangeSlider` (two knobs, a
  slider each for the keyboard),
  `Progress` (or indeterminate), `Tabs`, `Field` (or a password), `Area`, `Table` (sortable, resizable columns, virtualised
  rows, selection and keyboard), `Tree` (items opened and closed, by the
  pointer or the arrows, virtualised rows; ARIA's tree, with levels),
  `Split` (two panes, a divider dragged or moved by the arrows), `Calendar`
  (a month's grid of days, moved through by the keys) and `DatePicker` (a
  calendar in a popover; `Days`: dates as day numbers, no time zones),
  `Disclosure` and `Accordion` (sections shown and hidden), `NumberField`
  (typed or stepped, within bounds; a spin button), `Listbox` (one option
  selected or several: Shift and Control with the arrows and clicks,
  Control+A; ARIA's multiselectable), `Toolbar` (its focusable children
  one Tab stop, Left and Right between them), `Sortable` (a list
  reordered by dragging, a line where the item will go, or by Alt+Up and
  Alt+Down), `ColorPicker` (a
  saturation and brightness square, a hue strip and the hex: sliders for
  the keyboard), and the popups `Select`, `Menu`,
  `ContextMenu` (at the pointer), `Menubar` (menus' titles in a row, moved
  through by Left and Right, one open at a time), `Tooltip`, `Dialog`, `Combobox` (a text
  field whose typing filters options under it; the focus stays in the
  field), `Toaster` (`Toasts.show`: messages in a corner for a while, with
  an action); `examples/Gallery.hx` shows them all. They draw
  with `Theme.current` (`Theme.LIGHT`, `Theme.DARK`: colours by role);
  `Theme.follow(() -> UiWindow.dark.value)` follows the system's
  appearance (`hxmc.os.App.prefersDark`: the browser's colour scheme,
  macOS's, Windows', GTK's settings).
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
that scrolls), `image` (an `ImageNode`: `src={image}` or `src={svg}`, `fit="cover"`).
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
- `focusable`, `ref={n -> ...}` (the node), `tag="name"` (for `Node.find`).
- drag and drop: `drag-data={value}` makes a node draggable; `onDragStart`,
  `onDragEnd` (`e.dropped`) on the source, `onDragOver` (`e.preventDefault()`
  accepts), `onDragLeave` and `onDrop` (`e.data`) on targets; Escape cancels.

A value that is a signal, a memo or a function is reactive: the attribute,
text or region follows it. In a `view`, text and text-valued holes next to
each other become one `TextNode`.

## Fonts

Text is shaped and rasterized by `@hxmc/text` with the system's fonts
(`sans-serif` by default). Colour emoji come from the system's emoji font,
drawn from its bitmaps (scaled down as a browser does) or colour layers. In a browser, give the page's fonts to `run`
(`fonts: [...]` with `packages/text/imports.mjs`).

## Native controls

`hxmc.ui.native` puts the platform's own controls in the same node tree:
a `NativeHost` window whose `Control` nodes (button, checkbox, text field,
slider, progress bar) are native widgets and whose `TextNode`s are native
labels, measured by the platform, laid out by hxmc.ui's flexbox and placed
absolutely; the markup and signals are the same (`import
hxmc.ui.native.Controls.*`: `Button`, `Checkbox`, `Field`, `Slider`,
`Progress`). The backends: GTK 3 on Linux (glibc mode; tested under Xvfb by
`NativeTest`) and the DOM in a browser (the page's own controls in a
container, `nativeContainer` in run's options, with
`packages/ui/imports.mjs`; tested in Chromium by `native-web.mjs`); the
same `examples/NativeForm.hx` runs on both. Plain nodes only lay out (no
backgrounds), and nothing scrolls yet. Win32 (the standard controls,
comctl32 5's classic look until a visual styles manifest) and AppKit run
`NativeTest` in CI. On Android the controls are `android.widget`'s views
(through JNI; `NativeHost.run` hands the steps to Java's main thread),
checked on an emulator by `AndroidNativeTest` with taps, text typed
through the input method and the accessibility tree.

## Accessibility

`hxmc.ui.access` builds the tree assistive technology sees (AccessKit's
model: roles, names, states, actions) from the nodes: each node's
`semantics` (in markup: `role`, `label`, `description`, `checked`,
`selected`, `expanded`, `disabled`, `value-now`, `value-min`,
`value-max`, `value-text`, `multiselectable`, `live`), text as labels,
focusable nodes as groups; the widgets declare theirs. A live region
(`live="polite"` or `"assertive"`) has its changes announced
(`AccessTree.announcements`: its new text): ARIA's aria-live, AT-SPI's
Announcement, UI Automation's LiveRegionChanged, macOS's announcement
request; the toaster says each toast through one. `Ui.accessTree()` gives it, `AccessTree.changes`
the incremental update, `Ui.accessAction` does what a screen reader asks
(click, focus, increment, decrement, set a value). In a browser the window
mirrors it as ARIA elements inside its canvas (the canvas's fallback
content: in the page's accessibility tree, not drawn): load
`packages/ui/imports.mjs` with the others. On macOS the window gives it to
NSAccessibility (`MacAccess`: an element per node, its role, label, value
and frame; press, increment and decrement come back as actions), which
VoiceOver reads; on Windows to UI Automation (`WinAccess`: a COM
provider per node, made here: navigation, properties, bounds, the
invoke, toggle, range value and value patterns), which Narrator reads; on
Linux to AT-SPI over D-Bus (`LinuxAccess`, libdbus loaded at run time:
Accessible, Component, Action, Value, Text), which Orca reads. On macOS, Windows
and Linux the tree is built only once a client first asks for it, so a
program nobody reads pays nothing for it.

## Text input

Keys come as `KeyDown` and characters as `TextInput` (Shift, the
keyboard layout, dead keys and compose sequences applied: on X11 through
the input method, `XMODIFIERS`'s or Xlib's own). While a text field has
the focus the window takes text at its caret (`hxmc.os.Window.startTextInput`):
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
subtrees that moved. Paint and hit tests skip subtrees whose bounds
(their ink: the box, overflowing text, children unless clipped, widened
by shadows and the focus ring) miss the window or their scrollers. The
accessibility tree is built again only when something it reads changed.
The renderer draws a quad as four vertices and six indices, batched by
texture.

Memory per node is kept small: leaves share one empty children array; event
handlers and the rarely set style properties (grid, transforms, shadows,
offsets...) are allocated when first set; paragraphs share their font sets.

`StressTest [rows]` (`make ui-draw-check` runs it) prints the times of the
first layout, of the frames after a change, a scroll and an append, and of
a steady frame; `RT_STATS=1` adds the collector's figures and the RSS, and
a build with `-D hxmc.census` run with `RT_CENSUS=1` lists the live heap by
type. At 5000 rows (40000 nodes) a steady frame paints in about 1.5 ms and a
change to one row is laid out in about 3.
The first layout of 1000 rows (8000 nodes) takes about 30 ms, 60% of it
laying out text and nearly half of that the collector copying the
paragraphs' glyphs, which all survive: a compact glyph store in
`hxmc.text` (arrays, not an object per glyph) is what would cut it next.

## Tests

`make ui-check` (Eval: layout against Chromium, events, markup rendered into nodes, the guide),
`make ui-draw-check` (natively, golden images), `make ui-web-check`
(Chromium, WebGPU and WebGL2, real input events). See `docs/testing.md`.
