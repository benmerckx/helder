import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import helder.theme.Shadcn;
import helder.ui.*;
import helder.ui.draw.*;
import helder.ui.widgets.Widgets.*;
import helder.ui.widgets.Widgets.MenuItem;
import helder.ui.widgets.Widgets.DayRange;
import helder.ui.widgets.Toasts;
import helder.view.*;

// hxmc's widgets under Shadcn.sheet against shadcn/ui's own markup and CSS
// drawn by Chromium (ref/*.png, ref.mjs; npm test -- theme-fidelity): each
// case of ref/cases.json (a component, its variant, size, state, light or
// dark, right to left) drawn headless in its frame (padding 16, Inter),
// hovered by the pointer, focused by Tab, opened by a click or a key as the
// case asks, its transitions run to their ends, then compared by ImageDiff (as
// the image tests compare): a small mean difference, few pixels far apart (edges and
// glyphs are anti-aliased differently). A popup (crop) is compared in its
// box, 8px around it: hxmc places it by its trigger. Prints each case's
// numbers; writes each drawing to <out dir>.
//   FidelityTest <ref dir> <out dir>
class FidelityTest implements Markup {
	// (the page's width in ref.mjs: md: holds)
	static inline var W = 800;
	static inline var H = 600;
	static inline var MEAN = 4.0;
	static inline var FAR = 96;
	static inline var MAX_FAR = 0.02;

	// the cases known to differ, by the start of their names, and why (what
	// helder.ui lacks yet): reported, not failed; one that agrees is reported too
	static final KNOWN = [
		"input-value-" => "the field's line a pixel above where Chromium centres an <input>'s text",
		"table-" => "Table's rows a fixed rowHeight for its virtual list, the head's too (shadcn's head h-10, its rows by their padding), its columns 1fr each (shadcn's: a table's auto layout)",
		"dropdown-menu-open-rtl" => "right to left, an overflow-y-auto box shows a horizontal scrollbar",
		"field-" => "a field set's legend is one of its flex items here (gap-6 after it); Chromium lays a fieldset's legend out apart from its content, no gap after it, and the description's [[data-variant=legend]+&]:-mt-1.5 is an arbitrary selector, dropped",
		"input-group-focus" => "the field in a ContextMenu's wrapper (its edit menu), so its flex-1 grows nothing in the group's row; and the caret drawn",
	];

	static function known(name:String):Null<String> {
		for (k => why in KNOWN)
			if (StringTools.startsWith(name, k)) return why;
		return null;
	}

	static final MENU:Array<MenuItem> = [
		{label: "Profile", shortcut: "Mod+P", onSelect: () -> {}},
		{label: "Billing", shortcut: "Mod+B", onSelect: () -> {}},
		{label: "", separator: true},
		{label: "Delete", variant: "destructive", onSelect: () -> {}},
		{label: "Disabled", disabled: true}
	];

	// (null: no widget for the component yet, or for this case, which is skipped;
	// the case's attributes are set on the component's node after)
	static function widget(c:Dynamic):Null<View> {
		var text:String = c.text, variant:String = c.variant ?? "default", size:String = c.size ?? "default";
		var today = {year: 2026, month: 10, day: 17};
		return switch (c.component : String) {
			case "button": <Button label={text} variant={variant} size={size}/>;
			case "badge": <Badge label={text} variant={variant}/>;
			case "toggle": <Toggle pressed={new Signal(c.on == true)} label={text} variant={variant} size={size}/>;
			case "input": <Input value={new Signal(text ?? "")} placeholder={c.placeholder}/>;
			case "checkbox": <Checkbox checked={new Signal(c.checked == true)}/>;
			case "switch": <Switch checked={new Signal(c.checked == true)} size={size}/>;
			case "label" if (c.peerDisabled == true): <Checkbox checked={new Signal(false)} label={text} disabled={true}/>;
			case "label": <Label text={text}/>;
			case "textarea": <Textarea value={new Signal(text ?? "")} placeholder={c.placeholder}/>;
			case "progress": <Progress value={(c.value : Float) / 100}/>;
			case "radio-group": <RadioGroup value={new Signal("Default")} options={["Default", "Comfortable"]}/>;
			case "card":
				<Card>
					<CardHeader>
						<CardTitle text={c.title}/>
						<CardDescription text={c.description}/>
						<CardAction><Button variant="link" label={c.action}/></CardAction>
					</CardHeader>
					<CardContent><text>{text}</text></CardContent>
					<CardFooter><Button label={c.footer}/></CardFooter>
				</Card>;
			case "slider": <Slider value={new Signal((c.value : Float) / 100)}/>;
			case "tabs": <Tabs labels={["Account", "Password"]} selected={new Signal(0)} variant={c.variant} render={_ -> "Make changes to your account here."}/>;
			case "separator":
				<view>
					<text font-size={14} line-height={1} font-weight={500}>Radix Primitives</text>
					<view margin="16 0"><Separator/></view>
					<text font-size={14} line-height={20 / 14}>Blog</text>
				</view>;
			case "skeleton":
				<view direction="row" align-items="center" column-gap={16}>
					<Skeleton tag="round" width={48} height={48}/>
					<view row-gap={8}><Skeleton width={200} height={16}/><Skeleton width={150} height={16}/></view>
				</view>;
			case "toggle-group": <ToggleGroup value={new Signal("Italic")} options={["Bold", "Italic", "Underline"]} variant={variant}/>;
			case "alert": <Alert variant={variant}><AlertTitle text={c.title}/><AlertDescription text={text}/></Alert>;
			case "select" if (c.text != null): <Select value={new Signal(text)} options={[text, "Banana"]}/>;
			case "select": <Select value={new Signal("")} options={["Apple", "Banana"]} placeholder={c.placeholder}/>;
			case "select-content": <Select value={new Signal("Apple")} options={["Apple", "Banana", "Blueberry", "Grapes"]} width={128}/>;
			case "table":
				var rows = [["INV001", "Paid", "$250.00"], ["INV002", "Pending", "$150.00"], ["INV003", "Unpaid", "$350.00"]];
				var cols = [for (k in 0...3) {title: ["Invoice", "Status", "Amount"][k], cell: (r:Dynamic) -> (r[k] : String)}];
				<Table rows={rows} selected={new Signal(rows[1])} rowHeight={37} height={160} columns={cols}/>;
			case "accordion":
				<Accordion open={new Signal(0)} sections={[
					{label: "Product Information", render: () -> "Our flagship product combines cutting-edge technology with sleek design."},
					{label: "Shipping Details", render: () -> "We offer worldwide shipping."}
				]}/>;
			case "breadcrumb": <Breadcrumb items={["Home", "Components", "Breadcrumb"]} onSelect={_ -> {}}/>;
			case "pagination": <Pagination page={new Signal(2)} count={10}/>;
			case "dialog":
				<Dialog open={new Signal(true)} title="Edit profile" description="Make changes to your profile here. Click save when you're done." width={512}>
					<DialogFooter><Button variant="outline" label="Cancel"/><Button label="Save changes"/></DialogFooter>
				</Dialog>;
			case "sheet":
				<Sheet open={new Signal(true)} title="Edit profile" description="Make changes to your profile here. Click save when you're done.">
					<SheetFooter><Button label="Save changes"/><Button variant="outline" label="Close"/></SheetFooter>
				</Sheet>;
			case "popover":
				<PopoverButton label="Open popover">
					<view slot="popover-header"><text slot="popover-title">Dimensions</text><text slot="popover-description">Set the dimensions for the layer.</text></view>
				</PopoverButton>;
			case "hover-card":
				<HoverCard content={<text font-size={14} line-height={20 / 14}>The React Framework, created and maintained by @vercel.</text>}><Button variant="link" label="@nextjs"/></HoverCard>;
			case "tooltip": <Tooltip text="Add to library"><Button variant="outline" label="Hover"/></Tooltip>;
			case "dropdown-menu": <DropdownMenu label="Open" items={MENU}/>;
			case "context-menu": <ContextMenu items={MENU}><view tag="area" width={200} height={80}/></ContextMenu>;
			case "menubar": <Menubar menus={[{label: "File", items: []}, {label: "Edit", items: []}, {label: "View", items: []}]}/>;
			case "menubar-content":
				<Menubar menus={[{label: "File", items: [
					{label: "New Tab", shortcut: "Mod+T", onSelect: () -> {}},
					{label: "New Window", shortcut: "Mod+N", onSelect: () -> {}},
					{label: "", separator: true},
					{label: "Share", onSelect: () -> {}},
					{label: "Print", shortcut: "Mod+P", onSelect: () -> {}}
				]}]}/>;
			case "combobox": <Combobox value={new Signal("")} options={["Next.js", "SvelteKit", "Nuxt.js", "Remix", "Astro"]} width={200}/>;
			case "command":
				<Command placeholder="Type a command or search..." groups={[
					{heading: "Suggestions", items: [{label: "Calendar", onSelect: () -> {}}, {label: "Search Emoji", onSelect: () -> {}}, {label: "Calculator", disabled: true}]},
					{heading: "Settings", items: [
						{label: "Profile", shortcut: "Mod+P", onSelect: () -> {}},
						{label: "Billing", shortcut: "Mod+B", onSelect: () -> {}},
						{label: "Settings", shortcut: "Mod+S", onSelect: () -> {}}
					]}
				]}/>;
			case "alert-dialog":
				<AlertDialog open={new Signal(true)} title="Are you absolutely sure?" width={512}
					description="This action cannot be undone. This will permanently delete your account and remove your data from our servers."/>;
			case "drawer":
				<Drawer open={new Signal(true)} title="Move Goal" description="Set your daily activity goal.">
					<DrawerFooter><Button label="Submit"/><Button variant="outline" label="Cancel"/></DrawerFooter>
				</Drawer>;
			case "input-otp": <InputOTP value={new Signal("12")} length={6} groups={[3, 3]}/>;
			case "dropdown-menu-items":
				<DropdownMenu label="Open" items={[
					{label: "Appearance", heading: true},
					{label: "Status Bar", checked: new Signal(true), onSelect: () -> {}},
					{label: "Panel", checked: new Signal(false), onSelect: () -> {}},
					{label: "", separator: true},
					{label: "More", items: [{label: "Email", onSelect: () -> {}}]}
				]}/>;
			case "avatar": <Avatar fallback="CN"/>;
			case "kbd": <Kbd text="Ctrl"/>;
			case "spinner": <Spinner/>;
			case "resizable": <view height={160}><Split first={<view grow={1} align-items="center" justify="center" padding={24}><text font-weight={600}>One</text></view>}
					second={<view grow={1} align-items="center" justify="center" padding={24}><text font-weight={600}>Two</text></view>} size={new Signal(150.0)}/></view>;
			case "calendar" if (c.range != null):
				var r:DayRange = {from: {year: 2026, month: 10, day: 12}, to: {year: 2026, month: 10, day: 16}};
				<Calendar range={new Signal(r)} today={{year: 2026, month: 10, day: 17}} firstDay={0}/>;
			case "calendar": <Calendar value={new Signal({year: 2026, month: 10, day: 12})} today={today} firstDay={0}/>;
			case "toast": <Toaster placement="top-left"/>;
			case "field":
				<FieldSet>
					<FieldLegend text="Profile"/>
					<FieldDescription text="How others see you."/>
					<FieldGroup>
						<Field><FieldLabel text="Name"/><Input value={new Signal("")} placeholder="Ada Lovelace"/><FieldDescription text="Shown on your posts."/></Field>
						<Field invalid={true}><FieldLabel text="Email"/><Input value={new Signal("not an email")} invalid={true}/><FieldError text="Enter an email address."/></Field>
						<FieldSeparator/>
						<Field orientation="horizontal">
							<FieldContent><FieldLabel text="Newsletter"/><FieldDescription text="A monthly email."/></FieldContent>
							<Switch checked={new Signal(true)}/>
						</Field>
					</FieldGroup>
				</FieldSet>;
			case "button-group" if (c.text != null):
				<ButtonGroup>
					<Button variant="outline" label="−"/><ButtonGroupText text={text}/><ButtonGroupSeparator/><Button variant="outline" label="+"/>
				</ButtonGroup>;
			case "button-group" if (variant == "vertical"):
				<ButtonGroup orientation="vertical"><Button variant="outline" size="sm" label="In"/><Button variant="outline" size="sm" label="Out"/></ButtonGroup>;
			case "button-group":
				<ButtonGroup><Button variant="outline" label="Archive"/><Button variant="outline" label="Report"/><Button variant="outline" label="Snooze"/></ButtonGroup>;
			case "input-group" if (c.text != null):
				<InputGroup>
					<InputGroupAddon><InputGroupText text="https://"/></InputGroupAddon>
					<InputGroupInput value={new Signal(text)}/>
					<InputGroupAddon align="inline-end"><InputGroupText text=".com"/></InputGroupAddon>
				</InputGroup>;
			case "input-group":
				<InputGroup>
					<InputGroupInput value={new Signal("")} placeholder="Search"/>
					<InputGroupAddon align="inline-end"><Button variant="ghost" size="sm" label="Clear"/></InputGroupAddon>
				</InputGroup>;
			case "empty":
				<Empty>
					<EmptyHeader>
						<EmptyMedia variant="icon"><image src={icon(FOLDER)} width={24} height={24}/></EmptyMedia>
						<EmptyTitle text="No projects yet"/>
						<EmptyDescription text="You haven't made a project. Start with your first one."/>
					</EmptyHeader>
					<EmptyContent><Button label="Create a project"/></EmptyContent>
				</Empty>;
			case "item" if (variant == "muted"):
				<Item variant="muted" size="sm" onClick={() -> {}}>
					<ItemContent><ItemTitle text="Grace Hopper"/><ItemDescription text="Wrote the first compiler."/></ItemContent>
				</Item>;
			case "item":
				<Item variant="outline">
					<ItemMedia variant="icon"><text>A</text></ItemMedia>
					<ItemContent><ItemTitle text="Ada Lovelace"/><ItemDescription text="Wrote the first program."/></ItemContent>
					<ItemActions><Button variant="outline" size="sm" label="Invite"/></ItemActions>
				</Item>;
			case "carousel":
				var slides:Array<Any> = [for (n in 1...4) <view slot="slide"><text>{Std.string(n)}</text></view>];
				<Carousel slides={slides}/>;
			case "navigation-menu":
				function link(t:String, d:String):View
					return <view slot="navigation-menu-link" role="link" focusable><text slot="nav-title">{t}</text><text slot="nav-description">{d}</text></view>;
				function panel(links:Array<View>):View
					return <view width={300} row-gap={8}>{links}</view>;
				var items:Array<{label:String, ?render:Void->Any, ?onSelect:Void->Void}> = [
					{label: "Getting started", render: () -> panel([link("Introduction", "What it is and why."), link("Installation", "How to add it.")])},
					{label: "Components", render: () -> panel([link("Button", "Pressed to act.")])}
				];
				<NavigationMenu items={items}/>;
			case "sidebar":
				<SidebarProvider open={new Signal(variant != "icon")}>
					<Sidebar collapsible="icon">
						<SidebarHeader><text font-weight={600}>Mail</text></SidebarHeader>
						<SidebarContent>
							<SidebarGroup>
								<SidebarGroupLabel text="Folders"/>
								<SidebarGroupContent><SidebarMenu>{[
									for (i in 0...3)
										<SidebarMenuItem><SidebarMenuButton label={["Inbox", "Drafts", "Sent"][i]} active={i == 0}><image src={icon(CIRCLE)} width={16} height={16}/></SidebarMenuButton></SidebarMenuItem>
								]}</SidebarMenu></SidebarGroupContent>
							</SidebarGroup>
						</SidebarContent>
						<SidebarFooter><text>Signed in</text></SidebarFooter>
					</Sidebar>
					<SidebarInset><view direction="row" align-items="center" column-gap={8}><SidebarTrigger/><text>Inbox</text></view></SidebarInset>
				</SidebarProvider>;
			case "chart-tooltip" | "chart-legend":
				<BarChart labels={["Jan", "Feb", "Mar", "Apr", "May", "Jun"]}
					series={[{name: "Desktop", values: [186, 305, 237, 73, 209, 214]}, {name: "Mobile", values: [80, 200, 120, 190, 130, 140]}]}/>;
			case "aspect-ratio":
				<AspectRatio ratio={16 / 9}><view grow={1} align-items="center" justify="center"><text slot="ar-text">16 : 9</text></view></AspectRatio>;
			case "scroll-area":
				<ScrollArea width={200} height={200}><view slot="sa-list">{[for (i in 0...50) <text>{"v1.2.0-beta." + (50 - i)}</text>]}</view></ScrollArea>;
			case "native-select": <NativeSelect value={new Signal("todo")} options={["todo", "doing", "done"]} labels={["To do", "In progress", "Done"]}/>;
			case _: null;
		}
	}

	// (what a case does once drawn, as the user would: open a popup, hover, focus)
	static function act(c:Dynamic, ui:Ui) {
		inline function click(n:Null<Node>) {
			if (n == null) return;
			ui.pointerMove(n.absX + n.width / 2, n.absY + n.height / 2);
			ui.pointerDown(n.absX + n.width / 2, n.absY + n.height / 2, 1);
			ui.pointerUp(n.absX + n.width / 2, n.absY + n.height / 2, 1);
		}
		switch (c.component : String) {
			case "select-content": click(find(ui.root, "select-trigger"));
			case "dropdown-menu" | "dropdown-menu-items": click(find(ui.root, "button"));
			case "input-otp": ui.setFocus(ui.root.find("otp-input"));
			case "popover": click(find(ui.root, "button"));
			case "menubar-content": click(find(ui.root, "menubar-trigger"));
			case "context-menu":
				var n = ui.root.find("area");
				ui.pointerDown(n.absX + 8, n.absY + 8, 3);
				ui.pointerUp(n.absX + 8, n.absY + 8, 3);
			case "tooltip" | "hover-card":
				var n = find(ui.root, "button");
				ui.pointerMove(n.absX + n.width / 2, n.absY + n.height / 2);
			case "combobox":
				var f = find(ui.root, "input");
				ui.setFocus(f);
				ui.keyDown(Key.DOWN, 0);
				ui.keyUp(Key.DOWN, 0);
			case "toast": Toasts.show(c.text, {action: c.action, duration: 0});
			case "navigation-menu" if (c.crop != null): click(find(ui.root, "navigation-menu-trigger"));
			case "chart-legend":
				// (the legend alone, as its reference: the axis above it out of its margin)
				find(ui.root, "chart-x-axis").style.visibility = helder.ui.Visibility.Hidden;
			case "chart-tooltip":
				// (the pointer over February's bars)
				var n = find(ui.root, "chart-plot");
				ui.pointerMove(n.absX + n.width * 1.5 / 6, n.absY + n.height / 2);
			case "skeleton":
				var n = ui.root.find("round");
				n.style.radius = 1e6;
			case "resizable":
				var n = find(ui.root, "resizable-panel-group");
				n.style.set({borderWidth: 1, radius: 10});
			case _:
		}
	}

	// (made in main: after the statics they use)
	static var EXTRA:Map<String, Array<Rule>>;

	// (the node a case's states are on: the component's main slot)
	static final TARGET = ["input-group" => "input-group-control", "radio-group" => "radio-group-item", "slider" => "slider-thumb", "tabs" => "tabs-trigger", "select" => "select-trigger"];

	// lucide's icons (ISC) the cases draw, as their references
	static inline var FOLDER = '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>';
	static inline var CIRCLE = '<circle cx="12" cy="12" r="10"/>';

	static function icon(paths:String):Svg
		return Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">$paths</svg>');

	static function find(n:Node, slot:String):Null<Node> {
		if (n.slot == slot) return n;
		for (k in n.children) {
			var f = find(k, slot);
			if (f != null) return f;
		}
		return null;
	}

	// (the clock run on, a second in tenths: transitions, a tooltip's delay; whole seconds after, a spinner upright)
	static function settle(ui:Ui) {
		var t = Math.ffloor(Clock.now) + 1;
		for (k in 1...10) {
			Clock.tick(t + k / 10);
			ui.update();
		}
		Clock.tick(t + 1);
		ui.update();
	}

	static function main() {
		var args = Sys.args();
		EXTRA = [
			"command" => helder.theme.Tw.rules("command", "rounded-lg border border-border shadow-md md:min-w-[450px]"),
			"carousel" => helder.theme.Tw.rules("carousel", "mx-12 w-[200px]")
				.concat(helder.theme.Tw.rules("slide", "flex h-[120px] items-center justify-center rounded-lg border border-border text-3xl font-semibold")),
			"navigation-menu" => helder.theme.Tw.rules("nav-title", "text-sm leading-none font-medium")
				.concat(helder.theme.Tw.rules("nav-description", "line-clamp-2 text-sm leading-snug text-muted-foreground")),
			"sidebar" => helder.theme.Tw.rules("sidebar-wrapper", "min-h-0 h-full").concat(helder.theme.Tw.rules("sidebar-container", "h-auto")),
			"aspect-ratio" => helder.theme.Tw.rules("aspect-ratio", "rounded-lg bg-muted").concat(helder.theme.Tw.rules("ar-text", "text-sm text-muted-foreground")),
			"scroll-area" => helder.theme.Tw.rules("scroll-area", "rounded-md border border-border").concat(helder.theme.Tw.rules("sa-list", "flex flex-col gap-2 p-3 text-sm"))
		];
		var cases:Array<Dynamic> = haxe.Json.parse(sys.io.File.getContent(args[0] + "/cases.json"));
		var device = Device.create(Surface.headless(W, H));
		var r = new Renderer(device);
		var pixels = Bytes.alloc(W * H * 4);
		function draw(ui:Ui) {
			var enc = device.beginFrame();
			var pass:PassDesc = {colors: [{load: Clear, clear: new helder.gfx.Color(1, 0, 1)}]};
			enc.beginPass(pass);
			r.begin(W, H);
			ui.paint(r);
			r.end(enc);
			enc.endPass();
			device.readPixels(pixels);
			device.endFrame();
		}
		var failed = 0, skipped = 0;
		for (c in cases) {
			var view = widget(c);
			if (view == null) {
				Sys.println('FidelityTest: ${c.name} skipped (no widget or prop for it)');
				skipped++;
				continue;
			}
			var w:Int = c.w, h:Int = c.h, fw:Int = c.fw ?? c.w, fh:Int = c.fh ?? c.h;
			var ui = new Ui(new DrawText(), W, H);
			// (the classes an example adds to its instance, as rules after the sheet's)
			var extra = EXTRA[c.component];
			ui.theme = extra == null ? Shadcn.sheet : {rules: Shadcn.sheet.rules.concat(extra), light: Shadcn.sheet.light, dark: Shadcn.sheet.dark, lengths: Shadcn.sheet.lengths};
			ui.dark = c.dark == true;
			// (a word too wide for its line overflowing it, CSS's initial overflow-wrap, ui's root's BreakWord aside)
			for (n in [ui.root, ui.overlay])
				n.style.set({fontFamily: "Inter", dir: c.rtl == true ? Rtl : Ltr, overflowWrap: Normal});
			var frame = new Node("frame");
			frame.slot = "body";
			frame.style.set({width: fw, height: fh, padding: 16, fontFamily: "Inter", direction: c.block ? Column : Row, alignItems: c.block ? Stretch : Start});
			ui.root.append(frame);
			Render.render(view, frame);
			ui.update();
			var states:Array<String> = c.states == null ? [] : c.states;
			var target = find(ui.root, TARGET[c.component] ?? c.component);
			var attrs:haxe.DynamicAccess<Dynamic> = c.attrs ?? {};
			for (k => v in attrs)
				target.setAttr(k, v == true ? "" : v);
			ui.update();
			act(c, ui);
			if (states.contains("hover")) ui.pointerMove(target.absX + target.width / 2, target.absY + target.height / 2);
			if (states.contains("focus-visible")) {
				ui.keyDown(Key.TAB, 0);
				ui.keyUp(Key.TAB, 0);
			}
			for (_ in 0...3) {
				ui.update();
				draw(ui);
				settle(ui);
			}
			draw(ui);
			// (the frame, or a popup's box 8px around it)
			var x0 = Math.round(frame.absX), y0 = Math.round(frame.absY);
			if (c.crop != null) {
				var n = find(ui.overlay, c.crop) ?? find(ui.root, c.crop);
				if (n != null) {
					x0 = Math.round(n.absX) - 8;
					y0 = Math.round(n.absY) - 8;
				}
			}
			var got = Bytes.alloc(w * h * 4);
			for (y in 0...h)
				for (x in 0...w) {
					var sx = x0 + x, sy = y0 + y;
					if (sx >= 0 && sy >= 0 && sx < W && sy < H) got.blit((y * w + x) * 4, pixels, (sy * W + sx) * 4, 4);
				}
			Toasts.clear();
			sys.io.File.saveBytes('${args[1]}/${c.name}.png', Png.encode(got, w, h));
			var want = PngDecoder.decode(sys.io.File.getBytes('${args[0]}/${c.name}.png'));
			var diff = ImageDiff.of(got, want.rgba, w, h, FAR);
			var ok = diff.within(MAX_FAR, MEAN), why = known(c.name);
			if (!ok && why == null) failed++;
			var verdict = why == null ? (ok ? "ok" : "FAILED") : ok ? 'ok, though known to differ ($why)' : 'differs, as known ($why)';
			Sys.println('FidelityTest: ${c.name} $verdict ($diff)');
		}
		device.dispose();
		Sys.println('FidelityTest: ${cases.length - skipped} cases ($skipped without a widget yet)' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
