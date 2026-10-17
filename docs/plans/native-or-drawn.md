# Native or drawn, per widget

Every widget can be **native** (the platform's control, in the browser a
DOM element), **drawn** (hxmc.ui's renderer) or **auto** (a per-platform
default). The same markup, signals, slots and theme serve both; an app
picks per widget, per subtree or app-wide. Auto picks native where the
platform's control does the job better than we can, drawn where looks and
consistency matter more.

## Defaults for `auto`

| Widget / case | Default | Why |
| --- | --- | --- |
| Input, Textarea, NumberField, password, search | native everywhere | IME, autofill and password managers, spellcheck, text services, selection handles and magnifier on touch, accessibility |
| Select | native on touch platforms (Android, iOS, mobile browsers), drawn on desktop | the system picker on phones; desktop natives look dated next to the theme |
| DatePicker, time | native on touch platforms, drawn on desktop | the system pickers on phones |
| ContextMenu | native on desktop | menus that behave like the system's: keyboard, accessibility, leaving the window |
| Menubar | native on macOS (the global menu), drawn in the window elsewhere | macOS apps are expected to use the system menu bar |
| Scrolling | native in the DOM; drawn elsewhere with the platform's physics | momentum, overscroll and scroll chaining as the platform does them |
| Static text in a browser | DOM | selection, find in page, translation, indexing |
| Video, web content, maps | native (platform views) | not something to draw ourselves |
| Button, Checkbox, Switch, Slider, Tabs, Dialog, Popover, Tooltip, and the rest | drawn | the theme's look; native available on request |

System services stay native and are not widgets: file and colour pickers,
share sheets, printing, alerts on request, the clipboard, drag and drop.

## How

- **A host per node.** `host: Auto | Native | Drawn` on widgets, inherited
  down a subtree; `Ui.policy` holds the defaults above and an app can
  change them.
- **A native control inside a drawn tree** (platform views): the native view
  is placed, sized and clipped by the layout, kept in step during scrolling
  and animation, in the tab order and accessibility tree where the node is.
  The theme draws the chrome (border, background, radius, ring) and a
  borderless native editor sits inside it with the theme's font, colour and
  padding, so a native field looks like the drawn one.
- **Layering.** A native view sits above the drawn surface. Popups and
  dialogs over native views become their own native layers (windows on
  desktop and Android, a layer above the canvas in the browser); where a
  platform cannot, the native view is swapped for a drawn snapshot while
  covered.
- **The browser** gets a DOM renderer for the widget set: a widget is a real
  element with shadcn's markup (`data-slot`, `data-state`, roles), and the
  theme compiles to CSS as well as rules. A web page can then be all DOM
  (small, no wasm needed for UI), all canvas (identical pixels everywhere),
  or mixed per mount point as `@hxmc/view` already allows.
- **Drawn stays the fallback** wherever there is no native counterpart, and
  on request.

## Who builds what

- **The UI session** (`packages/ui`): `host` and `Ui.policy`; platform views
  in a drawn tree on Linux, macOS, Windows and Android (placement, clipping,
  scroll sync, focus, accessibility, layering); native text editors first,
  then Select and DatePicker on Android, ContextMenu and the macOS menu bar.
- **Here**: the browser's DOM renderer for the widgets; the theme's split
  into chrome and editor, and its CSS output; iOS (UIKit) when it starts.

## Order

1. Native text fields by default (desktop, Android, browser).
2. The DOM renderer and CSS theme for the browser.
3. The rest of the defaults table.
