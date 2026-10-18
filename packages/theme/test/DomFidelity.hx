import hxmc.ui.widgets.Toasts;
import hxmc.view.*;
import hxmc.web.widgets.Widgets.*;
import hxmc.web.widgets.Widgets.MenuItem;
import hxmc.web.widgets.Widgets.DayRange;
import js.Browser.document;

// The bundle dom-fidelity.mjs drives (make theme-dom-check): renderCase(c,
// width, height) renders a case of ref/cases.json with the DOM's widgets
// in #frame as ref.mjs frames shadcn's markup (false: no widget for it);
// toast(text, action) shows a toast.
class DomFidelity implements Markup {
	static var dispose:Null<Void->Void>;

	static final MENU:Array<MenuItem> = [
		{label: "Profile", shortcut: "Mod+P", onSelect: () -> {}},
		{label: "Billing", shortcut: "Mod+B", onSelect: () -> {}},
		{label: "", separator: true},
		{label: "Delete", variant: "destructive", onSelect: () -> {}},
		{label: "Disabled", disabled: true}
	];

	// (null: no widget for the component yet)
	static function widget(c:Dynamic):Null<View> {
		var text:String = c.text, variant:String = c.variant ?? "default", size:String = c.size ?? "default";
		return switch (c.component : String) {
			case "button": <Button label={text} variant={variant} size={size}/>;
			case "badge": <Badge label={text} variant={variant}/>;
			case "toggle": <Toggle pressed={new Signal(c.on == true)} label={text} variant={variant} size={size}/>;
			case "input": <Input value={new Signal(text ?? "")} placeholder={c.placeholder}/>;
			case "textarea": <Textarea value={new Signal(text ?? "")} placeholder={c.placeholder}/>;
			case "checkbox": <Checkbox checked={new Signal(c.checked == true)}/>;
			case "switch": <Switch checked={new Signal(c.checked == true)} size={size}/>;
			case "label" if (c.peerDisabled == true): <Checkbox checked={new Signal(false)} label={text} disabled={true}/>;
			case "label": <Label text={text}/>;
			case "card":
				<Card>
					<CardHeader>
						<CardTitle text={c.title}/>
						<CardDescription text={c.description}/>
						<CardAction><Button variant="link" label={c.action}/></CardAction>
					</CardHeader>
					<CardContent><p>{text}</p></CardContent>
					<CardFooter><Button label={c.footer}/></CardFooter>
				</Card>;
			case "separator":
				<div>
					<div style="font-size:14px;line-height:1;font-weight:500">Radix Primitives</div>
					<div style="margin:16px 0"><Separator/></div>
					<div style="font-size:14px;line-height:20px">Blog</div>
				</div>;
			case "skeleton":
				<div style="display:flex;align-items:center;gap:16px">
					<div style="border-radius:9999px;overflow:hidden"><Skeleton width={48} height={48}/></div>
					<div style="display:flex;flex-direction:column;gap:8px"><Skeleton width={200} height={16}/><Skeleton width={150} height={16}/></div>
				</div>;
			case "alert": <Alert variant={variant}><AlertTitle text={c.title}/><AlertDescription text={text}/></Alert>;
			case "avatar": <Avatar fallback="CN"/>;
			case "radio-group": <RadioGroup value={new Signal("Default")} options={["Default", "Comfortable"]}/>;
			case "slider": <Slider value={new Signal((c.value : Float) / 100)}/>;
			case "tabs": <Tabs labels={["Account", "Password"]} selected={new Signal(0)} variant={c.variant} render={_ -> "Make changes to your account here."}/>;
			case "progress": <Progress value={(c.value : Float) / 100}/>;
			case "toggle-group": <ToggleGroup value={new Signal("Italic")} options={["Bold", "Italic", "Underline"]} variant={variant}/>;
			case "accordion":
				<Accordion open={new Signal(0)} sections={[
					{label: "Product Information", render: () -> "Our flagship product combines cutting-edge technology with sleek design."},
					{label: "Shipping Details", render: () -> "We offer worldwide shipping."}
				]}/>;
			case "breadcrumb": <Breadcrumb items={["Home", "Components", "Breadcrumb"]} onSelect={_ -> {}}/>;
			case "pagination": <Pagination page={new Signal(2)} count={10}/>;
			case "select" if (c.text != null): <Select value={new Signal(text)} options={[text, "Banana"]}/>;
			case "select": <Select value={new Signal("")} options={["Apple", "Banana"]} placeholder={c.placeholder}/>;
			case "select-content": <Select value={new Signal("Apple")} options={["Apple", "Banana", "Blueberry", "Grapes"]}/>;
			case "dialog":
				<Dialog open={new Signal(true)} title="Edit profile" description="Make changes to your profile here. Click save when you're done." width={512}>
					<DialogFooter><Button variant="outline" label="Cancel"/><Button label="Save changes"/></DialogFooter>
				</Dialog>;
			case "sheet":
				<Sheet open={new Signal(true)} title="Edit profile" description="Make changes to your profile here. Click save when you're done.">
					<SheetFooter><Button label="Save changes"/><Button variant="outline" label="Close"/></SheetFooter>
				</Sheet>;
			case "alert-dialog":
				<AlertDialog open={new Signal(true)} title="Are you absolutely sure?" width={512}
					description="This action cannot be undone. This will permanently delete your account and remove your data from our servers."/>;
			case "drawer":
				<Drawer open={new Signal(true)} title="Move Goal" description="Set your daily activity goal.">
					<DrawerFooter><Button label="Submit"/><Button variant="outline" label="Cancel"/></DrawerFooter>
				</Drawer>;
			case "popover":
				<PopoverButton label="Open popover">
					<div data-slot="popover-header"><div data-slot="popover-title">Dimensions</div><div data-slot="popover-description">Set the dimensions for the layer.</div></div>
				</PopoverButton>;
			case "hover-card": <HoverCard content={<p style="font-size:14px;line-height:20px">The React Framework, created and maintained by @vercel.</p>}><Button variant="link" label="@nextjs"/></HoverCard>;
			case "tooltip": <Tooltip text="Add to library"><Button variant="outline" label="Hover"/></Tooltip>;
			case "dropdown-menu": <DropdownMenu label="Open" items={MENU}/>;
			case "context-menu": <ContextMenu items={MENU}><div id="area" style="width:200px;height:80px"/></ContextMenu>;
			case "menubar": <Menubar menus={[{label: "File", items: []}, {label: "Edit", items: []}, {label: "View", items: []}]}/>;
			case "menubar-content":
				<Menubar menus={[{label: "File", items: [
					{label: "New Tab", shortcut: "Mod+T", onSelect: () -> {}},
					{label: "New Window", shortcut: "Mod+N", onSelect: () -> {}},
					{label: "", separator: true},
					{label: "Share", onSelect: () -> {}},
					{label: "Print", shortcut: "Mod+P", onSelect: () -> {}}
				]}]}/>;
			case "dropdown-menu-items":
				<DropdownMenu label="Open" items={[
					{label: "Appearance", heading: true},
					{label: "Status Bar", checked: new Signal(true), onSelect: () -> {}},
					{label: "Panel", checked: new Signal(false), onSelect: () -> {}},
					{label: "", separator: true},
					{label: "More", items: [{label: "Email", onSelect: () -> {}}]}
				]}/>;
			case "combobox": <Combobox value={new Signal("")} options={["Next.js", "SvelteKit", "Nuxt.js", "Remix", "Astro"]} width={200}/>;
			case "command":
				<div class="command-example" style="display:contents"><Command placeholder="Type a command or search..." groups={[
					{heading: "Suggestions", items: [{label: "Calendar", onSelect: () -> {}}, {label: "Search Emoji", onSelect: () -> {}}, {label: "Calculator", disabled: true}]},
					{heading: "Settings", items: [
						{label: "Profile", shortcut: "Mod+P", onSelect: () -> {}},
						{label: "Billing", shortcut: "Mod+B", onSelect: () -> {}},
						{label: "Settings", shortcut: "Mod+S", onSelect: () -> {}}
					]}
				]}/></div>;
			case "input-otp": <InputOTP value={new Signal("12")} length={6} groups={[3, 3]}/>;
			case "calendar" if (c.range != null):
				var r:DayRange = {from: {year: 2026, month: 10, day: 12}, to: {year: 2026, month: 10, day: 16}};
				<Calendar range={new Signal(r)} today={{year: 2026, month: 10, day: 17}} firstDay={0}/>;
			case "calendar": <Calendar value={new Signal({year: 2026, month: 10, day: 12})} today={{year: 2026, month: 10, day: 17}} firstDay={0}/>;
			case "toast": <Toaster placement="top-left"/>;
			case "table":
				var rows = [["INV001", "Paid", "$250.00"], ["INV002", "Pending", "$150.00"], ["INV003", "Unpaid", "$350.00"]];
				var cols = [for (k in 0...3) {title: ["Invoice", "Status", "Amount"][k], cell: (r:Dynamic) -> (r[k] : String)}];
				<Table rows={rows} selected={new Signal(rows[1])} columns={cols}/>;
			case "resizable":
				var pane = (t:String) -> <div style="display:flex;height:100%;align-items:center;justify-content:center;padding:24px"><span style="font-weight:600">{t}</span></div>;
				<div class="resizable-example" style="display:contents"><Split first={pane("One")} second={pane("Two")} size={new Signal(150.0)}/></div>;
			case "kbd": <Kbd text="Ctrl"/>;
			case "spinner": <Spinner/>;
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
						<EmptyMedia variant="icon">{hxmc.web.widgets.Dom.icon("folder")}</EmptyMedia>
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
					<ItemMedia variant="icon">A</ItemMedia>
					<ItemContent><ItemTitle text="Ada Lovelace"/><ItemDescription text="Wrote the first program."/></ItemContent>
					<ItemActions><Button variant="outline" size="sm" label="Invite"/></ItemActions>
				</Item>;
			case "carousel":
				var slides:Array<Any> = [for (n in 1...4) <div data-slot="slide">{Std.string(n)}</div>];
				<div class="carousel-example" style="display:contents"><Carousel slides={slides}/></div>;
			case "navigation-menu":
				function link(t:String, d:String):View
					return <a data-slot="navigation-menu-link" href="#"><div data-slot="nav-title">{t}</div><p data-slot="nav-description">{d}</p></a>;
				function panel(links:Array<View>):View
					return <ul style="display:grid;width:300px;gap:8px">{[for (l in links) <li>{l}</li>]}</ul>;
				var items:Array<{label:String, ?render:Void->Any, ?onSelect:Void->Void}> = [
					{label: "Getting started", render: () -> panel([link("Introduction", "What it is and why."), link("Installation", "How to add it.")])},
					{label: "Components", render: () -> panel([link("Button", "Pressed to act.")])}
				];
				<NavigationMenu items={items}/>;
			case "sidebar":
				<div class="sidebar-example" style="display:contents"><SidebarProvider open={new Signal(variant != "icon")}>
					<Sidebar collapsible="icon">
						<SidebarHeader><span style="font-weight:600">Mail</span></SidebarHeader>
						<SidebarContent>
							<SidebarGroup>
								<SidebarGroupLabel text="Folders"/>
								<SidebarGroupContent><SidebarMenu>{[
									for (i in 0...3)
										<SidebarMenuItem><SidebarMenuButton label={["Inbox", "Drafts", "Sent"][i]} active={i == 0}>{hxmc.web.widgets.Dom.icon("circle")}</SidebarMenuButton></SidebarMenuItem>
								]}</SidebarMenu></SidebarGroupContent>
							</SidebarGroup>
						</SidebarContent>
						<SidebarFooter><span>Signed in</span></SidebarFooter>
					</Sidebar>
					<SidebarInset><div style="display:flex;align-items:center;gap:8px"><SidebarTrigger/><span>Inbox</span></div></SidebarInset>
				</SidebarProvider></div>;
			case "chart-tooltip" | "chart-legend":
				<BarChart labels={["Jan", "Feb", "Mar", "Apr", "May", "Jun"]}
					series={[{name: "Desktop", values: [186, 305, 237, 73, 209, 214]}, {name: "Mobile", values: [80, 200, 120, 190, 130, 140]}]}/>;
			case "aspect-ratio":
				<div class="aspect-example" style="display:contents"><AspectRatio ratio={16 / 9}><div data-slot="ar-text">16 : 9</div></AspectRatio></div>;
			case "scroll-area":
				<div class="scroll-example" style="display:contents"><ScrollArea width={200} height={200}>
					<div data-slot="sa-list">{[for (i in 0...50) <div>{"v1.2.0-beta." + (50 - i)}</div>]}</div>
				</ScrollArea></div>;
			case "native-select": <NativeSelect value={new Signal("todo")} options={["todo", "doing", "done"]} labels={["To do", "In progress", "Done"]}/>;
			case _: null;
		}
	}

	static function renderCase(c:Dynamic, w:Int, h:Int):Bool {
		if (dispose != null) dispose();
		dispose = null;
		Toasts.clear();
		var html = document.documentElement;
		html.className = c.dark == true ? "dark" : "";
		if (c.rtl == true) html.setAttribute("dir", "rtl") else html.removeAttribute("dir");
		var frame = document.getElementById("frame");
		// (a popup compared in its box: the frame away from the window's edges, which would push it)
		frame.setAttribute("style", 'box-sizing:border-box;width:${w}px;height:${h}px;padding:16px;background-color:var(--background)'
			+ (c.crop != null ? ";margin:120px 0 0 200px" : "")
			+ (c.block == true ? "" : ";display:flex;align-items:flex-start"));
		var v = widget(c);
		if (v == null) return false;
		dispose = Render.render(v, frame);
		return true;
	}

	static function main() {
		// (the classes shadcn's example adds to its command)
		var style = document.createStyleElement();
		style.textContent = hxmc.theme.Css.classes(".command-example > [data-slot=command]", "rounded-lg border shadow-md md:min-w-[450px]")
			+ hxmc.theme.Css.classes(".resizable-example > [data-slot=resizable-panel-group]", "rounded-lg border")
			+ hxmc.theme.Css.classes(".carousel-example > [data-slot=carousel]", "mx-12 w-[200px]")
			+ hxmc.theme.Css.classes("[data-slot=slide]", "flex h-[120px] items-center justify-center rounded-lg border text-3xl font-semibold")
			+ hxmc.theme.Css.classes("[data-slot=nav-title]", "text-sm leading-none font-medium")
			+ hxmc.theme.Css.classes("[data-slot=nav-description]", "line-clamp-2 text-sm leading-snug text-muted-foreground")
			+ hxmc.theme.Css.classes(".sidebar-example [data-slot=sidebar-wrapper]", "min-h-0 h-full [contain:layout]")
			+ hxmc.theme.Css.classes(".sidebar-example [data-slot=sidebar-container]", "h-auto")
			+ hxmc.theme.Css.classes(".aspect-example [data-slot=aspect-ratio]", "rounded-lg bg-muted")
			+ hxmc.theme.Css.classes("[data-slot=ar-text]", "flex h-full items-center justify-center text-sm text-muted-foreground")
			+ hxmc.theme.Css.classes(".scroll-example > [data-slot=scroll-area]", "rounded-md border")
			+ hxmc.theme.Css.classes("[data-slot=sa-list]", "flex flex-col gap-2 p-3 text-sm");
		document.head.appendChild(style);
		js.Syntax.code("window.renderCase = {0}", renderCase);
		js.Syntax.code("window.toast = {0}", (text:String, action:String) -> Toasts.show(text, {action: action, duration: 0}));
	}
}
