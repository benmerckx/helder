# @hxmc/ui

A UI toolkit for hxmc in pure Haxe: a node tree laid out with flexbox,
drawn with the GPU (`@hxmc/gfx`), written in markup (`@hxmc/esx`) with
fine-grained signals, Solid's way.

```haxe
import hxmc.esx.*;
import hxmc.ui.draw.UiWindow;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Reactive.*;
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
list, checkboxes, filters). It runs natively on Linux, macOS and Windows,
and in a browser (wasm32-wasi on WebGPU or WebGL2).

## The parts

- **`hxmc.ui`**, the core, plain Haxe (it runs on any target; its tests
  run on Eval): `Node` and `TextNode`, `Style`, `Layout`, `Ui`.
  - Layout is CSS flexbox, column by default: `direction`, `wrap`,
    `justify`, `alignItems`, `alignSelf`, `alignContent`, `grow`,
    `shrink`, `basis`, `width`, `height`, min and max, `aspectRatio`,
    `padding`, `margin`, `borderWidth`, `rowGap`, `columnGap`, `position`
    (Absolute with `left`, `top`, `right`, `bottom`), `overflow` (Hidden,
    Scroll). Sizes are border boxes. Items get CSS's automatic minimum
    size, so content is not squashed. `display: Grid` lays children out
    on CSS grid tracks instead: `gridTemplateColumns` and
    `gridTemplateRows` (px, %, fr, auto, min-content, max-content,
    minmax(), repeat()), `gridAutoRows`, `gridAutoColumns`,
    `gridAutoFlow`, `gridTemplateAreas` ("'head head' 'side main'"), items
    placed by `gridColumn` and `gridRow` ("1 / 3", "span 2", negative
    lines, an area's name) or `gridArea`, or auto-placed, aligned by
    `justifyItems`, `justifySelf`, `alignItems`, `alignSelf`, the tracks
    by `justify` and `alignContent` (no other named lines, no subgrid,
    no dense packing). Checked against Chromium on 89 cases, 29 of them
    grids.
  - Text properties inherit: `color`, `fontFamily`, `fontSize`,
    `fontWeight`, `italic`, `lineHeight`, `textAlign`. `textDecoration`
    (underline, line-through, overline) draws its lines with the text inside
    the node, in its colour, where Chromium draws them. `maxLines` cuts a
    text to so many lines, the last ending in an ellipsis where Chromium's
    line-clamp puts it.
  - Paint: `background`, `borderColor`, `radius`, `opacity`, `shadow`
    (`"0 2 8 #00000040"`: x, y, blur, spread, colour), `cursor`. Colours are
    CSS's (`Color.parse`: hex, `rgb()`, `hsl()`, the 148 names, as Chromium
    computes them); `backgroundImage` (markup: `background="linear-gradient(...)"`)
    is a CSS gradient, linear or radial, repeating or not (`Gradient`: within
    two levels of Chromium's pixels on 19 cases), under the border.
  - Images: `Image` (RGBA8 pixels; `Image.decode` reads PNG files of every
    colour type, depth and interlacing, JPEG files, baseline or
    progressive, decoded as browsers do, the EXIF orientation applied, and
    GIF files' first frame; `AnimatedImage` plays a GIF's frames, each
    composed as Chromium composes it, on the clock), shown by an `ImageNode` at its own
    size or the style's (keeping its aspect ratio), fitted as `Fill`,
    `Contain`, `Cover` or `None`, its corners rounded with the node's.
  - SVG: `Svg.parse` reads the static subset icon sets use (shapes, all of
    path data, fills and strokes with their joins, caps and dashes, linear
    and radial gradients, opacities, transforms, use and symbol, clip-path,
    nested viewports, CSS colours, currentColor); `render` draws it at any
    size, checked against Chromium's pixels on 30 cases. An `ImageNode`'s
    `svg` (markup: `src={svg}`) is drawn at the window's pixel size in the
    node's colour. Not drawn: text, images, patterns, masks, filters, markers.
  - `Ui` dispatches pointer, wheel, key and text events to nodes (bubbling
    to ancestors), tracks hover and press, moves the focus (click, Tab,
    Shift+Tab; a ring shows when the keyboard moved it) and scrolls
    `Overflow Scroll` nodes (the wheel or a trackpad, by the pixels it
    moved, Shift turning a wheel sideways; in a browser a finger's drag,
    gliding on when let go moving, a tap a click; or their scrollbars'
    thumbs).
- **`hxmc.ui.draw`**: the GPU renderer. One shader draws rounded rectangles
  with borders, soft shadows and glyphs from an atlas, every fragment
  clipped by a rounded rectangle (one draw call a frame); `UiWindow` puts a
  `Ui` in an `hxmc.os` window, shows the hovered node's cursor and runs
  the loop. On macOS the app has the usual menu bar (Hide, Quit, the Window
  menu); Quit asks each window to close, as its close button does.
- **`hxmc.ui.reactive`**: `signal`, `memo`, `effect`, `batch`, `untrack`,
  `root`, `onCleanup`, `onMount`, contexts (`context`, `provide`, `use`,
  the `Provider` component), and `Render`, which mounts markup into nodes
  once and binds every value that is a `Signal`, a `Memo` or a function.
  Control flow components: `For` (keyed: rows are kept and moved), `Index`
  (a row per index, its item a signal), `Show`, `Switch` with `Match`
  (a branch made again only when the branch chosen changes; `null` and
  `false` choose none), `ErrorBoundary` (a fallback, with a reset, for
  errors while rendering its children or later in their computations),
  `VirtualList` (only the rows in view made: a list of 100000 rows scrolls
  as one of 20), `Popover`.
  `Motion`: `transition`, `spring` and `color` are signals moving toward
  a target as the `Clock` ticks (a window ticks it each frame and keeps
  drawing while anything moves; `Clock.finish()` ends every animation, for
  tests); the widgets' colours and the switch's knob use them.
- **`hxmc.ui.widgets`**: `TextField` (caret, selection, keyboard editing),
  `TextArea` (lines: wrapping, Up and Down, scrolling; both on
  `EditableText`, with an input method's composition shown at the caret), and the components `Button`, `Checkbox`, `Toggle` (a switch), `Radio`, `Slider`,
  `Progress`, `Tabs`, `Field`, `Area`, and the popups `Select`, `Menu`,
  `ContextMenu` (at the pointer), `Tooltip`, `Dialog`; `examples/Gallery.hx` shows them all. They draw
  with `Theme.current` (`Theme.LIGHT`, `Theme.DARK`: colours by role);
  `Theme.follow(() -> UiWindow.dark.value)` follows the system's
  appearance (`hxmc.os.App.prefersDark`: the browser's colour scheme,
  macOS's, Windows', GTK's settings).
- **Popups**: `Popup` nodes are layers over the tree (`Ui.open`, `Ui.close`:
  children of `Ui.overlay`, drawn and hit after the tree, not clipped by
  it), anchored to a node (below, above, beside; flipped and kept in the
  window), at a point (a context menu) or modal (a backdrop, the focus kept inside); a press outside or
  Escape asks them to close. In markup, `Flow.Popover` puts its children
  in one while `open` is true.
- **Shortcuts**: `Ui.shortcut("Mod+S", action, ?scope)` (`Shortcut`: Mod is
  Control or Command; labels in each platform's notation), run when the
  focused node does not take the key, scoped to a subtree or to a modal
  popup; `Flow.Hotkey` in markup, and menu items' `shortcut`.

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
  `onTextInput`, `onFocus`, `onBlur` (an `Event -> Void`);
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
`NativeTest` in CI.

## Accessibility

`hxmc.ui.access` builds the tree assistive technology sees (AccessKit's
model: roles, names, states, actions) from the nodes: each node's
`semantics` (in markup: `role`, `label`, `description`, `checked`,
`selected`, `expanded`, `disabled`, `value-now`, `value-min`,
`value-max`, `value-text`), text as labels, focusable nodes as groups; the
widgets declare theirs. `Ui.accessTree()` gives it, `AccessTree.changes`
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

## Tests

`make ui-check` (Eval: layout against Chromium, events, signals, markup),
`make ui-draw-check` (natively, golden images), `make ui-web-check`
(Chromium, WebGPU and WebGL2, real input events). See `docs/testing.md`.
