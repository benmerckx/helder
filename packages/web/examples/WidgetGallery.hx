import hxmc.ui.Color;
import hxmc.ui.widgets.Days;
import hxmc.ui.widgets.Toasts;
import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.web.widgets.Widgets.*;

typedef Entry = {name:String, ?children:Array<Entry>, ?size:Int};

// ui's widget gallery (packages/ui/examples/Gallery.hx, drawn on a canvas)
// on the DOM's widgets: the same widgets, props and signals, each a real
// element with shadcn's markup under the theme's CSS; popups in the top
// layer; right to left and dark at a switch (make web-widgets:
// bin/web/widgets/gallery.html; web.mjs drives it)
class WidgetGallery implements Markup {
	static function main()
		Render.render(new WidgetGallery().view(), js.Browser.document.body);

	public final clicks = signal(0);
	public final checked = signal(true);
	public final on = signal(false);
	public final size = signal("Medium");
	public final days = signal(["Tue", "Thu"]);
	public final colour = signal(Color.rgb(0x3B82F6));
	public final volume = signal(0.4);
	public final priceLow = signal(20.0);
	public final priceHigh = signal(80.0);
	public final tab = signal(0);
	public final name = signal("");
	public final notes = signal("");
	public final fruit = signal("Apple");
	public final chosen = signal("nothing chosen");
	public final dialog = signal(false);
	public final pane = signal(200.0);
	public final open:Signal<Array<Entry>> = signal([]);
	public final file:Signal<Null<Entry>> = signal(null);
	public final row:Signal<Null<Entry>> = signal(null);
	public final city = signal("");
	public final rtl = signal(false);
	public final dark = signal(false);
	public final count = signal(3.0);
	public final period = signal("Week");
	public final page = signal(4);
	public final labels = signal(["design", "review"]);
	public final bold = signal(true);
	public final due:Signal<Null<Day>> = signal(null);
	public final faq = signal(0);
	static final TODAY:Day = {year: 2026, month: 10, day: 17};
	static final CITIES = ["Amsterdam", "Antwerp", "Berlin", "Bern", "Brussels", "Lisbon", "London", "Madrid", "Paris", "Prague", "Rome", "Vienna"];
	static final FILES:Array<Entry> = [
		{name: "examples", children: [{name: "Gallery.hx", size: 6}, {name: "Todo.hx", size: 3}]},
		{name: "src", children: [{name: "Node.hx", size: 12}, {name: "Ui.hx", size: 38}, {name: "Style.hx", size: 21}]},
		{name: "README.md", size: 9}
	];
	static final SIZES:Array<Entry> = [for (d in FILES) for (e in d.children ?? [d]) e];
	static final TABS = [
		"An overview of the widgets: each is a function of its props, bound to signals.",
		"Details: the content of a tab is rendered again when the selection changes.",
		"Notes: every widget here takes the keyboard focus and works with the keyboard."
	];

	public function new() {
		var html = js.Browser.document.documentElement;
		effect(() -> html.setAttribute("dir", rtl.value ? "rtl" : "ltr"));
		effect(() -> html.classList.toggle("dark", dark.value));
	}

	function section(title:String, content:View):View
		return <section style="display:flex;flex-direction:column;gap:8px">
			<h2 style="font-size:12px;font-weight:700;opacity:.6">{title}</h2>
			{content}
		</section>;

	function tabContent(i:Int):View
		return <Card><CardContent>{TABS[i]}</CardContent></Card>;

	static inline final ROW = "display:flex;align-items:center;gap:12px;flex-wrap:wrap";

	public function view():View
		return <main style="display:flex;flex-direction:column;gap:18px;padding:20px;max-width:640px;font-size:14px">
			<header style="display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap">
				<div style="display:flex;align-items:center;gap:14px">
					<h1 style="font-size:22px;font-weight:700">Widgets</h1>
					<Menubar tag="app" label="Gallery" menus={[
						{label: "File", items: [{label: "New", shortcut: "Mod+Alt+N", onSelect: () -> Toasts.show("New")}, {label: "Open…", onSelect: () -> Toasts.show("Open")}]},
						{label: "Edit", items: [{label: "Undo", onSelect: () -> Toasts.show("Undone")}, {label: "Redo", onSelect: () -> Toasts.show("Redone")}]},
						{label: "View", items: [{label: "Right to left", checked: rtl}, {label: "Dark", checked: dark}]}
					]}/>
				</div>
				<div style="display:flex;gap:16px"><Switch tag="rtl" checked={rtl} label="Right to left"/><Switch tag="dark" checked={dark} label="Dark"/></div>
			</header>
			{section("BUTTONS IN A TOOLBAR", <div style={ROW}>
				<Toolbar tag="buttons" label="Buttons">
					<Button tag="plain" label="Plain" variant="outline" size="sm" onClick={() -> clicks.value++}/>
					<Button tag="primary" label="Primary" size="sm" onClick={() -> clicks.value += 10}/>
				</Toolbar>
				<span id="clicks" style="opacity:.7">{() -> "clicked " + clicks.value}</span>
			</div>)}
			{section("POPUPS", <div style={ROW}>
				<Select tag="fruit" value={fruit} options={["Apple", "Pear", "Plum"]} label="Fruit"/>
				<DropdownMenu tag="file" label="File" items={[
					{label: "New", onSelect: () -> chosen.value = "New"},
					{label: "Open…", onSelect: () -> chosen.value = "Open"},
					{label: "Rename…", onSelect: () -> dialog.value = true}
				]}/>
				<Tooltip tag="tip" text="A tooltip, after half a second"><Button variant="ghost" label="Hover me"/></Tooltip>
				<span id="chosen" style="opacity:.7">{() -> chosen.value}</span>
				<Dialog open={dialog} title="Rename" description="The name the greeting below uses.">
					<Input tag="rename" value={name} placeholder="A new name"/>
					<DialogFooter><Button tag="done" label="Done" onClick={() -> dialog.value = false}/></DialogFooter>
				</Dialog>
			</div>)}
			{section("TOGGLES", <div style="display:flex;align-items:center;gap:24px;flex-wrap:wrap">
				<Checkbox tag="check" checked={checked} label="Checkbox"/>
				<Switch tag="switch" checked={on} label="Switch"/>
				<span id="toggles" style="opacity:.7">{() -> (checked.value ? "checked" : "unchecked") + ", " + (on.value ? "on" : "off")}</span>
			</div>)}
			{section("RADIO AND LISTBOX", <div style="display:flex;align-items:flex-start;gap:24px;flex-wrap:wrap">
				<RadioGroup tag="size" value={size} options={["Small", "Medium", "Large"]}/>
				<Listbox tag="days" selected={days} options={["Mon", "Tue", "Wed", "Thu", "Fri"]} multiple label="Days" width={110}/>
				<span id="size-shown" style="opacity:.7">{() -> "size: " + size.value + ", " + days.value.join(" ")}</span>
			</div>)}
			{section("SLIDER, PROGRESS AND COLOUR", <div style="display:flex;align-items:flex-start;gap:32px;flex-wrap:wrap">
				<div style="display:flex;flex-direction:column;gap:14px">
					<div style={ROW}><Slider tag="volume" value={volume} step={0.05} width={200} label="Volume"/><span id="volume-shown" style="opacity:.7">{() -> Math.round(volume.value * 100) + "%"}</span></div>
					<Progress value={volume} width={200}/>
					<div style={ROW}><RangeSlider tag="price" low={priceLow} high={priceHigh} min={0} max={100} step={5} width={200} label="Price"/><span id="price-shown" style="opacity:.7">{() -> priceLow.value + "–" + priceHigh.value}</span></div>
				</div>
				<ColorPicker tag="colour" value={colour} size={130} label="Accent"/>
			</div>)}
			{section("TABS", <Tabs tag="tab" labels={["Overview", "Details", "Notes"]} selected={tab} render={tabContent}/>)}
			{section("SEGMENTS, BREADCRUMBS, PAGES", <div style="display:flex;flex-direction:column;align-items:flex-start;gap:10px">
				<ToggleGroup tag="period" label="Period" value={period} options={["Day", "Week", "Month"]} variant="outline"/>
				<Breadcrumb tag="crumbs" items={["Home", "Projects", "Gallery"]} onSelect={i -> chosen.value = "crumb " + i}/>
				<Pagination tag="pages" page={page} count={9}/>
			</div>)}
			{section("SPLIT: A TREE AND A TABLE", <div style="height:180px;border:1px solid var(--border);border-radius:var(--radius)"><Split tag="panes" size={pane} min={120} label="Sidebar"
				first={<Tree tag="files" roots={FILES} children={(e:Entry) -> e.children} render={(e:Entry) -> e.name} text={(e:Entry) -> e.name} expanded={open}
					selected={file} height={178} label="Files"/>}
				second={<Table tag="sizes" rows={SIZES} selected={row} height={178} label="Sizes" columns={[
					{title: "Name", cell: (e:Entry) -> e.name, compare: (a:Entry, b:Entry) -> Reflect.compare(a.name, b.name)},
					{title: "KB", width: "60px", numeric: true, cell: (e:Entry) -> "" + e.size, compare: (a:Entry, b:Entry) -> a.size - b.size}
				]}/>}/></div>)}
			{section("FIELD, TAGS AND AREA", <div style="display:flex;flex-direction:column;gap:6px">
				<Input tag="name" value={name} placeholder="Your name" label="Name"/>
				<span id="greeting" style="opacity:.7">{() -> name.value == "" ? "Type a name." : "Hello, " + name.value + "!"}</span>
				<TagInput tag="labels" tags={labels} label="Labels" placeholder="Add a label"/>
				<Textarea tag="notes" value={notes} rows={3} placeholder="Notes, on several lines"/>
				<span id="lines" style="opacity:.7">{() -> notes.value.split("\n").length + " lines"}</span>
			</div>)}
			{section("COMBOBOX, COMMAND, NUMBER, DISCLOSURE, TOASTS", <div style="display:flex;flex-direction:column;align-items:flex-start;gap:10px">
				<div style={ROW}>
					<Combobox tag="city" value={city} options={CITIES} placeholder="A city" label="City" onChoose={c -> Toasts.show("Chose " + c, {kind: "success"})}/>
					<NumberField tag="count" value={count} min={0} max={99} width={90} label="Count"/>
				</div>
				<div style="width:280px;border:1px solid var(--border);border-radius:var(--radius)"><Command tag="command" placeholder="Type a command" label="Commands" groups={[
					{heading: "Suggestions", items: [{label: "New file", shortcut: "Mod+Alt+F", onSelect: () -> Toasts.show("New file")},
						{label: "Open recent", onSelect: () -> Toasts.show("Open recent")}, {label: "Share", disabled: true}]}
				]}/></div>
				<Collapsible tag="more" label="What these are"><p style="opacity:.7">A combobox filters its options as you type; a toast says what happened, for a while.</p></Collapsible>
				<Button tag="notify" label="Show a toast" variant="outline" onClick={() -> Toasts.show("Deleted 3 files", {action: "Undo", onAction: () -> Toasts.show("Restored")})}/>
			</div>)}
			{section("CARDS, BADGES, ALERTS AND MORE", <div style="display:flex;flex-direction:column;gap:12px">
				<Card tag="card">
					<CardHeader><CardTitle text="Native widgets"/><CardDescription text="Real elements with shadcn's markup, styled by the theme's CSS."/></CardHeader>
					<CardContent><div style="display:flex;gap:6px"><Badge label="New"/><Badge label="Widgets" variant="secondary"/><Badge label="Beta" variant="outline"/></div></CardContent>
					<CardFooter><div style="display:flex;gap:8px"><Button tag="read" label="Read" size="sm"/><Button tag="later" label="Later" variant="ghost" size="sm"/></div></CardFooter>
				</Card>
				<Alert tag="alert"><AlertTitle text="Heads up"/><AlertDescription text="An alert: a title and a description, default or destructive."/></Alert>
				<div style={ROW}>
					<Toggle tag="bold" pressed={bold} label="Bold" variant="outline"/>
					<div style="height:24px"><Separator orientation="vertical"/></div>
					<Label text="Due"/>
					<DatePicker tag="due" value={due} today={TODAY} placeholder="Pick a date" label="Due"/>
					<HoverCard content={<p>The card shows after a moment.</p>}><Button variant="link" label="@hxmc"/></HoverCard>
				</div>
				<Accordion tag="faq" open={faq} sections={[
					{label: "Is it accessible?", render: () -> "Each widget is the element and role assistive technology expects."},
					{label: "Can it be themed?", render: () -> "By CSS: the theme's tokens, or rules of one's own on the slots."}
				]}/>
				<div style={ROW}>
					<div style="border-radius:9999px;overflow:hidden"><Skeleton width={40} height={40}/></div>
					<div style="display:flex;flex-direction:column;gap:6px"><Skeleton width={180} height={12}/><Skeleton width={120} height={12}/></div>
					<Avatar fallback="HX"/><Kbd text="Ctrl+K"/><Spinner/>
				</div>
				<div style={ROW}>
					<PopoverButton label="Popover"><p>A popover: anything in it.</p></PopoverButton>
					<ContextMenu items={[{label: "Copy", shortcut: "Mod+Alt+C", onSelect: () -> Toasts.show("Copied")}, {label: "Delete", variant: "destructive", onSelect: () -> Toasts.show("Deleted")}]}>
						<div id="area" style="padding:12px 16px;border:1px dashed var(--border);border-radius:var(--radius)">Right-click here</div>
					</ContextMenu>
				</div>
			</div>)}
			<Toaster/>
		</main>;
}
