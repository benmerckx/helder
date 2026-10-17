import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.theme.Shadcn;
import hxmc.ui.*;
import hxmc.ui.draw.*;
import hxmc.ui.widgets.Widgets.*;
import hxmc.ui.widgets.Widgets.MenuItem;
import hxmc.ui.widgets.Toasts;
import hxmc.view.*;

// hxmc's widgets under Shadcn.sheet against shadcn/ui's own markup and CSS
// drawn by Chromium (ref/*.png, ref.mjs; make theme-fidelity-check): each
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
	// hxmc.ui lacks yet): reported, not failed; one that agrees is reported too
	static final KNOWN = [
		"badge-default" => CLIP,
		"badge-destructive" => CLIP,
		"switch-checked" => CLIP,
		"input-value" => "a single-line field's text at the top of its content box, not centred in it as a browser's <input> centres it",
		"radio-group-" => "a <button>'s content is centred vertically by the browser; the item's indicator, at its top here, is not",
		"progress-" => "the indicator is not moved by translateX(-(100 - value)%) as shadcn's, and the widget's own width (160) wins over w-full",
		"slider-" => "Slider and its track carry no data-orientation: data-[orientation=horizontal]:h-1.5 w-full never apply, the track has no size",
		"tabs-" => "Tabs carries no data-orientation (its flex-col, the list's h-9 by group-data-[orientation=horizontal]/tabs) and tabs-list no variant (bg-muted is its default variant's)",
		"toggle-group-outline" => "ToggleGroup and its items carry no data-spacing (shadcn's default, 0): the joined items' rounded-none, first:rounded-l-md, border-l-0 never apply",
		"select-value" => SELECT,
		"select-focus" => SELECT,
		"table-" => "Table's rows a fixed rowHeight for its virtual list, the head's too (shadcn's head h-10, its rows by their padding), its columns 1fr each (shadcn's: a table's auto layout)",
		"breadcrumb-" => "the separator a ▸ glyph at 0.6 opacity, not lucide's chevron-right (size-3.5): the items after it shifted",
		"pagination-" => "Previous and Next without lucide's chevrons, the ellipsis a … glyph, not MoreHorizontal",
		"sheet-" => "the sheet's content placed in its popup's box (at the window's left), not against the window's right edge; popups do not inherit the body's text-base (the title's 16px)",
		"combobox-" => "Combobox's popup is a bare command-list (the slot Command's list has too): shadcn's combobox is a Popover holding a Command, its border, background and shadow theirs",
		"dropdown-menu-open-rtl" => "right to left, an overflow-y-auto box shows a horizontal scrollbar",
	];
	static inline var SELECT = "Select's own width (160) wins over w-fit; the trigger has no size (data-[size=default]:h-9)";
	static inline var CLIP = "background not painted under a transparent border (CSS's background-clip: border-box): 1px smaller each side";

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
			case "tabs" if (c.variant == null): <Tabs labels={["Account", "Password"]} selected={new Signal(0)} render={_ -> "Make changes to your account here."}/>;
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
			case "avatar": <Avatar fallback="CN"/>;
			case "kbd": <Kbd text="Ctrl"/>;
			case "spinner": <Spinner/>;
			case "resizable": <view height={160}><Split first={<view grow={1} align-items="center" justify="center" padding={24}><text font-weight={600}>One</text></view>}
					second={<view grow={1} align-items="center" justify="center" padding={24}><text font-weight={600}>Two</text></view>} size={new Signal(150.0)}/></view>;
			case "calendar": <Calendar value={new Signal({year: 2026, month: 10, day: 12})} today={today} firstDay={0}/>;
			case "toast": <Toaster placement="top-left"/>;
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
			case "dropdown-menu": click(find(ui.root, "button"));
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
			case "skeleton":
				var n = ui.root.find("round");
				n.style.radius = 1e6;
			case "resizable":
				var n = find(ui.root, "resizable-panel-group");
				n.style.set({borderWidth: 1, radius: 10});
			case _:
		}
	}

	// (the node a case's states are on: the component's main slot)
	static final TARGET = ["radio-group" => "radio-group-item", "slider" => "slider-thumb", "tabs" => "tabs-trigger", "select" => "select-trigger"];

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
		var cases:Array<Dynamic> = haxe.Json.parse(sys.io.File.getContent(args[0] + "/cases.json"));
		var device = Device.create(Surface.headless(W, H));
		var r = new Renderer(device);
		var pixels = Bytes.alloc(W * H * 4);
		function draw(ui:Ui) {
			var enc = device.beginFrame();
			var pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 0, 1)}]};
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
			ui.theme = Shadcn.sheet;
			ui.dark = c.dark == true;
			for (n in [ui.root, ui.overlay])
				n.style.set({fontFamily: "Inter", dir: c.rtl == true ? Rtl : Ltr});
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
