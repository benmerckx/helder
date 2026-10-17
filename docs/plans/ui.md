# hxmc: UI (survey, design, and what is built)

How to build the low level of `@hxmc/ui`, and whether to abstract over the
platforms' native controls or to draw everything with the GPU (the
gpui/Makepad route). A survey of what exists as of October 2026, what is
good enough to use or to copy, then a design. Current state of hxmc is in
[README.md](../../README.md), the graphics plan in [graphics.md](graphics.md)
(`@hxmc/os`, `@hxmc/gfx`, the UI section).

What hxmc brings to the question, since it decides most of it:

- No C of our own. Every library below that is C, C++ or Rust is out as a
  dependency, except system libraries loaded at run time
  (`@:hxmc.lib`, `dlopen`): on Windows comctl32, uxtheme, DirectWrite,
  Direct2D, UIAutomationCore; on macOS AppKit, CoreText, the accessibility
  protocols; on Linux (glibc mode, which any GUI already needs for the GPU
  drivers) GTK 4, Pango, HarfBuzz, FreeType, fontconfig, AT-SPI's D-Bus;
  in the browser the DOM through `imports.mjs`. Those are the "already
  good" APIs: the platforms' own.
- What is already there: windows, events and the loop (`hxmc.os`), a
  portable GPU API with shaders written in Haxe (`hxmc.gfx`), raw
  bindings to Win32, the Objective-C runtime and X11, callbacks from C
  (`@:hxmc.callback`: delegates, window procedures), COM vtables (D3D11).
  Structs by value in C calls work on arm64 only; x86-64 is left, and
  AppKit's geometry (`NSRect` in `setFrame:`, `frame`) needs it.
- Four targets of equal weight: Linux, macOS, Windows and the browser.
  Whatever the design, the browser gets it either as a canvas (drawn) or
  as the DOM (native).

## 1. The three routes

| Route | Who | Gets for free | Pays for |
| --- | --- | --- | --- |
| Native controls behind one API | libui-ng, wxWidgets, .NET MAUI, SWT, React Native | look and feel, text editing semantics, IME, accessibility, scroll physics, menus, dialogs, dark mode, DPI | the lowest common denominator; a per-platform quirk per control; layout and events that behave differently; custom widgets need a drawn escape hatch anyway |
| Drawn by the toolkit on the GPU | gpui (Zed), Makepad, Flutter, Avalonia, Compose Multiplatform, egui, Iced, Slint, Masonry/Xilem, Gio | identical behavior everywhere, the browser included; any widget; headless golden-image tests; one event model | text (shaping, rasterization, hinting), text input and IME, accessibility, scroll and selection behaviors; all of it per platform, and all of it is what stays undone for years (below) |
| A web view | Tauri, Electron | HTML/CSS/JS, accessibility, IME, text | three engines (WebView2, WKWebView, WebKitGTK) drifting apart; a JS runtime; not a Haxe UI |

The third is not for hxmc. The first two are not exclusive: every drawn
toolkit still uses native menus, dialogs, the clipboard and drag and drop;
every native toolkit needs a drawn canvas control. The question is which
is the default for the standard controls, and what the shared low level
is. Evidence from the survey first.

## 2. Native-control abstractions

- **libui-ng** (C, MIT; Win32, Cocoa, GTK 3): the fork of libui, still
  "mid-alpha" after a decade, no release on GitHub, bindings in Go, Ruby,
  Crystal, PHP. Its controls are the common denominator and its layout is
  its own box model: bindings note "precise widget positioning isn't
  possible". The lesson is how small the portable surface stayed, not the
  code. Not usable here anyway (a C library to ship).
- **wxWidgets** (C++): mature; 3.3.3 (July 2026) still adding dark mode
  on Windows, control by control; GTK 3, no GTK 4 port in sight. A C++ API
  needs a C shim, so out; HaxeUI's `hxwidgets` backend reaches it through
  hxcpp.
- **.NET MAUI**: native controls through "handlers" (a cross-platform
  control class, one handler per platform mapping properties and events to
  the native view). No Linux, macOS through Mac Catalyst. The handler
  pattern is the clean form of route 1 and worth copying. Avalonia chose
  drawn (Skia) and documents the cost: "scrolling physics and text input
  behavior require manual implementation"; Uno offers both modes.
- **SWT** (Eclipse): twenty years of native-first, drawing what the
  platform lacks (`StyledText`, `CTabFolder`): the hybrid works, and the
  drawn part grows.
- **React Native (Fabric)**: the toolkit owns the tree and the layout
  (Yoga, flexbox, in C++ on a background thread), the platform owns the
  leaf views, positioned absolutely by the computed layout; a mutation
  list is applied on the UI thread. This is route 1 done right: layout is
  portable because it is ours, controls are native because they are
  leaves.
- **Flutter platform views** (the reverse embedding: a native view inside
  a drawn tree) show the cost of mixing: texture mode loses accessibility,
  hybrid composition merges threads and drops frames, HCPP needs API 34
  and Vulkan. Native-inside-drawn is hard; drawn-inside-native (a GPU
  child surface) is easy and is what the plan already says.

## 3. Drawn toolkits

- **gpui** (Zed; Rust): hybrid immediate/retained, views re-rendered each
  frame into an element tree, Taffy layout, a Tailwind-style style API,
  one quad shader with a glyph atlas; Metal on macOS, wgpu elsewhere
  (moved off blade in 2026). Text is the platform's: CoreText on macOS,
  DirectWrite on Windows, cosmic-text on Linux. Pre-1.0; in February 2026
  Zed paused all GPUI work not needed by Zed, and the community fork
  gpui-ce is thin. Accessibility: AccessKit landed behind
  `ZED_EXPERIMENTAL_A11Y=1` in mid 2026 with much broken; Windows screen
  readers get nothing (issue open since October 2025). Six years in, with
  a funded team, for one application.
- **Makepad** (Rust, MIT): the closest in spirit to hxmc: a Rust-like
  shader DSL compiled to Metal, HLSL, GLSL and WebGL, everything drawn
  through shaders, SDF glyph atlases, HarfBuzz for shaping, a live-editable
  UI DSL (in transition from `live_design!` to a script DSL), platforms
  including wasm, iOS, Android. 1.0 in mid 2025; no tagged releases;
  accessibility and IME undocumented. One team, APIs moving.
- **Linebender** (Rust): parts rather than a toolkit: Vello (GPU 2D:
  compute-shader classic, and sparse strips: CPU tiling with GPU or CPU
  fine rasterization, so it runs without compute shaders or without a
  GPU; 0.0.7 "roughly beta", April 2026), Parley (text layout, emits
  AccessKit text properties, system fonts through CoreText), HarfRust
  (HarfBuzz ported to Rust, tracking HarfBuzz 14.3), skrifa (font
  parsing), Glifo (atlas glyph cache, "first cut"), Masonry (the widget
  tree; IME through ui-events, runs on Vello CPU) and Xilem on top. The
  most modular design and the best reading on what the layers are.
- **Slint**: declarative DSL; renderers Skia, FemtoVG, software; text
  through the OS with Skia, swash with FemtoVG (blurry at small sizes
  until recently); accessibility on by default through AccessKit; "native
  style" only through Qt. GPL or commercial.
- **egui**: immediate mode; AccessKit on by default, IME works (2026
  survey), default font lacks CJK. **Iced**: no screen reader, no IME
  (2025 survey, no newer evidence).
- **Flutter/Impeller**: glyph atlases rebuilt per render pass were its
  main text bottleneck; atlas management is where the effort goes.
- **Compose Multiplatform desktop** (Skia): accessibility full on macOS,
  through Java Access Bridge on Windows, none on Linux. Years in.
- **Gio** (Go, no cgo): the precedent for "own everything, no C": its own
  OpenType shaping and GPU renderer, Android to wasm; accessibility
  "limited". Feasible, and accessibility is what stays undone.
- **Dioxus Blitz**: HTML/CSS without a browser from parts (Stylo, Taffy,
  Parley, Vello, AccessKit, winit); pre-alpha. The parts approach again.

The pattern: the drawn route's pixels are the easy part and were done by
every project in its first year; text input, IME and accessibility are
where each of them still is years later, platform by platform.

## 4. The parts

What a drawn backend (or a GPU view in a native one) needs, and what is
good.

- **Layout**: flexbox is the answer everywhere (Yoga in React Native,
  Taffy in Zed, Bevy, Servo, Slint, Blitz; block and CSS grid in Taffy
  too). Clay (C, one header of ~5k lines, MIT) shows how small a flexbox
  with text wrapping, scrolling and a sorted output command list can be
  with arena memory and no allocation. Port the algorithm (Clay's size as
  the target, Taffy's semantics as the reference); grid later.
- **Text shaping and fonts**: the platforms' shapers, through dlopen:
  CoreText (macOS), DirectWrite (COM, like D3D11), HarfBuzz plus FreeType
  plus fontconfig or Pango (Linux: present wherever GTK is), the canvas or
  DOM in the browser. gpui does exactly this. A Haxe shaper (HarfRust is
  the measure: a multi-year port of HarfBuzz) is not worth it.
- **Glyph rasterization**: the platform's rasterizer into an atlas we
  own (R8 for grayscale, RGBA for color emoji and ClearType), as gpui and
  Impeller do: text then matches the OS's hinting and subpixel rendering,
  which is what users notice. Vector text on the GPU later for zooming
  and transforms: Slug's patent went public domain on 2026-03-17 with
  MIT reference shaders (quadratic outlines, winding number in the
  fragment shader); Vello's sparse strips are the CPU-tiled alternative.
  Both are shader work the Haxe shader macro is made for.
- **2D drawing**: one batched quad shader (rect, rounded rect with border
  and shadow, image, glyph; scissor clipping) is what gpui and Makepad
  run on and covers a widget set; paths (Vello-style) are a second step.
- **Accessibility**: AccessKit is the only cross-platform abstraction and
  its design is the one to copy: a tree schema derived from Chromium's
  (node id, role, properties, actions), a full push then incremental
  updates, adapters to UI Automation (COM, doable), NSAccessibility
  (Objective-C, doable), AT-SPI (D-Bus; a client is the heavy part). It
  is Rust with a C API, so for hxmc it is a design to port, not a
  library. Native controls get all of it free.
- **Text input and IME**: `NSTextInputClient`, TSF or `WM_IME_*`, GTK's
  input methods or Wayland `text-input-v3`, the browser's composition
  events. Masonry's ui-events is a platform-neutral event vocabulary
  including IME worth copying for `hxmc.os.Event`. Native text fields get
  it free.

## 5. Assessment

Neither gpui nor Makepad is adoptable (Rust; gpui is paused for outside
use; neither has accessibility to speak of), but their architectures are:
hxmc already has the shader macro, the GPU layer, the windows and the raw
platform bindings, which is most of a Makepad. What it does not have is
the years the drawn toolkits spent on text, IME and accessibility, and
the survey says that is the bulk of the work, and that it is per
platform.

Native controls hand those over to the platform. Through dlopen the
platforms' toolkits are available without a line of C, and on Linux GTK
4 brings text, input methods and AT-SPI with it. Their cost is a small
portable surface (libui), per-control quirks, and a drawn escape hatch
being needed from day one for anything that is not a standard control.

Both routes need the same core: a widget tree we own, a layout we own
(React Native's lesson: native leaves, portable layout), a style model,
focus and event routing, an accessibility tree, a text API. So the design
is one core and two backends, built in the order that gets to usable
applications first.

## 6. Design

```
hxmc.ui          tree, layout (flexbox), style, focus, events, a11y tree, text API
   |                        |
hxmc.ui.native   per control: Win32/comctl32, AppKit, GTK 4, DOM     (first)
hxmc.ui.draw     on hxmc.gfx: quads, atlas text, scissor; any widget (second)
hxmc.text        fonts, shaping, glyph raster: CoreText, DirectWrite, HarfBuzz+FreeType, canvas
hxmc.os          windows, events (+ child Surface, IME, clipboard, cursors, menus, dialogs)
hxmc.gfx
```

- **`hxmc.ui` core**: a retained tree of `View`s with properties; layout
  by our flexbox over measured intrinsic sizes (native controls report
  theirs: `Button_GetIdealSize`, `intrinsicContentSize`/`fittingSize`,
  `gtk_widget_measure`, `getBoundingClientRect`); positions applied to
  leaves absolutely (`SetWindowPos`, `setFrame:` on a flipped container
  view, a `GtkFixed` or a custom `GtkLayoutManager`, `position:absolute`).
  A `Backend` interface per control kind, MAUI-handler style: create,
  set properties, bounds, events in. An accessibility tree in AccessKit's
  schema, filled by the native backend from the controls and by the drawn
  backend by widgets. Headless: the tree, layout and the drawn backend run
  without a window, checked by golden images as gfx is.
- **`hxmc.os` additions** (both backends need them): child surfaces (a
  GPU view inside a native layout, the easy direction), text events as
  characters and composition (IME) beside keysyms, clipboard, cursors,
  DPI changes, native menus and file dialogs (always native, even in
  drawn toolkits). The loop stays ours: GTK 4 runs under
  `g_main_context_iteration(NULL, FALSE)` from `App.turn`, as Cocoa and
  Win32 do now.
- **`hxmc.ui.native` first**: the standard controls (button, label, text
  field and area, checkbox, radio, combo, list and table, slider,
  progress, scroll, tabs, split, menus, dialogs) on comctl32 (with
  uxtheme dark mode and `WM_DPICHANGED`, which Win32 does not do by
  itself), AppKit (`class_addMethod` delegates as `CocoaWindow` does;
  needs x86-64 structs by value for `NSRect`), GTK 4 (glibc mode;
  `g_signal_connect_data` with `@:hxmc.callback`; `g_object_set_property`
  instead of the varargs `g_object_set`), the DOM in the browser. It
  ships text editing, IME, accessibility, dark mode and the look by
  delegation, and is the backend for tools and settings-style UIs.
- **`hxmc.text`**: needed by the drawn backend and by any GPU view
  drawing text in a native UI, so it is the first shared investment after
  the core: font enumeration and fallback, shaping to glyph runs, glyph
  rasterization into an atlas, line breaking; the platform's engines
  behind one API, the canvas in the browser.
- **`hxmc.ui.draw` second**: the same tree and layout on gfx, starting as
  the escape hatch inside the native backend (editors, canvases, charts,
  custom controls in a child Surface) and growing into a full backend for
  applications that want one look everywhere or run on the browser
  canvas. One quad shader, atlas text from `hxmc.text`, scissor clipping;
  its text fields implement IME through the os events, its widgets fill
  the accessibility tree, and the platform adapters (UIA, NSAccessibility,
  AT-SPI) are built then, in that order of difficulty.
- **Not planned**: native controls overlaid on a drawn surface beyond a
  single text field (Flutter's platform-view costs); a Haxe HarfBuzz; a
  web view backend.

Order of work and the open hxmc items it depends on: x86-64 structs by
value (AppKit geometry); GTK 4 and Pango bindings in glibc mode; a child
`Surface` on each platform; the DOM side of `imports.mjs` for controls.
The first milestone mirrors gfx's: one form (label, text field, button,
list) on all four backends, laid out by our flexbox, with a GPU child
view in it, checked headless where the backend allows.

## 7. Built

Since the design above (October 2026), in this order:

- `@hxmc/gfx` gained what a drawn UI needs: buffer writes, R8 and RGBA8
  textures (`Texture2D` parameters in shaders), blending and scissor, on
  all five back ends ([graphics.md](graphics.md)).
- `@hxmc/ui`'s core (`hxmc.ui`): `Node`, `TextNode`, `Style` (setters
  mark layout or paint), `Layout` (flexbox after CSS section 9, checked
  against Chromium's on 60 cases; CSS grid came later, 26 more), `Ui` (hit testing, hover, press and
  click, bubbling, focus and Tab, wheel scrolling), `Canvas` and
  `TextEngine` interfaces. It runs on Eval: its tests need no GPU.
- `@hxmc/text` (`hxmc.text`): TrueType parsing, a rasterizer after
  font-rs, shaping by cmap and kerning with fallback fonts, line breaking,
  a glyph atlas, the system's fonts on Linux, Windows and macOS, the page's
  fonts in a browser.
- The drawn backend (`hxmc.ui.draw`): one shader for rounded rectangles
  with borders (signed distance) and atlas glyphs, a renderer batching by
  clip, `UiWindow` on an `hxmc.os` window. `hxmc.os` gained modifiers and
  text input events on all four platforms.
- `@hxmc/esx` (`hxmc.esx`): markup literals after WebReflection's ESX
  proposal: one static `Template` per literal (its identity a cache key)
  and its dynamic values; components compile to calls whose props Haxe
  checks. It works on every Haxe target.
- `hxmc.ui.reactive`: signals, memos and effects (Reactively's algorithm,
  an ownership tree) and `Render`, which mounts ESX into nodes once and
  binds what they read, Solid's way; `For`, `Show`; widgets (`TextField`,
  `Button`, `Checkbox`). `packages/ui/examples/Todo.hx` is a todo app in
  markup, tested natively and in Chromium (WebGPU and WebGL2) with real
  input events.
- Then the visual details: clipping moved into the shader (each vertex
  carries its clip rectangle and corner radius: rounded clips, and a frame
  is one draw call), box shadows (`Style.shadow`), scrollbar thumbs that
  drag, a focus ring when the keyboard moves the focus, and cursors
  (`hxmc.os.Window.cursor` on X11, Win32, Cocoa and the browser;
  `Style.cursor`).
- Windows sleep while nothing changes (`App.wait`; a frame only when the
  UI asks for one); a stress test of 1000 rows found where layout spent its
  time (text measured twice, a quadratic list reorder), and an hxmc bug
  (closures in structural fields called with another signature's
  arguments), fixed in the compiler.
- More widgets (`Toggle`, `Slider`, `Radio`, `Tabs`, `Progress`) and a
  gallery; images: a PNG decoder, `ImageNode` with CSS's object-fit
  modes, textures freed with `Device.destroyTexture`.
- Solid's remaining pieces (context, onMount, Index, Switch and Match,
  ErrorBoundary) and the clipboard (`hxmc.os.Clipboard`: X11's CLIPBOARD
  selection, Win32, NSPasteboard, the browser's paste event and
  navigator.clipboard; copy, cut and paste in text fields).
- Animation: a `Clock` the window ticks each frame, and `Motion`'s
  transitions, springs and colour transitions as signals.
- `TextArea` (several lines), and accessibility: `hxmc.ui.access`, the
  tree in AccessKit's model built from the nodes' semantics (which the
  widgets declare), incremental updates and actions; the browser's adapter
  mirrors it as ARIA elements inside the canvas (checked against
  Chromium's accessibility tree).
- `hxmc.ui.native`, the native backend begun: `Control` nodes for the
  platform's widgets in the same tree, measured by the platform, laid out
  by our flexbox, placed absolutely (section 6's plan), a `NativeBackend`
  interface and its GTK 3 and DOM implementations (GtkFixed and Pango;
  absolutely placed elements in a container), driven by the same markup
  and signals: one example runs on both; then Win32's common controls
  and AppKit's (`NSButton`, `NSTextField`, `NSSlider`...), each driven by
  the same test through `NativeDriver`.
- Text input: X11's input method (layouts, dead keys, compose sequences),
  and input methods' compositions shown in the text fields, underlined,
  until committed: in the browser through a transparent textarea at the
  caret, on macOS through a text view at the caret (`NSTextInputClient`),
  on Windows with the IME's windows placed at the caret.
- Text and images: CFF outlines (OpenType `.otf`, CID-keyed CJK fonts
  too) and GPOS pair kerning in `@hxmc/text`; a JPEG decoder (baseline
  and progressive, libjpeg's arithmetic: pixel-exact with Chromium's) and
  a GIF decoder (every frame composed as Chromium's ImageDecoder does,
  played by AnimatedImage); a WebP decoder (lossless VP8L, lossy VP8 with
  its ALPH alpha: pixel-exact with libwebp's; animations composed as
  libwebp composes them); APNG's frames.
- Popups (a layer over the tree: anchored, modal), the widgets on them
  (Select, Menu, Tooltip, Dialog), and VirtualList.
- Accessibility on every platform: NSAccessibility (macOS), UI Automation
  (Windows: COM providers made in Haxe), AT-SPI over D-Bus (Linux), each
  checked in CI through the platform's own client side.
- CSS grid layout (tracks with fr, minmax() and repeat(), placement by
  lines and spans, auto-placement), every box as Chromium lays it out.
- Windows given a title, a size and a minimum size on every platform;
  dark mode (the widgets' themes following the system's appearance);
  touch scrolling in the browser.
- Rich text: spans in a paragraph (span, b, i in markup) with their own
  fonts, colours and handlers, line boxes as CSS computes them;
  synthetic italic.
- Right-to-left text: the bidi algorithm (levels, visual order, mirrored
  brackets), Arabic's joining forms and required ligatures from GSUB,
  carets and hits by direction; marks on their bases (GPOS anchors) and
  canonical compositions; CJK and other scripts' fallback faces loaded
  when first needed; colour emoji (CBDT, sbix, COLR), their sequences and
  widths as Chromium's, drawn as Chromium draws Noto Color Emoji.
- Right-to-left layout (`dir`): rows, columns' cross axis, grids'
  columns and absolute boxes mirrored as Chromium mirrors them, text
  aligned to its start, fields aligned and scrollers overflowing to the
  left (scrolled by negative offsets, as Chromium's scrollLeft), arrow
  keys and popups mirrored; `order`, `zIndex`, `visibility`,
  `pointerEvents`, `textWrap`, `textTransform` and `textOverflow`;
  variable fonts (fvar, avar, gvar: SystemFonts' weights as instances).
- More widgets and their keyboards: Menubar (ARIA's menubar), Combobox,
  NumberField, Disclosure and Accordion, Toaster, resizable table columns,
  a mixed checkbox, an indeterminate progress bar, Listbox (multiple
  selection), Toolbar (Role.Toolbar on every adapter), Sortable and ColorPicker; tabs, radio
  groups and toolbars one stop for Tab, moved through by the arrows.
- Images: animated PNGs (APNG) as Chromium composes them, and PNG
  decoding about three times faster (hxmc's haxe.zip.InflateImpl inflating a
  BytesInput whole).
- `@hxmc/view` ([view.md](view.md)) replaced `@hxmc/esx` and
  `hxmc.ui.reactive`: markup compiled to direct calls on a renderer,
  `hxmc.ui.view.NodeRenderer` for both backends; the markup's style
  attributes generated from `Style`'s properties.

Where this departs from section 6:

- **The drawn backend came first**, ahead of native controls: markup with
  a Solid-like framework on drawn components was the goal, and it needs no
  per-platform widget code. The native backend followed on GTK 3, the
  DOM, Win32 and AppKit.
- **Text starts with a built-in rasterizer** rather than the platforms'
  shapers: the same pixels on every machine and target (golden images in
  CI, the browser without font files). Its limits are the shapers' reasons
  to come next: no optional ligatures or Indic shaping (GSUB beyond
  Arabic's forms, the standard ligatures and colour sequences), no
  explicit bidi embeddings, no hinting or subpixel rendering, no variable
  fonts' CFF2. Bidi ordering, Arabic's joining, the ligatures and marks on
  their bases match Chromium's widths and ink on the test strings.
- **Layout uses CSS's automatic minimum size**, not Yoga's 0: items do not
  shrink below their content, so text is not squashed (a container that
  must shrink sets `minHeight: 0`, as in CSS).
- **Not yet**: Windows' compositions drawn in the field (its IME draws
  its own), image formats beyond PNG, JPEG, GIF and WebP (AVIF).

## Sources

Zed's GPUI README and discussions (#6576 accessibility, #30515 extraction,
issue #41138 Windows screen readers, PR #64143 macOS AccessKit adapter);
gpui-ce; the Makepad repository and book; Linebender's monthly updates
(2026 Q1 in particular) and the Vello sparse strips READMEs; the AccessKit
repository; libui-ng; wxWidgets release notes 3.3.0 to 3.3.3; Avalonia,
Uno and MAUI comparisons (2026); React Native's architecture
documentation; Flutter's platform views and Impeller glyph atlas issues;
Slint's renderer documentation and discussions; the 2025 and 2026 surveys
of Rust GUI libraries (egui, Iced); Compose Multiplatform's accessibility
page; Gio's package documentation; Dioxus Blitz; Taffy; Clay;
HarfRust; "The GPU font patent that fed a game studio for a decade" (Slug,
March 2026); Microsoft's Win32 theming guidance.
