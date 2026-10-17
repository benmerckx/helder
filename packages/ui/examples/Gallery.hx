// title: Widgets
// summary: ui's widgets bound to signals: a menu bar, a toolbar, a list box, a range slider, a colour picker, a select, a menu, a dialog, sliders, tabs, a tree and a table, images, text fields; right to left at a switch
// tags: ui, widgets
// demo: canvas 560x520
import hxmc.ui.*;
import hxmc.ui.draw.UiWindow;
import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.ui.widgets.Widgets.*;
import hxmc.ui.widgets.Toasts;
import hxmc.ui.widgets.Days;

// hxmc.ui's widgets side by side, bound to signals that other widgets show:
// buttons, a select, a menu, a tooltip and a dialog (popups over the
// rest), a checkbox and a switch, radio buttons, a slider driving a
// progress bar, tabs, a tree and a table in a split view, images fitted
// three ways, a text field and a text area, a combobox, a number field, a
// disclosure and toasts; all of it mirrored right to left at a switch. In a window:
//
//   haxe -lib hxmc.ui -cp packages/ui/examples -main Gallery --custom-target hxmc=gallery -D hxmc.libc=glibc
//
// (GalleryTest drives it headless.)
typedef Entry = {name:String, ?children:Array<Entry>, ?size:Int};

class Gallery implements Markup {
	static function main() {
		var w = new UiWindow("Gallery", 560, 520);
		w.ui.theme = Plain.sheet;
		Render.render(new Gallery().view(), w.root);
		UiWindow.run();
	}

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
	final picture = landscape(120, 60);

	public function new() {}

	// a landscape drawn pixel by pixel: sky, a sun, hills (an image without a file)
	public static function landscape(w:Int, h:Int):Image {
		var img = new Image(w, h);
		for (y in 0...h)
			for (x in 0...w) {
				var fx = x / w, fy = y / h;
				var r = 96 + 80 * fy, g = 165 + 60 * fy, b = 250 - 20 * fy;
				var dx = fx - 0.75, dy = fy - 0.3, sun = Math.sqrt(dx * dx * w * w + dy * dy * h * h) / (h * 0.16);
				if (sun < 1) {
					r = 253;
					g = 224 - 40 * sun;
					b = 71;
				}
				var hill = 0.62 + 0.1 * Math.sin(fx * 7.0), far = 0.55 + 0.08 * Math.sin(fx * 4.0 + 1.3);
				if (fy > far) {
					r = 74;
					g = 158 - 30 * (fy - far);
					b = 110;
				}
				if (fy > hill) {
					r = 34 + 20 * fy;
					g = 120 + 30 * fy;
					b = 60;
				}
				var o = 4 * (y * w + x);
				img.pixels.set(o, Std.int(r));
				img.pixels.set(o + 1, Std.int(g));
				img.pixels.set(o + 2, Std.int(b));
				img.pixels.set(o + 3, 255);
			}
		return img;
	}

	function section(title:String, content:View):View
		return <view row-gap={8}>
			<text font-size={12} font-weight={700} opacity={0.6}>{title}</text>
			{content}
		</view>;

	static final TABS = [
		"An overview of the widgets: each is a function of its props, bound to signals.",
		"Details: the content of a tab is rendered again when the selection changes.",
		"Notes: every widget here takes the keyboard focus and works with the keyboard."
	];

	function tabContent(i:Int):View
		return <Card tag="tab-content"><text>{TABS[i]}</text></Card>;

	public function view():View
		return <scroll slot="body" grow={1} padding={20} row-gap={18} font-family="DejaVu Sans" font-size={14} dir={() -> rtl.value ? "rtl" : "ltr"}>
			<view direction="row" align-items="center" justify="space-between">
				<view direction="row" align-items="center" column-gap={14}>
					<text font-size={22} font-weight={700}>Widgets</text>
					<Menubar tag="app" label="Gallery" menus={[
						{label: "File", items: [{label: "New", onSelect: () -> Toasts.show("New")}, {label: "Open…", onSelect: () -> Toasts.show("Open")}]},
						{label: "Edit", items: [{label: "Undo", onSelect: () -> Toasts.show("Undone")}, {label: "Redo", onSelect: () -> Toasts.show("Redone")}]},
						{label: "View", items: [{label: "Right to left", onSelect: () -> rtl.value = !rtl.value}]}
					]}/>
				</view>
				<Switch tag="rtl" checked={rtl} label="Right to left"/>
			</view>
			{section("BUTTONS IN A TOOLBAR", <view direction="row" column-gap={8} align-items="center">
				<Toolbar tag="buttons" label="Buttons">
					<Button tag="plain" label="Plain" onClick={() -> clicks.value++}/>
					<Button tag="primary" label="Primary" onClick={() -> clicks.value += 10}/>
				</Toolbar>
				<text tag="clicks" opacity={0.7}>{() -> "clicked " + clicks.value}</text>
			</view>)}
			{section("POPUPS", <view direction="row" column-gap={12} align-items="center">
				<Select tag="fruit" value={fruit} options={["Apple", "Pear", "Plum"]} label="Fruit" width={110}/>
				<DropdownMenu tag="file" label="File" items={[
					{label: "New", onSelect: () -> chosen.value = "New"},
					{label: "Open…", onSelect: () -> chosen.value = "Open"},
					{label: "Rename…", onSelect: () -> dialog.value = true}
				]}/>
				<Tooltip tag="tip" text="A tooltip, after half a second"><text opacity={0.7}>Hover me</text></Tooltip>
				<text tag="chosen" opacity={0.7}>{() -> chosen.value}</text>
				<Dialog open={dialog} title="Rename" description="The name the greeting below uses.">
					<Input tag="rename" value={name} placeholder="A new name"/>
					<DialogFooter><Button tag="done" label="Done" onClick={() -> dialog.value = false}/></DialogFooter>
				</Dialog>
			</view>)}
			{section("TOGGLES", <view direction="row" column-gap={24} align-items="center">
				<Checkbox tag="check" checked={checked} label="Checkbox"/>
				<Switch tag="switch" checked={on} label={"Switch"}/>
				<text tag="toggles" opacity={0.7}>{() -> (checked.value ? "checked" : "unchecked") + ", " + (on.value ? "on" : "off")}</text>
			</view>)}
			{section("RADIO AND LISTBOX", <view direction="row" column-gap={24} align-items="start">
				<RadioGroup tag="size" value={size} options={["Small", "Medium", "Large"]}/>
				<Listbox tag="days" selected={days} options={["Mon", "Tue", "Wed", "Thu", "Fri"]} multiple label="Days" width={110} height={104}/>
				<text tag="size-shown" opacity={0.7}>{() -> "size: " + size.value + ", " + days.value.join(" ")}</text>
			</view>)}
			{section("SLIDER, PROGRESS AND COLOUR", <view direction="row" column-gap={32} align-items="start">
				<view row-gap={10}>
					<view direction="row" column-gap={12} align-items="center">
						<Slider tag="volume" value={volume} step={0.05} width={200}/>
						<text tag="volume-shown" opacity={0.7}>{() -> Math.round(volume.value * 100) + "%"}</text>
					</view>
					<Progress value={volume} width={200}/>
					<view direction="row" column-gap={12} align-items="center">
						<RangeSlider tag="price" low={priceLow} high={priceHigh} min={0} max={100} step={5} width={200} label="Price"/>
						<text tag="price-shown" opacity={0.7}>{() -> priceLow.value + "–" + priceHigh.value}</text>
					</view>
				</view>
				<ColorPicker tag="colour" value={colour} size={130} label="Accent"/>
			</view>)}
			{section("TABS", <Tabs tag="tab" labels={["Overview", "Details", "Notes"]} selected={tab} render={tabContent}/>)}
			{section("SEGMENTS, BREADCRUMBS, PAGES", <view row-gap={10} align-items="start">
				<ToggleGroup tag="period" label="Period" value={period} options={["Day", "Week", "Month"]}/>
				<Breadcrumb tag="crumbs" items={["Home", "Projects", "Gallery"]} onSelect={i -> chosen.value = "crumb " + i}/>
				<Pagination tag="pages" page={page} count={9}/>
			</view>)}
			{section("SPLIT: A TREE AND A TABLE", <Split tag="panes" size={pane} min={120} label="Sidebar"
				first={<Tree tag="files" roots={FILES} children={(e:Entry) -> e.children} render={(e:Entry) -> e.name} expanded={open} selected={file}
					height={150} rowHeight={24} label="Files"/>}
				second={<Table tag="sizes" rows={SIZES} selected={row} height={150} rowHeight={24} label="Sizes" columns={[
					{title: "Name", cell: (e:Entry) -> e.name, compare: (a:Entry, b:Entry) -> Reflect.compare(a.name, b.name)},
					{title: "KB", width: "50px", numeric: true, cell: (e:Entry) -> "" + e.size, compare: (a:Entry, b:Entry) -> a.size - b.size}
				]}/>}></Split>)}
			{section("IMAGES: FILL, CONTAIN, COVER", <view direction="row" column-gap={12} align-items="start">
				<image tag="fill" src={picture} width={110} height={70} radius={8}/>
				<image tag="contain" src={picture} fit="contain" width={110} height={70} radius={8} background="#80808033"/>
				<image tag="cover" src={picture} fit="cover" width={110} height={70} radius={8}/>
				<image tag="natural" src={picture} radius={30}/>
			</view>)}
			{section("FIELD, TAGS AND AREA", <view row-gap={6}>
				<Input tag="name" value={name} placeholder="Your name"/>
				<text tag="greeting" opacity={0.7}>{() -> name.value == "" ? "Type a name." : "Hello, " + name.value + "!"}</text>
				<TagInput tag="labels" tags={labels} label="Labels" placeholder="Add a label"/>
				<Textarea tag="notes" value={notes} rows={3} placeholder="Notes, on several lines"/>
				<text tag="lines" opacity={0.7}>{() -> notes.value.split("\n").length + " lines"}</text>
			</view>)}
			{section("COMBOBOX, NUMBER, DISCLOSURE, TOASTS", <view row-gap={10} align-items="start">
				<view direction="row" column-gap={12} align-items="center">
					<Combobox tag="city" value={city} options={CITIES} placeholder="A city" label="City" onChoose={c -> Toasts.show("Chose " + c, {kind: "success"})}/>
					<NumberField tag="count" value={count} min={0} max={99} width={90} label="Count"/>
				</view>
				<Collapsible tag="more" label="What these are">
					<text opacity={0.7}>A combobox filters its options as you type; a toast says what happened, for a while.</text>
				</Collapsible>
				<Button tag="notify" label="Show a toast" onClick={() -> Toasts.show("Deleted 3 files", {action: "Undo", onAction: () -> Toasts.show("Restored")})}/>
			</view>)}
			{section("CARDS, BADGES, ALERTS AND MORE", <view row-gap={12} align-items="stretch">
				<Card tag="card">
					<CardHeader><CardTitle text="Unstyled widgets"/><CardDescription text="Their looks come from a theme, else the colour of the text."/></CardHeader>
					<CardContent><view direction="row" column-gap={6}><Badge label="New"/><Badge label="Widgets" variant="secondary"/><Badge label="Beta" variant="outline"/></view></CardContent>
					<CardFooter><Button tag="read" label="Read" size="sm"/><Button tag="later" label="Later" variant="ghost" size="sm"/></CardFooter>
				</Card>
				<Alert tag="alert"><AlertTitle text="Heads up"/><AlertDescription text="An alert: a title and a description, default or destructive."/></Alert>
				<view direction="row" column-gap={12} align-items="center">
					<Toggle tag="bold" pressed={bold} label="Bold"/>
					<Separator orientation="vertical"/>
					<Label text="Due"/>
					<DatePicker tag="due" value={due} today={TODAY} placeholder="Pick a date"/>
				</view>
				<Accordion tag="faq" open={faq} sections={[
					{label: "Is it accessible?", render: () -> <text opacity={0.7}>Each widget has the roles and states assistive technology reads.</text>},
					{label: "Can it be themed?", render: () -> <text opacity={0.7}>By the rules of a StyleSheet, for each slot, variant, size and state.</text>}
				]}/>
				<view direction="row" column-gap={10} align-items="center">
					<Skeleton width={40} height={40}/>
					<view row-gap={6}><Skeleton width={180} height={12}/><Skeleton width={120} height={12}/></view>
				</view>
			</view>)}
			<Toaster/>
		</scroll>;
}
