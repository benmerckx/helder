# Building an app with @hxmc/ui

This guide walks through writing an application with `@hxmc/ui`: markup,
components, state, lists, popups, your own drawn nodes, running it on each
platform and testing it. The [README](README.md) is the reference for every
attribute and widget. The examples here are compiled and run by
`test/GuideTest.hx` (`make ui-check`), so they work as written.

## Setting up

```sh
npm i -D @hxmc/cli @hxmc/ui
```

```hxml
# app.hxml
-lib hxmc.ui
-cp src
-main App
--custom-target hxmc=app
-D hxmc.libc=glibc   # Linux: the GPU drivers are glibc libraries
```

`npx haxe app.hxml` builds `app`, a native executable for this machine.
Markup compiles in a class that `implements hxmc.esx.Markup`. These imports
cover the examples below:

```haxe
import hxmc.esx.*;
import hxmc.ui.*;
import hxmc.ui.draw.UiWindow;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Flow.*;     // For, Index, Show, Switch, Match, Provider, Popover...
import hxmc.ui.reactive.Reactive.*; // signal, memo, effect, batch, context, use...
import hxmc.ui.widgets.Widgets.*;   // Button, Checkbox, Field, Select, Dialog...
```

A window holds a tree of nodes. `Render.render` mounts markup into its
root, and `UiWindow.run` runs the loop until the last window closes:

```haxe
class App implements Markup {
	static function main() {
		var w = new UiWindow("Tickets", 480, 360);
		Render.render(<view grow={1} padding={24} background="#f4f4f5"><Order/></view>, w.root);
		UiWindow.run();
	}
}
```

## Components

A component is a function from a props object to content. Haxe checks the
props at each use: a missing required prop, a wrong type or an unknown name
is a compile error at the attribute. Optional props are `?name`. Nested
content arrives as the `children` prop.

```haxe
static function Stepper(props:{label:String, value:Signal<Int>, ?step:Int}):Esx {
	var step = props.step ?? 1;
	return <view direction="row" align-items="center" column-gap={8}>
		<text grow={1}>{props.label}</text>
		<Button tag="minus" label="-" onClick={() -> props.value.value -= step}/>
		<text min-width={32} text-align="center">{props.value}</text>
		<Button tag="plus" label="+" onClick={() -> props.value.value += step}/>
	</view>;
}

static function Card(props:{title:String, ?children:Any}):Esx
	return <view padding={16} row-gap={8} radius={8} background="#ffffff" shadow="0 1 4 #0000001a">
		<text font-weight={700}>{props.title}</text>
		{props.children}
	</view>;
```

A component runs once, when it is mounted. It is not called again when
state changes, so its local variables live as long as its nodes do. That
makes the body the place for local state:

```haxe
static function Order(props:{}):Esx {
	var adults = signal(2), children = signal(0);
	var total = memo(() -> adults.value * 30 + children.value * 12);
	return <Card title="Tickets">
		<Stepper label="Adults" value={adults}/>
		<Stepper label="Children" value={children} step={1}/>
		<text tag="total">{() -> 'Total: € ${total.value}'}</text>
	</Card>;
}
```

A component without props still takes an empty object (`props:{}`).

## State

State lives in signals. Reading `.value` inside a reactive context tracks
the signal there, and writing `.value` updates exactly what read it:

- **`signal(v)`** holds a value.
- **`memo(() -> ...)`** derives one, cached until what it read changes.
- **`effect(() -> ...)`** runs code now and again after every change to
  what it read.
- **`batch(() -> ...)`** groups writes, so dependents update once.

```haxe
var price = signal(12.5), qty = signal(2);
var total = memo(() -> price.value * qty.value);
effect(() -> trace(total.value)); // 25
batch(() -> {
	price.value = 10;
	qty.value = 3;
}); // 30, once
```

In markup, a hole or attribute whose value is a signal, a memo or a
function is bound: the text, style or region follows it. A plain value is
read once. So pass the signal, or wrap the expression in a function:

```haxe
<text>{count}</text>                         // follows count
<text>{() -> count.value * 2}</text>         // follows count
<text>{count.value}</text>                   // the value at mount time only
<view background={() -> on.value ? "#22c55e" : "#e4e4e7"}/>
```

`untrack(() -> ...)` reads without tracking, and `onCleanup` and `onMount`
run code when the owner goes away or after the nodes are mounted.

## Lists and conditions

`For` keeps one row per item, keyed by the item itself, so rows move
instead of being made again when the array is reordered. `Show` renders its
children while `when` holds, else its `fallback`:

```haxe
static function Names(props:{names:Signal<Array<String>>}):Esx
	return <view row-gap={4}>
		<For each={props.names} render={(name:String) -> <text>{name}</text>}/>
		<Show when={() -> props.names.value.length == 0} fallback={<text tag="count">{() -> props.names.value.length + " names"}</text>}>
			<text tag="empty">No names yet</text>
		</Show>
	</view>;
```

Replace the array to change the list: `names.value = names.value.concat(["Cy"])`.
`Index` is the other way round: one row per position, its item a signal,
for lists of plain values that change in place. `Switch` picks the first
`Match` whose `when` holds:

```haxe
static function Page(props:{tab:Signal<String>}):Esx
	return <Switch fallback={<text>Not found</text>}>
		<Match when={() -> props.tab.value == "home"}><text tag="home">Home</text></Match>
		<Match when={() -> props.tab.value == "settings"}><text tag="settings">Settings</text></Match>
	</Switch>;
```

A long list belongs in a `VirtualList`, which makes only the rows in view.

## Layout and style

Nodes lay out with CSS flexbox, as a column by default. Every Style
property is an attribute, in kebab-case or camelCase, with CSS's values:

```haxe
<view direction="row" justify="space-between" align-items="center" padding="8 12" column-gap={8}
	width="50%" min-height={0} background="#3b82f6" radius={6} border-width={1} border-color="#1d4ed8"/>
```

Colours are CSS's: hex, `rgb()`, `hsl()` and the named ones. A background
can be a CSS gradient, linear or radial, repeating or not, drawn under the
border:

```haxe
<view tag="banner" height={48} radius={8} background="linear-gradient(to right, #6366f1, rgb(236 72 153))"/>
```

A `transform` turns, scales, skews or moves a node and its subtree as it
is drawn and hit, about its centre unless `transform-origin` says
otherwise, without changing the layout around it; animate it like any
other attribute:

```haxe
<view tag="badge" width={24} height={24} radius={12} background="#ef4444" transform="rotate(15deg) scale(1.2)" transform-origin="left top"/>
```

For two-dimensional layouts, `display="grid"` places children on CSS
grid tracks: fixed sizes, percentages, `fr` shares, `auto`,
`min-content`, `max-content`, `minmax()` and `repeat()`, with items
placed by line numbers or spans and the rest auto-placed:

```haxe
static function Dashboard(props:{}):Esx
	return <view display="grid" grid-template-columns="200px 1fr 1fr" grid-auto-rows="80px" column-gap={12} row-gap={12} padding={12}>
		<view tag="nav" grid-row="span 2" background="#e4e4e7"/>
		<view tag="chart" grid-column="span 2" background="#dbeafe"/>
		<view tag="a" background="#fef3c7"/>
		<view tag="b" background="#dcfce7"/>
	</view>;
```

Named areas draw the layout as text, and items go to an area by its name:

```haxe
static function Shell(props:{}):Esx
	return <view display="grid" grid-template-columns="160px 1fr" grid-template-rows="48px 1fr 32px" height="100%"
		grid-template-areas="'head head' 'side main' 'foot foot'">
		<view tag="head" grid-area="head" background="#e4e4e7"/>
		<view tag="side" grid-area="side" background="#f4f4f5"/>
		<view tag="main" grid-area="main"/>
		<view tag="foot" grid-area="foot" background="#e4e4e7"/>
	</view>;
```

Sizes are border boxes, and items do not shrink below their content. A
scrolling area is a `scroll` element, which needs a bounded height, often
`grow={1} min-height={0}` inside a column. Text properties (`color`,
`font-family`, `font-size`, `font-weight`, `italic`, `line-height`,
`letter-spacing`, `word-spacing`, `text-align`) inherit. `Motion.transition`, `Motion.spring` and
`Motion.color` give signals that move toward a target, for animated values:

```haxe
var open = signal(false);
var height = Motion.spring(() -> open.value ? 200 : 0);
<view height={height} overflow="hidden">...</view>
```

## Images and icons

An `image` shows an `Image` (`Image.decode`: PNG, JPEG, GIF), an
`AnimatedImage`, or an `Svg`. An SVG is drawn at the size it is shown,
sharp at any scale, in the node's text colour wherever it says
`currentColor`, so icons follow the theme like text does:

```haxe
static final SEARCH = Svg.parse('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
	stroke-linecap="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>');

static function SearchButton(props:{onClick:Void->Void}):Esx
	return <view tag="search" role="button" label="Search" focusable direction="row" column-gap={6} align-items="center"
		color="#2563eb" onClick={_ -> props.onClick()}>
		<image src={SEARCH} width={16} height={16}/>
		<text>Search</text>
	</view>;
```

## Rich text

Inside a `text`, elements are spans: `span`, `b`, `i`, or `text` again.
Each takes style attributes and handlers, and holes in it stay reactive:

```haxe
static function Greeting(props:{name:Signal<String>, onLink:Void->Void}):Esx
	return <text tag="greeting">Hello <b>{props.name}</b>, read <span tag="link" color="#2563eb" text-decoration="underline" cursor="pointer" onClick={_ -> props.onLink()}>the guide</span>.</text>;
```

The spans wrap as one paragraph. A larger span makes its line taller, as
in CSS, and a click on a span's text goes to that span. `text-decoration`
(`underline`, `line-through`, `overline`) draws its lines where Chromium
draws them, in the colour of the element that asks for them, under the text
inside it. A `selectable` text can be selected with the pointer (a
drag, a double click for a word, a triple click for all of it) and copied
with Control+C or Command+C; `Ui.selectedText()` reads it.

## Context

A context passes a value down the tree without threading it through every
component. `use` reads the nearest `Provider`'s value, else the default:

```haxe
static final Brand = context({accent: "#3b82f6"});

static function Accent(props:{label:String}):Esx {
	var brand = use(Brand);
	return <text color={brand.accent}>{props.label}</text>;
}

<Provider context={Brand} value={{accent: "#e11d48"}}><Accent label="rose"/></Provider>
```

## Themes and dark mode

The widgets draw with `Theme.current`, a signal holding `Theme.LIGHT` or
`Theme.DARK` (or a theme of your own: colours by role). Setting it
recolours every widget, with their usual transition. `UiWindow.dark`
follows the system's appearance, so one line makes an app follow it:

```haxe
Theme.follow(() -> UiWindow.dark.value);
```

Paint your own surfaces with the theme's roles too, read inside a
function so that they follow it:
`<view background={() -> Theme.current.value.background} color={() -> Theme.current.value.text}>`.

## Popups

Popups are layers over the tree, so a parent's clipping does not cut them.
`Select`, `Menu`, `ContextMenu`, `Tooltip` and `Dialog` are built on them, and `Popover`
puts any content in one while `open` is true (its `at` places it at a point). A modal dialog keeps the
focus inside, and Escape or a press outside asks it to close:

```haxe
static function Confirm(props:{onYes:Void->Void}):Esx {
	var open = signal(false);
	return <view>
		<Button tag="delete" label="Delete" onClick={() -> open.value = true}/>
		<Dialog open={open} title="Delete this file?">
			<view direction="row" column-gap={8} justify="end">
				<Button tag="no" label="Cancel" onClick={() -> open.value = false}/>
				<Button tag="yes" label="Delete" primary onClick={() -> {
					open.value = false;
					props.onYes();
				}}/>
			</view>
		</Dialog>
	</view>;
}
```

A `ContextMenu` around some nodes opens its items where they are
right-clicked, or at their corner on the menu key or Shift+F10:

```haxe
<ContextMenu items={[{label: "Copy", onSelect: copy}, {label: "Delete", onSelect: remove}]}>
	<text>Right-click me</text>
</ContextMenu>
```

## Tables

A `Table` shows rows in columns: each column a title, a width (a grid
track), what a row's cell shows and, to make it sortable, a comparison. Only
the rows in view are made, so long tables stay cheap. A click selects a row,
a double click or Enter activates it, the arrow keys move the selection:

```haxe
typedef Person = {name:String, age:Int};

static function People(props:{people:Array<Person>, onOpen:Person->Void}):Esx
	return <Table tag="people" rows={props.people} height={200} label="People" onActivate={props.onOpen} columns={[
		{title: "Name", cell: p -> p.name, compare: (a, b) -> Reflect.compare(a.name, b.name)},
		{title: "Age", width: "60px", cell: p -> "" + p.age, compare: (a, b) -> a.age - b.age}
	]}/>;
```

## Keyboard shortcuts

A `Hotkey` runs its action when its keys are pressed anywhere in the
window, for as long as it is mounted; with `local`, only while the
focus is inside the node it is in. `Mod` is Control, or Command on a
Mac. A key the focused node takes first (a text field's Control+C, a
letter typed into it) is not a shortcut, and under a modal dialog only
the dialog's own shortcuts work. Menu items take a `shortcut` too:
it is shown in the menu, in the platform's notation, and works while
the menu is mounted.

```haxe
static function Editor(props:{text:Signal<String>, onSave:Void->Void}):Esx
	return <view row-gap={8}>
		<Hotkey keys="Mod+S" action={props.onSave}/>
		<Menu label="Edit" items={[{label: "Clear", shortcut: "Mod+Shift+K", onSelect: () -> props.text.value = ""}]}/>
		<Area value={props.text}/>
	</view>;
```

## Drag and drop

A node with `drag-data` can be dragged: a press that moves past 4 pixels
starts a drag carrying that value. Nodes under the pointer hear
`onDragOver` and accept the drop by calling `e.preventDefault()`, as in
HTML; the one that accepted hears `onDragLeave` when the pointer moves
on, and `onDrop` with `e.data` on release. The source hears
`onDragStart` and `onDragEnd` (`e.dropped`), and Escape cancels:

```haxe
static function Sortable(props:{items:Signal<Array<String>>}):Esx {
	var over = signal("");
	function move(what:String, before:String) {
		var list = props.items.value.filter(x -> x != what);
		list.insert(list.indexOf(before), what);
		props.items.value = list;
	}
	return <view row-gap={4}>
		<For each={props.items} render={(name:String) -> <view tag={"item-" + name} drag-data={name} padding={6}
			background={() -> over.value == name ? "#dbeafe" : "#ffffff"}
			onDragOver={e -> {
				e.preventDefault();
				over.value = name;
			}}
			onDragLeave={_ -> over.value = ""}
			onDrop={e -> {
				over.value = "";
				if (e.data != name) move(e.data, name);
			}}>{name}</view>}/>
	</view>;
}
```

`ui.dragging` gives what is dragged and where, to draw it under the pointer.

## Your own nodes

The intrinsic elements cover boxes, text and images. For anything drawn,
subclass `Node`, say that it has content, and paint it with the `Canvas`.
A `Node` is content too, so a component can return one, fed by an effect:

```haxe
class Sparkline extends Node {
	public var values(default, set):Array<Float> = [];

	public function new() {
		super("sparkline");
		style.height = 40;
	}

	function set_values(v:Array<Float>):Array<Float> {
		values = v;
		if (ui != null) ui.requestFrame();
		return v;
	}

	override public function hasContent():Bool
		return true;

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (values.length == 0) return;
		var max = Lambda.fold(values, Math.max, 0.0), w = width / values.length;
		for (i in 0...values.length) {
			var h = values[i] / max * height;
			canvas.rect(x + i * w + 1, y + height - h, w - 2, h, 2, Color.parse("#3b82f6"), 0, 0);
		}
	}
}

static function Spark(props:{values:Signal<Array<Float>>}):Node {
	var n = new Sparkline();
	effect(() -> n.values = props.values.value);
	return n;
}
```

`requestFrame` asks for a repaint. When the node's size depends on its
content, override `measureContent` and call `markDirty` when that changes,
as `TextNode` and `ImageNode` do. Events are the node's `onPointerDown`,
`onKeyDown` and the rest, and `focusable = true` puts it in the Tab order.
To use it as an element instead, register it:
`Render.elements.set("sparkline", () -> new Sparkline())`.

## Accessibility

The widgets describe themselves to screen readers. For your own
components, give nodes a `role` and a `label` (and `checked`, `expanded`,
`value-now` and the rest where they apply), and make interactive ones
`focusable` with keyboard handlers:

```haxe
<view role="button" label="Close" focusable onClick={_ -> close()}
	onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) close()}>...</view>
```

The window passes this tree to VoiceOver (macOS), Narrator (Windows), Orca
(Linux) and, in a browser, to the page's accessibility tree.

## Running it

The same program runs on every platform. `-D hxmc.target` picks the target,
and everything cross-builds from Linux or macOS:

| Target | Options | Notes |
| --- | --- | --- |
| Linux | `-D hxmc.libc=glibc` | X11 and OpenGL; Wayland through XWayland |
| macOS | `-D hxmc.target=macos-arm64` (or `-x86_64`) | Cocoa and Metal; signed ad hoc |
| Windows | `-D hxmc.target=windows-x86_64` (or `-arm64`) | Win32 and Direct3D 11 |
| Browser | `-D hxmc.target=wasm32-wasi` | a canvas, WebGPU or WebGL2 |

In a browser, the page loads the module with the packages' imports and gives
it the fonts it may use, as files or URLs:

```html
<canvas id="c" style="width: 480px; height: 360px"></canvas>
<script type="module">
import { run } from './node_modules/@hxmc/os/browser.mjs';
const p = './node_modules/@hxmc/';
run('app.wasm', {
	imports: [p + 'os/imports.mjs', p + 'gfx/imports.mjs', p + 'text/imports.mjs', p + 'ui/imports.mjs'],
	canvas: 'c',
	fonts: ['DejaVuSans.ttf', 'DejaVuSans-Bold.ttf'],
});
</script>
```

## Testing

The core runs on any Haxe target, Eval included, so most of an app tests
without a window or a GPU. Make a `Ui` with a text engine, mount the
markup, and drive it with the events a window would send. `DrawText` lays
text out with the system's fonts; `test/MonoText.hx` (every character half
the font size wide) gives sizes that do not depend on the machine:

```haxe
var ui = new Ui(new MonoText(), 400, 300);
Render.render(<Order/>, ui.root);
ui.update();
var plus = ui.root.find("plus");
ui.pointerDown(plus.absX + 2, plus.absY + 2, 1);
ui.pointerUp(plus.absX + 2, plus.absY + 2, 1);
ui.update();
var total:TextNode = cast ui.root.find("total"); // "Total: € 90"
```

`tag` names nodes for `find`; popups are under `ui.overlay`. `keyDown`,
`textInput`, `wheel` and `setFocus` do the rest, and `ui.paint(canvas)`
with a recording `Canvas` shows what would be drawn. For pixels, the
renderer draws headless into an image to compare with a golden one:
`test/UiDrawTest.hx` and `test/TodoTest.hx` show how.
