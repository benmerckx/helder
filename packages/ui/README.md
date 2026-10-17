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
    size, so content is not squashed. Checked against Chromium on 60 cases.
  - Text properties inherit: `color`, `fontFamily`, `fontSize`,
    `fontWeight`, `italic`, `lineHeight`, `textAlign`.
  - Paint: `background`, `borderColor`, `radius`, `opacity`, `shadow`
    (`"0 2 8 #00000040"`: x, y, blur, spread, colour), `cursor`.
  - Images: `Image` (RGBA8 pixels; `Image.decode` reads PNG files of every
    colour type, depth and interlacing), shown by an `ImageNode` at its own
    size or the style's (keeping its aspect ratio), fitted as `Fill`,
    `Contain`, `Cover` or `None`, its corners rounded with the node's.
  - `Ui` dispatches pointer, wheel, key and text events to nodes (bubbling
    to ancestors), tracks hover and press, moves the focus (click, Tab,
    Shift+Tab; a ring shows when the keyboard moved it) and scrolls
    `Overflow Scroll` nodes (the wheel, or their scrollbars' thumbs).
- **`hxmc.ui.draw`**: the GPU renderer. One shader draws rounded rectangles
  with borders, soft shadows and glyphs from an atlas, every fragment
  clipped by a rounded rectangle (one draw call a frame); `UiWindow` puts a
  `Ui` in an `hxmc.os` window, shows the hovered node's cursor and runs
  the loop.
- **`hxmc.ui.reactive`**: `signal`, `memo`, `effect`, `batch`, `untrack`,
  `root`, `onCleanup`, `onMount`, contexts (`context`, `provide`, `use`,
  the `Provider` component), and `Render`, which mounts markup into nodes
  once and binds every value that is a `Signal`, a `Memo` or a function.
  Control flow components: `For` (keyed: rows are kept and moved), `Index`
  (a row per index, its item a signal), `Show`, `Switch` with `Match`
  (a branch made again only when the branch chosen changes; `null` and
  `false` choose none), `ErrorBoundary` (a fallback, with a reset, for
  errors while rendering its children or later in their computations).
  `Motion`: `transition`, `spring` and `color` are signals moving toward
  a target as the `Clock` ticks (a window ticks it each frame and keeps
  drawing while anything moves; `Clock.finish()` ends every animation, for
  tests); the widgets' colours and the switch's knob use them.
- **`hxmc.ui.widgets`**: `TextField` (caret, selection, keyboard editing),
  `TextArea` (lines: wrapping, Up and Down, scrolling; both on
  `EditableText`), and the components `Button`, `Checkbox`, `Toggle` (a switch), `Radio`, `Slider`,
  `Progress`, `Tabs`, `Field`, `Area`; `examples/Gallery.hx` shows them all.

## Markup

Intrinsic elements: `view` (a box), `text` (a run of text), `scroll` (a box
that scrolls), `image` (an `ImageNode`: `src={image}`, `fit="cover"`).
Attributes:

- any Style property, in camelCase or kebab-case, with values as CSS
  writes them: `direction="row"`, `justify="space-between"`,
  `padding="8 12"`, `width="50%"`, `background="#3b82f6"`, `radius={6}`;
  `style={...}` takes a typed `StyleProps` object;
- events: `onClick`, `onPointerDown`, `onPointerUp`, `onPointerMove`,
  `onPointerEnter`, `onPointerLeave`, `onWheel`, `onKeyDown`, `onKeyUp`,
  `onTextInput`, `onFocus`, `onBlur` (an `Event -> Void`);
- `focusable`, `ref={n -> ...}` (the node), `tag="name"` (for `Node.find`).

A value that is a signal, a memo or a function is reactive: the attribute,
text or region follows it. In a `view`, text and text-valued holes next to
each other become one `TextNode`.

## Fonts

Text is shaped and rasterized by `@hxmc/text` with the system's fonts
(`sans-serif` by default). In a browser, give the page's fonts to `run`
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
comctl32 5's classic look until a visual styles manifest) runs `NativeTest`
in CI; AppKit is next.

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
`packages/ui/imports.mjs` with the others. The native adapters (UI
Automation, NSAccessibility, AT-SPI) are not written yet.

## Tests

`make ui-check` (Eval: layout against Chromium, events, signals, markup),
`make ui-draw-check` (natively, golden images), `make ui-web-check`
(Chromium, WebGPU and WebGL2, real input events). See `docs/testing.md`.
