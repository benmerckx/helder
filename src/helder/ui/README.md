# helder.ui

A UI toolkit for hxmc in pure Haxe: a node tree laid out with flexbox,
drawn with the GPU (`helder.gfx`), written in markup with fine-grained
signals, Solid's way (`helder.view`, which renders into its nodes).

```haxe
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.graph.Graph.*;

class Counter implements Markup {
	static function main() {
		var count = signal(0);
		UiWindow.run(<Surface title="Counter" width={320} height={200}>
			<view grow={1} padding={24} row-gap={12} align-items="center" justify="center">
				<text font-size={32}>{count}</text>
				<view:button role="button" focusable padding="8 16" radius={6} background="#18181b" color="#fafafa" cursor="pointer"
					onPress={() -> count(c -> c + 1)}>+1</view:button>
			</view>
		</Surface>);
	}
}
```

```sh
bun run helder dev examples/counter/Counter.hx   # or build; --target web for a page
```

`Render.render(content, node)` mounts markup into a node of your own (a
`UiWindow`'s `root`, a test's `Ui`).

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
  - Images: `helder.image`'s (`Image`, RGBA8 pixels; `Image.decode`: PNG,
    JPEG, GIF and WebP, [its README](../image/README.md); an
    `AnimatedImage` played on the `Clock`), shown by an `ImageNode` at its own
    size or the style's (keeping its aspect ratio), fitted as `Fill`,
    `Contain`, `Cover` or `None`, placed by `position` (CSS's object-position:
    `"right 10px top"`, markup `object-position`; centred by default, the
    part outside cut), its corners rounded with the node's.
  - SVG: `Svg.parse` (helder.canvas's `Svg`) reads the static subset icon sets use (shapes, all of
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
    moved, Shift turning a wheel sideways; a finger's drag (below),
    gliding on when let go moving, a tap a click; their scrollbars'
    thumbs; or the keys a browser scrolls with, when the focus took none of
    them: the arrows by 40 pixels, Page Up, Page Down and Space by seven
    eighths of the view, Home and End, eased over `Ui.scrollDuration`;
    `Ui.scrollBy` eases the same way). A node's key handler calls
    `preventDefault` (or `stop`) on the keys it takes.
  - Fingers and pens are pointers of their own, as the DOM's Pointer
    Events (`UiWindow` feeds helder.os's `Pointers`:
    `Ui.pointerDown(x, y, 1, id, type)` with the slot as the
    id, 0 the mouse): `e.pointerId`, `e.pointerType`, `e.pressure`,
    `e.isPrimary` on their events; each captured by the node it went down
    on (`capture()` in a handler moves it there, `releaseCapture()` lets
    it go: `onLostPointerCapture`); `onPointerCancel` when the system takes
    it, when its node leaves the tree, or when a scroll takes the press;
    a press released within 8 points on its node clicks. The first
    finger's drag scrolls what is under where it started (Wheel events at
    that point, as the wheel's, then a glide when let go moving:
    `helder.os.Glide`), unless a recogniser inside wins it first
    (below). `pointerDown` answers whether the press is the ui's (not the
    root's, the body's, nor a world drawn under the ui: `Node.ownsPointer`,
    a `<Scene>`'s box says no); `UiWindow` marks the pointer `owner = Ui`
    then, so that a game's touch controls leave it alone.
  - Gestures (`helder.ui.gesture`): recognisers on nodes competing for
    each pointer in an arena (Flutter's model): at a press the recognisers
    from the node pressed up to the root join, the innermost first (the
    first finger's scroll last); the first to accept (past its 8-point
    slop, a second finger for a pinch) wins the pointer, the others lose
    it; at the release a `Tap` still in it wins. A recogniser that wins
    other than a `Tap` takes the click (`onClick` is a tap that won, as on
    iOS: a button inside a pannable list). `Tap` (once, `Ended`, at the
    release), `Pan` (`axis` `X` or `Y`: a drag along the other is left to a
    scroller; `minPointers`), `Scale` (pan, pinch and turn at once: `scale`,
    `dscale`, `angle`, `dangle`; `minPointers` 2 for a pinch); a finger put
    down or lifted makes no jump. Their handler gets the recogniser itself,
    reused: `state` (`Possible`, `Began`, `Changed`, `Ended`, `Cancelled`),
    the focus `x`, `y` (node-local), `dx`, `dy` since the last call, `tx`,
    `ty` since it began, `vx`, `vy` (points a second), `pointers`,
    `pointerType`, `button`, `taps`; `cancel()` gives its pointers back.
    The mouse's presses feed the arena too. `Node.addGesture`,
    `removeGesture`, `gesture(Class)`; a recogniser of a node that leaves
    the tree is cancelled.
- **`helder.ui.draw`**: the GPU renderer. One instanced shader (after
  Rune's uber-quad) draws rounded rectangles with borders, soft shadows
  (outer and inset), glyphs from an atlas and images, each an instance of
  one quad, every fragment clipped by a rounded rectangle carried by its
  instance; small images (paths, SVGs, gradients, colour glyphs) share
  atlas pages, so that a frame is one draw call (a texture of its own, a
  large image or a `<Scene>`'s, a draw more where it is bound), its
  instances in a ring of buffers written where they changed; `UiWindow` puts a
  `Ui` in an `helder.os` window, shows the hovered node's cursor and runs
  the loop. In markup the window is `<Surface>` (`UiWindow.Surface`, a
  root): `UiWindow.run(<Surface title="Todo" width={480} height={560}
  theme={sheet}>...</Surface>)` opens it and runs the loop; its props
  (title, size, theme, background, dark) are values or reactive, several
  make several windows; on the web it fills the page, or takes the canvas
  the page gives (a helder.web `<Surface>`'s) at its styles' size. The GPU
  renderer also draws a render target (`gpuTexture`) and records passes
  before the frame's (`beforePass`): a `<Scene>`'s box. On macOS the app has the usual menu bar (Hide, Quit, the Window
  menu); Quit asks each window to close, as its close button does.
- **`helder.ui.view`**: `helder.view`'s renderer for these nodes
  (`NodeRenderer`, named by `Node`'s `@:rendered`; `UiView`, its markup:
  a `<Surface>`'s children, a component returning one pinned to ui), the markup's attributes (`StyleAttrs`, generated
  from `Style`'s properties: a property added to `Style` is an
  attribute), and what is ui's own: the control flow components
  `VirtualList` (a `VirtualScroll`: only the rows in view made, each of
  its own height in a `HeightIndex`; a million rows scroll as twenty, below),
  `Popover` (`UiFlow`), and `Motion`:
  `transition`, `spring` and `color` are signals moving toward a target
  as the `Clock` ticks (a window ticks it each frame and keeps drawing
  while anything moves; `Clock.finish()` ends every animation, for tests). Signals (`signal`,
  `memo`, `effect`, `flush`, `untrack`, contexts: `helder.view.graph`),
  `Render` and the control flow components `For`, `Repeat`, `Show`,
  `Switch`, `Errored`, `Loading` are `helder.view`'s ([its
  README](../view/README.md)). The graph's writes land at the end of each
  event (`Ui`'s pointer, key and text entry points, a native control's
  callbacks) and frame (`Ui.update`, `Clock.tick`, `App.run`'s turns).
- **`helder.ui.motion`**: motion as property tracks, declared on nodes
  (examples/motion, in Haxe and TSX). A `Track` is one value moving: an
  analytic spring by duration and bounce (SwiftUI's
  `Spring(duration:bounce:)`, closed form in each damping regime), a tween
  (a duration on a cubic Bézier) or a decay (a fling's), evaluated at the
  `Clock`'s time (a headless run's virtual one), retargeted from exactly
  where it is and how fast it moves, settled once within its epsilon for
  good; sampling allocates nothing. A node's `Present` keeps a track per
  property that moves, `Motions` changes them:
  - `motion` (Node.motion, markup's `motion="snappy|default|calm"`,
    `motion="0.3 0.15"`, `motion={{duration: 0.3, bounce: 0.2}}`, a
    `MotionSpec`) for a node and its subtree, per property class over it
    (`motion-layout`, `motion-opacity`, `motion-color`,
    `motion-transform`, `motion-radius`, `motion-presence`); the palette's
    tokens (snappy .25/0, default .3/0, calm .4/0, lead .2/0, fade .15,
    bouncy, morph, glide, drift: `Curve.TOKENS`), a theme's own over them
    (`StyleSheet.motion`).
  - Layout: a node laid out elsewhere after it was drawn moves there edge
    by edge in its parent's space, from where its edges are drawn: an edge
    that stays put never moves, children ride their parent's leading
    (top left) edges, or its trailing ones (`ride="trailing"`, `"x"`,
    `"y"`); `lead` and `trail`: the edge in the direction of travel on one
    curve, the other on another, the box stretching as it goes. Drawn
    where the tracks are (the renderer's translation, the presented size;
    text and children keep their layout); `windowBounds`, the inspector
    and `--trace` say where it is drawn. Hit testing stays on the layout.
  - Properties: `opacity`, `radius`, `background`, `borderColor` and
    `color` (premultiplied OKLab; a text colour in half the time, so a
    theme switch keeps its contrast: `textLeads`) spring as they are set;
    the style reads where they are, `style.target(name)` where they go;
    `transform` moves as translation, scale and rotation lanes.
  - Presence: a transition's presence words (`transition="fade"`,
    `"scale"`, `"slide-up"`, `"slide-left(24)"`, `"pop"`, combined: `"fade
    scale"`; with CSS's parts: `"fade, background-color 150ms"`) play as a
    node is inserted into a drawn parent and as it is removed: kept drawn
    where it was, out of the tree and its layout (its old parent's
    `exits`), until its exit settles, revived from where it is if it is
    inserted again; helder.view's keyed `For` keeps such a row and takes
    it back when its key returns (Renders' `leaving`). Nothing enters on
    the first frame. `blur` is a fade (the renderer has no blur).
  - Matched elements (`matched="id"`): one removed and another of that id
    laid out within an update: the new one flies from where the old one
    was seen, its rect, velocity, radius and fill, drawn over everything,
    its content scaled to cover its frame as it goes.
  - `instant` (a node's subtree; `Motions.instant(f)`): its changes without
    motion, its own entrance and exit kept. `Clock.reducedMotion`: travel,
    size, transforms and matched flights snap; opacity, presence and
    colours fade over 0.15 s.
  - A change between frames moves from the next frame on (the Clock may
    have been idle); a layout's within the frame it is laid out.
  1,000 boxes moving at once: a frame's work the same as drawing them still
  (0.82 ms against 0.85 ms median, headless on llvmpipe), retargeting all
  of them 3.7 ms, 152 GC bytes a frame either way (the motion-bench lane).
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
- **`helder.ui.code`**: a code editor. `CodeModel` is its document: a
  rope (`Rope`: chunks of at most 1 KB with their lengths, UTF-8 lengths
  and line breaks; line and offset lookups and UTF-16/UTF-8 mapping by
  binary search), multi-cursor selections, undo grouped by runs of
  typing, highlighting read again from an edited line until a line's
  state is the one it had (`CodeLanguage`; TypeScript, TSX and Haxe are
  `helder.syntax.Lexer`'s, by extension in `CodeLanguages`, more
  registered), and the commands (brackets paired, Enter's indentation,
  words, indent, comments, duplicated and moved lines, cursors above,
  below and at the next occurrence, find and replace). `CodeView` draws
  it virtualised (only the lines in view highlighted, laid out and
  drawn; a line laid out kept until it changes, and shared by content)
  in the bundled JetBrains Mono (OFL, ligatures off unless asked): a
  gutter of line numbers and diagnostics, the current line, selections,
  cursors that blink and spring, indentation guides, whitespace in
  selections, decorations, squiggles with their message on hover; keys
  are `CodeAction`'s through the keymap (context `CodeEditor`), an input
  method composes at the primary caret (its context the caret's line),
  and assistive technology reads a multi-line text input
  (`Node.accessValue`). `CodeEditor` adds find and replace and go to
  line, and the studio's hooks: `revealRange`, `setSelection(s)`,
  `addDecoration`, `setDiagnostics` (helder.compiler.service's),
  `onChange` with each edit's changes (helder.syntax's: a
  `Transaction`'s). examples/code-editor hosts it; tests: `CodeModel.test.hx`,
  `CodeEditor.test.hx`, the headless-run lane (a scripted 2,000-line TSX
  file), the code-bench lane (tests/bench/results/code-editor.md). Not
  yet: soft wrap, folding, completion, bidi text on its column grid.
- **Popups**: `Popup` nodes are layers over the tree (`Ui.open`, `Ui.close`:
  children of `Ui.overlay`, drawn and hit after the tree, not clipped by
  it), anchored to a node (below, above, beside; flipped and kept in the
  window), in a corner of the window (notifications), at a point (a context menu) or modal (a backdrop, the focus kept inside); a press outside or
  Escape asks them to close. In markup, `UiFlow.Popover` puts its children
  in one while `open` is true.
- **Long lists**: `VirtualScroll` (markup's `VirtualList`, `UiFlow`)
  makes only the rows in view and an overscan more, in the flow between
  two spacers; a `HeightIndex` (a sum tree over leaves of 128 rows: 4
  bytes a measured row, under one for the rest) holds every row's height,
  estimated until the row is shown and measured (whole pixels: a row's
  height taken up to the next, so rows above changing move no edge), the
  estimate following the measured mean. Each layout ends with the rows
  shown measured and the window moved (`Ui.update` settles its settlers,
  laid out again while one changes), so no frame shows a gap. The scroll
  is anchored to the row at its top: measures, the estimate, rows put in
  or taken out above it (`splice`; VirtualList diffs its list by key into
  them) move nothing in view. Rows leaving the window are hidden and kept
  by key (`keep`, the farthest let go), coming back made already;
  `scrollToIndex` and `focusIndex` reach rows not made, the arrows, Page
  Up and Down, Home and End move the focus (and `selected`, a key that
  outlives its row's node) onto them; a listbox to assistive technology,
  each made row's place among all (`Semantics.posInSet`, `setSize`).
  examples/million and ts-million (a million messages); tests: MarkupTest,
  `HeightIndex.test.hx`, the headless-run lane, the million-bench lane
  (tests/bench/results/million.md). Not yet: sticky headers across rows
  (a header sticks within its own row), horizontal lists, the code
  editor's lines on the index (fixed height: a multiplication is all it needs).
- **Shortcuts**: the keymap's bindings to actions (below), run when the
  focused node does not take the key; menu items show them.

## Actions and keymaps

`helder.ui.actions`, modelled on Zed's GPUI. An action is a value of an
enum an app or a library declares (`enum ViewerAction { Next; ZoomTo(percent:Float); }`),
its namespace given by a definition (src/helder/compiler/DESIGN.md 4):
`actions("viewer", ViewerAction)`, `viewer::ZoomTo` in a keymap. Its
handler (`ActionsDefinition`, TypeScript's the same) checks it when the
program is built: the namespace an identifier, a string literal, declared
once in the program; every argument one a JSON keymap can give (numbers,
strings, booleans, and arrays and structures of these). It generates the
actions' names and their arguments' readers and comparisons (an
`ActionSpace`, registered where the call is evaluated), so nothing is
looked up by reflection at run time (`-dce full` keeps it working).
`StandardAction` is declared as `standard` (`standard::Quit`).
`Ui.dispatchAction(a)` sends it from the focused node up its
ancestors (a popup's: on to the node it is anchored to, else where the
focus was when it opened) to the root, then to the window's handlers
(`Ui.on`), then the app's (`Actions.on`): each handler (`Node.on(ViewerAction,
a -> ..., ?state)`) takes it (true) or lets it bubble (false); its state
(`Enabled`, `Disabled`, `Checked`, `Unchecked`, `Unhandled`) is what a
menu shows. `StandardAction` is every app's (Quit, CloseWindow,
ToggleFullscreen: the window's; Copy: the selection's; About, Undo, Cut,
Paste...: the menus' roles).

In TypeScript (`helder/ui/actions`, src/helder/ui/actions/index.ts) the
definition takes an object of methods, their parameters the arguments; a
method with arguments returns them as an object, which is what TypeScript
types the action as (a type has no parameter names), and the bodies never
run. It is plain TypeScript, checked by tsgo as it is written:

```tsx
import { actions, type ActionOf, handle, Keymap } from "helder/ui/actions";

export const Viewer = actions("viewer", {
	next() {},
	zoomTo(percent: number) { return { percent }; },
});
export type ViewerAction = ActionOf<typeof Viewer>;   // {type: "next"} | {type: "zoomTo", percent: number}

Keymap.global.bind("1", Viewer.zoomTo(100), "Viewer");
<view key-context="Viewer" actions={handle(Viewer, a => {
	switch (a.type) {
		case "next": next(); return true;
		case "zoomTo": zoom(a.percent); return true;
	}
}, a => a.type === "next" && last() ? Disabled : Enabled)}>...</view>
```

`Viewer.zoomTo(100)` makes a value, `{type: "zoomTo", percent: 100}`; a
handler is a `switch (a.type)`, narrowed by the checker. The same
machinery dispatches it (`on(node, ...)`, `onWindow`, `onApp`, a JSON
keymap's `["viewer::ZoomTo", 100]`, menus' `item(label, action)`,
`resolve`, `popup`, `MenuBar`); `Standard` is StandardAction's
(`Standard.quit()`), its values given to a TypeScript handler as the
program's objects. tests/typescript/definitions/shortcuts.tsx and
Shortcuts.hx print the same; examples/ts-todo binds its filters.

A node's key context (`Node.keyContext`, `KeyContext.parse("Editor mode=full read_only")`)
joins the context stack of the focus (root first). A binding
(`Keymap.bind("secondary-k secondary-s", ZoomIn, "Viewer && !picker")`)
matches by GPUI's predicates: names, `key == value`, `!=`, `!`, `&&`,
`||`, parentheses and `a > b` (b inside a). Keystrokes as GPUI writes
them: `ctrl-shift-s`, `alt-enter`, `f11`, `ctrl--`, `secondary-o`
(Command on macOS, Control elsewhere); several separated by spaces are a
chord, which waits `Keymap.timeout` (1 s) for its next keystroke
(`Ui.pendingKeys`), then runs what its keys alone are bound to. Of the
bindings that match, the one whose context holds deepest wins, then the
later; one whose action no handler on the path takes is passed over.
`Keymap.global` is the app's default keymap; `loadUser(path)` adds a JSON
file over it (`[{"context": "Viewer", "bindings": {"secondary-k z": "viewer::ZoomIn", "1": ["viewer::ZoomTo", 100], "f11": null}}]`:
null unbinds), read again when it changes (a window polls it each
second; a bad file keeps the last good bindings, `error` says why).
`keysFor(action, ?stack)` and `label(action)` (`"Ctrl+O"`, `"⌘K ⌘S"`)
are what a menu or a tooltip shows. Keys a typing field takes (no
Control, Alt or Command) stay its own; the keymap runs after the focus's
`onKeyDown` handlers.

Focus: `FocusHandle` (made before its node, tied by `track-focus`):
`focus()`, `blur()`, `isFocused()`, `containsFocus()` and the signals
`focused` and `within`; `Node.focusWithin()`; `Node.tabIndex` orders Tab
and Shift+Tab as the DOM's tabindex does (above 0 first, below 0 left
out). A popup gives the focus back to where it was when it closes. In
markup:

```haxe
<view key-context="Viewer" actions={[Actions.handle(ViewerAction, a -> switch a {
	case ZoomIn: camera.zoomIn(); true;
	case _: false;
}, a -> a == ZoomIn && camera.canZoom() ? Enabled : Disabled)]}>
	<view track-focus={handle} tab-index={1}/>
</view>
```

## Menus

`helder.ui.menu`: one model for the menu bar and context menus. A
`MenuItem` is `Item(label, action)`, `Separator`, `Submenu(label, items)`
or `Role(role)` (About, Quit, Hide, Undo, Redo, Cut, Copy, Paste,
SelectAll, Minimize, Zoom, Fullscreen, CloseWindow: `StandardAction`'s);
a `Menu` is a title and its items (`role: Window`: the window menu).
`Menus.resolve` turns it into the platform's items: each action's
shortcut from the keymap (the first binding where the context stack of
the node it is for holds), enabled and checked from its handler's state.
`Menus.popup(ui, items, x, y, ?from)` shows a context menu, its choice
dispatched from `from`; `MenuBar` (markup's `<MenuBarView menus={...}/>`)
the window's bar, set again when a label or a state changes (checked
before each update, `Ui.beforeUpdate`). Where `Ui.hostOf` says native
(`"context-menu"`, `"menubar"`) and the window has them: macOS's NSMenu
(the bar's menus after the application's, About moved to the top of the
application's menu, Quit and Hide left to its own, a window menu's items
in Window; an editing role's `copy:`, `paste:`... sent to a native text
editor first; context menus by popUpMenuPositioningItem), Windows' HMENU
(SetMenu; the accelerator after a tab, `Open…\tCtrl+O`; TrackPopupMenuEx).
Elsewhere (Linux) helder draws them (`DrawnMenu`, GTK's look loosely, in
the window's light or dark colours): a bar of titles (F10 opens the
first; Left and Right move along it; a hover moves while one is open) and
popups with check marks, shortcuts at the right and submenus; Up, Down,
Home, End, a letter, Right and Left into and out of submenus, Enter or
Space chooses, Escape closes the innermost, a press outside all; the
focus given back when they close. `tests/os/MenuTest.hx` reads each
platform's back (the window lane); `src/helder/ui/menu/Menus.test.hx` the
model and the drawn menus.

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
  `onPointerEnter`, `onPointerLeave`, `onPointerCancel`,
  `onLostPointerCapture`, `onWheel`, `onKeyDown`, `onKeyUp`,
  `onTextInput`, `onFocus`, `onBlur`, `onFocusIn`, `onFocusOut` (bubbling) (an `Event -> Void`);
  `onPress` (`Node.onActivate`: a click, or Enter or Space unless `onKeyDown`
  took it, as a DOM button's click); the gestures `onTap`, `onPan`
  (`pan-axis="x"`, `pan-min-pointers`), `onPinch`, `onScale` (a
  recogniser made on the node, given to its handler: a `Tap`, a `Pan`, a
  `Scale`). `helder.ui.view.NodeEvents` declares them (NodeRenderer's
  `@:events`, the neutral elements' in every renderer), and markup checks
  each handler against it: a function of its event or of none
  (`onPress={() -> ...}`), an untyped parameter typed as it
  (`onPan={g -> x(g.tx)}`, `onInput={e -> name(e.text)}`); another type, a
  Dynamic value or a name not there is a compile error at the attribute
  (helder.view's README);
- `key-context="Viewer zoomed"` (what the node is to the keymap),
  `actions={[Actions.handle(ViewerAction, a -> ...)]}` (its action
  handlers), `track-focus={handle}` (a `FocusHandle` tied to it),
  `tab-index={1}` (Tab's order): see Actions and keymaps below;
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
`maxlength`, `spellcheck` (the platform's checker on its words: a text
area's by default, a field's asked; misspelled words underlined with a red
wave, their corrections and Add to Dictionary in a right click's menu;
`helder.text.Spell`, off in the deterministic modes), `inputmode` and `autocomplete` (a page's), `onInput` (its
text changed by its user: `e.text`), its own editing after the markup's
`onKeyDown`... unless that prevented the default; a ref of theirs gets an `helder.ui.Part` (Node is one: `focus`,
`rect`, `scrollIntoView`, `contains`, `attr`, `rtl`, `capture`: a press's
moves and release to it (in a handler, that event's pointer: a finger's too); `select`: a field's selection).
- drag and drop: `drag-data={value}` makes a node draggable; `onDragStart`,
  `onDragEnd` (`e.dropped`) on the source, `onDragOver` (`e.preventDefault()`
  accepts), `onDragLeave` and `onDrop` (`e.data`) on targets; Escape cancels.

A phone's safe area (the insets its bars, notch, island, cutout or home
indicator leave clear) is CSS's `env()`: a literal attribute naming
`env(safe-area-inset-top)` (`-right`, `-bottom`, `-left`; a fallback after
a comma for a name it does not know) is bound to the main window's insets
in UI pixels (`SafeArea.insets`, a signal; UiWindow sets it from
`helder.os.Window.safeTop`... over the scale) and set again when they
change (a rotation, the bars hidden): `padding-top="env(safe-area-inset-top)"`,
`padding="calc(env(safe-area-inset-top) + 8px) 16px"`,
`margin-bottom="max(12px, env(safe-area-inset-bottom))"` (`calc()`,
`max()` and `min()` of pixels fold to one length). Each Ui has its own as
`ui.safeArea` (0 on the desktop and the web); a `<Scene>`'s box gives the
part over it (`SceneBox.safeArea()`), for a game's HUD over a scene on the
whole screen.

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
(s.pressed() ? {opacity: 0.8} : {} : StyleProps)}>` (typed: a function
literal markup cannot type is a reactive value; over the theme's rules;
what it stops giving, the theme's again). The system colours `Canvas` and `CanvasText` are a sheet's colours of those
names, else Chromium's, light or dark; a page's slot `"body"` takes them
(a page's background and text colour), and the layers
(popups, dialogs: `ui.overlay`) inherit its text, as a page's popups in
its body do (`ui.body`).

## Fonts

Text is shaped and rasterized by `helder.text` with the system's fonts
(`sans-serif` by default). `HELDER_NO_SYSTEM_FONTS=1` makes
`helder.text.SystemFonts` look for none (only the fonts added: a
program's fallback tested as on a bare system). Colour emoji come from the system's emoji font,
drawn from its bitmaps (scaled down as a browser does) or colour layers. In a browser, give the page's fonts to `run`
(`fonts: [...]` with `src/helder/text/imports.mjs`).

## Platform views

`helder.ui.platform` is a small layer for the platform's own views
embedded in a drawn window, each in a rectangle the layout gives it:
the native menus (a context menu, the menu bar), the platform's text
editors where `Ui.policy` or a node says native (on the desktop helder
draws its own by default), the system's web view (`WebView`, below),
and later other heavy views (video) when an app needs one. A window's `Ui.platform` is its
`PlatformViews` (`MacViews` on macOS, `WinViews` on Windows, `WebViews`
in a browser; none on Linux and Android, where everything is drawn); a
`PlatformEditor` is one text editor, `PlatformMenuItem` a menu's item as
the platform takes it. The AppKit and Win32 calls they make beside
helder.os's are theirs (`AkMsg`, `Win32`).

### The web view

`<webview>` (`helder.ui.platform.WebView`, a node) is the system's web
view placed where it is laid out, over the drawn surface: on iOS and
macOS a WKWebView (`AppleWebView`: a subview of the window's view,
its UiWindow's surface's), on Android an `android.webkit.WebView` (`AndroidWebView`:
a panel window of the activity's, since NativeActivity's own window draws
no views, made and driven on Java's main thread); elsewhere nothing yet
(its box is drawn). `WebShell.run` is an app that is a web view alone, on
the whole screen (iOS: its window's root view; Android: the activity's
content, `org.hxmc.Activity`; the desktop: a window with one WebView):
the thin native shell around a web app (helder studio's web build on a
phone, where only the system's web view runs wasm compiled at run time).

```haxe
var content = WebContent.bundle("web/");          // Asset.bytes("web/index.html") etc.: the bundle's files
<webview src="index.html" content={content} flex-grow={1}
	onMessage={e -> reply(e.text)} onTitle={e -> title(e.text)} onLoadError={e -> trace(e.text)}/>

web.post("hello");                                 // the page's helder.onmessage (e.data)
web.postJson({kind: "open", path: p});
web.postBytes(bytes);                              // an ArrayBuffer there
web.eval("document.title");
web.snapshot(shot -> ...);                         // {width, height, pixels}: RGBA8, straight alpha

WebShell.run({content: content, src: "index.html"}, (shell, e) -> if (e.kind == Message) shell.post("pong"));
```

- **Its own origin**: a `WebContent` serves the bundle's files
  (`bundle(prefix)`: helder.asset's keys, which the program names), a
  directory's (`directory(dir)`) or a function's (`handler(path ->
  WebResponse)`), through the platform's scheme handler: WKURLSchemeHandler
  for `app://localhost/` on Apple's systems, `shouldInterceptRequest` for
  `https://appassets.androidplatform.net/` on Android (as
  WebViewAssetLoader), so the page is a secure context. Every response has
  COOP `same-origin`, COEP `require-corp` and CORP `same-origin` (its
  `headers`: cross-origin isolation, SharedArrayBuffer and wasm threads),
  and a MIME type by extension (`.wasm`: `application/wasm`). `src` may be
  a path of it.
- **The bridge** (`WebBridge`): the page has `window.helder` before its own
  scripts (Apple: a WKUserScript at the document's start; Android: put in
  the HTML its content serves, and evaluated at each other page's start):
  `helder.post(x)` a string, a value as JSON or bytes (an ArrayBuffer or
  typed array, as base64) to `onMessage` (`WebViewEvent`: `text`,
  `isJson`/`json()`, `bytes`), over WKScriptMessageHandler or a
  `@JavascriptInterface` object (`org.hxmc.WebBridge`, on its JavaBridge
  thread); native to the page by evaluating its `helder.__receive`, and
  bytes fetched by the page from its own origin
  (`/__helder/bytes/<id>`: an ArrayBuffer, no base64) where it has one.
  What native code gives the page that a browser cannot (the stores' APIs
  without a CORS relay, the keychain, files, the share sheet) goes through it.
- **Its life**: `onNavigate`, `onUrlChange`, `onLoad`, `onTitle`,
  `onProgress`, `onLoadError`, `onConsole` (Android's console; Apple's
  console.* through the bridge), `onCrash` (the content process gone);
  `url`, `title`, `progress`, `loading`; `goBack`, `goForward`, `reload`,
  `stop`. The back gesture (iOS's edge swipe, Android's Back key) goes
  back in its history (`backGesture`); the keyboard and the page's safe
  area (`env(safe-area-inset-*)`) are the system's; pinch zoom off unless
  `zoom`; `transparent`; the inspector (`isInspectable`,
  `setWebContentsDebuggingEnabled`) in debug builds or with `inspectable`.
- **A still** (`snapshot`): WKWebView's takeSnapshot (a block made by
  hand: a global one, its invoke a callback), Android's View.draw into a
  bitmap; RGBA8, for helder to composite a frame of it.

Tests: CI's simulator and emulator (`tests/platform/webview-ios.sh`,
`webview-android.sh`: `tests/platform/WebViewCheck.hx` in a drawn window
and `WebShellCheck.hx` on the whole screen; a bundled page that reports
`crossOriginIsolated`, instantiates a wasm module streamed as
`application/wasm` and posts the result, native's string and bytes
answered by the page and checked, a snapshot, then examples/todo's web
build run in the same web view). Not yet: Windows' WebView2 and Linux's
WebKitGTK (nothing is drawn there), the web view in a browser (an
iframe), ArrayBuffers from the page without base64.

### Native or drawn, per widget

In a drawn window a widget can also be the platform's own control:
`host` on a node (`Auto`, `Native`,
`Drawn`; markup's `host="native"`) holds for its subtree, and where the
tree leaves it `Auto` the window's `Ui.policy` decides per kind of widget
(`"text-field"`, `"text-area"`, `"context-menu"` and `"menubar"`;
`Ui.defaultPolicy()`: on the desktop, Windows, macOS and Linux, text
fields and areas drawn, as Zed's GPUI draws its editor: helder's own
composes with popups, scrolling and clipping and keeps screenshots the
same, and the platform still gives input methods (TSF, NSTextInputClient,
XIM, text-input-v3), spellcheck (`helder.text.Spell`) and accessibility
(the access tree); in a browser and on phones the platform's editor; the
menus native everywhere). Native
needs the window's `Ui.platform` (`helder.ui.platform.PlatformViews`); without one, or for a
kind it lacks, the widget is drawn. `host="native"` on a field, or
`ui.policy["text-field"] = Native`, asks for the platform's editor on the
desktop too: the
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
program's own (`helder.ui.menu` is the model over them, Menus below): `PlatformViews.menu` shows a context menu (its items,
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
(click, focus, increment, decrement, set a value: a text's, or a range's,
stepped there; expand, collapse, select an item, scroll into view, set a
text input's selection). The tree counts what assistive technology
announces as "2 of 3": an item's place in its set (a list's items, tabs,
radios, menu items, a tree's items of a level), a table's rows and
columns and each cell's row and column; a text input's node has its
caret, its selection and whether it is read only. In a browser the window
mirrors it as ARIA elements inside its canvas (the canvas's fallback
content: in the page's accessibility tree, not drawn; a set's place,
a table's rows and columns and a cell's, read-only as ARIA's attributes):
load `src/helder/ui/imports.mjs` with the others (a page without helder.ui
loads none of it; the ui-web lane reads the fixture's mirror through
Chromium's own tree, `tests/ui/web-access.mjs`). On macOS the window gives it to
NSAccessibility (`MacAccess`: an element per node, its role, label, value
and frame; a text input's characters, selection and lines; a table's
rows, columns and headers, a row's and an item's index; press,
increment and decrement come back as actions, as do a value, the focus,
expanded and selected set; the notifications of what changed), which
VoiceOver reads (the window lane on macOS: `MacAccessTest`,
`MacPatternsTest`, in process); on iOS to UIAccessibility (`IosAccess`:
the window's view a container of a UIAccessibilityElement per node
VoiceOver stops at, its label, value, hint, traits and frame; activate,
increment and decrement come back as actions; layout changes and
announcements posted; `tests/ui/IosAccessCheck.hx` on CI's simulator); on Android to an
AccessibilityNodeProvider on NativeActivity's content view
(`AndroidAccess`, its Java classes.dex's `org.hxmc.AccessProvider` and
`AccessDelegate`, natives: a virtual view per node, its class, text,
bounds, states, range, collection and item info and actions, the
accessibility focus its own, TalkBack's order the tree's; the content
changed, the focus and announcements sent; `tests/ui/AndroidAccessCheck.hx`
read by `uiautomator dump` on CI's emulator); on Windows to UI Automation (`WinAccess`: a COM
provider per node, made here: navigation, properties (an item's place in
its set, a heading's level, off screen), bounds, the Invoke, Toggle,
RangeValue, Value, ExpandCollapse, SelectionItem, Selection, ScrollItem,
Grid, GridItem, Table, TableItem and Text patterns, a text's ranges by
characters, words, lines and the whole (`TextUnits`); the focus,
structure, property, selection, text and live region events of what
changed), which Narrator reads (the window lane: in process,
`WinAccessTest`, `WinPatternsTest`; from another process through
IUIAutomation, `WinAccessProbe`, on the fixture and the screens Linux's
probe reads; under Wine, whose IUIAutomation has no patterns, the tree
and its properties); on
Linux to AT-SPI over D-Bus (`LinuxAccess`, through helder's own D-Bus
client, `helder.os.linux.DBus`: Accessible, Component, Action, Value,
Text by characters, words, sentences and lines with the caret and the
selection, EditableText, Selection, Table and TableCell; the events of
what changed since the last frame: children added and removed, names,
values, states, the text's edits and caret, a selection's change), which
Orca reads (the ui-draw lane reads the fixture, the todo and mail
examples and the guide's widgets through libatspi, the viewer lane the
viewer's main screen: `tests/ui/AtspiProbe.hx`). On macOS, Windows
and Linux the tree is built only once a client first asks for it, so a
program nobody reads pays nothing for it.

## Hosts, canvases and documents

A `Ui` is a tree's host: its size and scale (the display's pixels per UI
pixel), its text engine and fonts, the events it is given, the clock,
the focus, the accessibility tree (`ui.accessTree()`: roles, names, states,
a link's `href`, each node's box). A `UiWindow` feeds it a window's
events; without one (`new Ui(engine, width, height)`, `update`, `paint`) it
is a host of a fixed size and no events, first-class: headless tests,
thumbnails, documents.
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
(`NSTextInputClient`: input methods and dead keys); on Windows through
the Text Services Framework (`helder.os.win32.Tsf`: a text store whose
document is the field's text and selection, `Window.textContext`; the
composition drawn in the field, the candidate window placed below the
caret through `GetTextExt`; where TSF is not there, IMM32's own windows at
the caret); on Wayland through text-input-unstable-v3 (`WaylandTextInput`:
enabled while the field has the focus, its surrounding text, content type
and caret's rectangle sent, the preedit drawn in the field, commits typed,
`delete_surrounding_text` applied); X11's input method draws its
composition itself. An input
method's edit of the text around the caret (TSF's `SetText`, Wayland's
`delete_surrounding_text`) comes as
`TextReplace` (`Node.replaceText`).

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

`StressTest [rows]` (`bun run test ui-draw` runs it) prints the times of the
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

`bun run test ui` (Eval: layout against Chromium, events, markup rendered into nodes, the guide),
`bun run test ui-draw` (natively, golden images), `bun run test ui-web`
(Chromium, WebGPU and WebGL2, real input events), from tests/ui (`bun run test help`: every lane).
The `*.test.hx` beside the sources run natively and as wasm32-wasi (the
test lane): pointers, gestures, and the safe area (`SafeArea.test.hx`:
`env()` resolved, markup's attributes following the insets, laid out
again).
