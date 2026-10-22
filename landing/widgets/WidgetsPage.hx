#if !macro
#if !js
import hxmc.theme.Shadcn;
import hxmc.ui.draw.UiWindow;
#end
import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.ui.widgets.Widgets.*;

typedef Entry = {name:String, title:String, summary:String, view:Null<Void->View>, popup:Bool};
#end

// The landing page's widgets page (widgets.html): every widget of @hxmc/ui,
// each the example beside it in packages/ui/examples/widgets
// (<Name>Example.hx: its view, its title and summary), on one canvas, under
// @hxmc/theme's shadcn sheet, drawn by this program on the GPU. A search
// hides the cards that do not match (their widgets keep their state), dark
// and right to left at a switch. The same page compiles to JavaScript with
// hxmc.web's DOM renderer (widgets-dom.js): the same widgets as the DOM's
// elements under the theme's CSS, for the page's switch between the two.
// Built ahead by the repository's tool (landing/build/Build.hx), not in the
// browser:
//   -cp landing/widgets -cp packages/ui/examples/widgets (and ui's class paths) -main WidgetsPage
class WidgetsPage #if !macro implements Markup #end {
	#if !macro
	static final ENTRIES:Array<Entry> = examples();

	final query = signal("");
	final dark = signal(false);
	final rtl = signal(false);

	#if js
	// (the DOM's widgets, hxmc.web's renderer: into the page's #wp-dom, under the
	// theme's CSS scoped to .hxmc, dark at the document's .dark class, which
	// the popups in the top layer see too)
	static function main() {
		var root = js.Browser.document.getElementById("wp-dom");
		var page = new WidgetsPage();
		page.dark.value = js.Browser.window.matchMedia("(prefers-color-scheme: dark)").matches;
		effect(() -> js.Browser.document.documentElement.classList.toggle("dark", page.dark.value));
		effect(() -> root.dir = page.rtl.value ? "rtl" : "ltr");
		Render.render(page.view(), root);
	}
	#else
	static function main() {
		var w = new UiWindow("Widgets", 1024, 768);
		w.ui.theme = Shadcn.sheet;
		var page = new WidgetsPage();
		page.dark.value = w.ui.dark;
		effect(() -> w.ui.dark = page.dark.value);
		Render.render(page.view(), w.root);
		UiWindow.run();
	}
	#end

	function new() {}

	function matches(e:Entry):Bool {
		var q = StringTools.trim(query.value.toLowerCase());
		return q == "" || e.title.toLowerCase().indexOf(q) >= 0 || e.summary.toLowerCase().indexOf(q) >= 0;
	}

	function card(e:Entry):View
		return <view display={() -> matches(e) ? "flex" : "none"} width={340} grow={1} shrink={0} max-width={560} align-items="stretch">
			<Card tag={e.name}>
				<CardHeader>
					<CardTitle text={e.title}/>
					<CardDescription text={e.summary}/>
				</CardHeader>
				<CardContent>{example(e)}</CardContent>
			</Card>
		</view>;

	// an example's view; one that opens its popup at start (as the theme's
	// reference images want it) waits for a click: a page of them open would
	// be covered by them
	function example(e:Entry):View {
		if (e.view == null) return <Badge variant="outline" label="drawn only: its example styles plain views the DOM does not take"/>;
		if (!e.popup) return e.view();
		var shown = signal(false);
		return <view>{() -> shown.value ? e.view() : <Button tag={e.name + "-show"} label="Show it" variant="outline" onClick={() -> shown.value = true}/>}</view>;
	}

	function count():String {
		var n = 0;
		for (e in ENTRIES) if (matches(e)) n++;
		return n == ENTRIES.length ? '${ENTRIES.length} widgets' : '$n of ${ENTRIES.length} widgets';
	}

	// (what both renderers take: the title and switches are widgets, their
	// type the theme's; the page around them is the renderer's, below)
	function content():View
		return <view row-gap={20}>
			<view direction="row" wrap align-items="center" justify="space-between" row-gap={12} column-gap={16}>
				<view row-gap={4}>
					<CardTitle text="Widgets"/>
					<text>{() -> count() + " of @hxmc/ui under @hxmc/theme, " + RENDERER}</text>
				</view>
				<view direction="row" wrap align-items="center" column-gap={16} row-gap={8}>
					<view width={220}><Input tag="widgets-search" value={query} placeholder="Search the widgets"/></view>
					<Switch tag="widgets-dark" checked={dark} label="Dark"/>
					<Switch tag="widgets-rtl" checked={rtl} label="Right to left"/>
				</view>
			</view>
			<view direction="row" wrap column-gap={16} row-gap={16} align-items="start">{[for (e in ENTRIES) card(e)]}</view>
		</view>;

	#if js
	static inline final RENDERER = "as the DOM's elements, under the theme's CSS";

	public function view():View
		return content();
	#else
	static inline final RENDERER = "drawn by WebAssembly on the GPU";

	public function view():View
		return <scroll slot="body" grow={1} padding={24} font-family="DejaVu Sans" font-size={14} dir={() -> rtl.value ? "rtl" : "ltr"}>{content()}</scroll>;
	#end
	#end

	// each <Name>Example class beside WidgetExample.hx, by name: its title and
	// summary (its header) and its view (WidgetExamplesTest finds them so)
	static macro function examples():haxe.macro.Expr {
		var dir = haxe.io.Path.directory(haxe.macro.Context.resolvePath("WidgetExample.hx"));
		var names = [
			for (f in sys.FileSystem.readDirectory(dir))
				if (StringTools.endsWith(f, "Example.hx") && f != "WidgetExample.hx") f.substr(0, f.length - 3)
		];
		names.sort(Reflect.compare);
		var header = ~/^\/\/ *(title|summary): *(.*)$/;
		// (the examples that style plain views in ways hxmc.web's NeutralMacro
		// has no DOM form for: background, radius, borders, padding-top, font
		// sizes on <view> and <text>; the DOM's page shows them as drawn only)
		// (the examples that open their popup at start)
		var popups = ["AlertDialogExample", "DialogExample", "DrawerExample", "DropdownMenuExample", "PopoverButtonExample", "SheetExample"];
		var drawnOnly = haxe.macro.Context.defined("js") ? ["AspectRatioExample", "CarouselExample", "ContextMenuExample", "NavigationMenuExample", "SidebarProviderExample", "TooltipExample"] : [];
		var list = [
			for (n in names) {
				var head = new Map<String, String>();
				for (line in sys.io.File.getContent('$dir/$n.hx').split("\n")) {
					if (!StringTools.startsWith(line, "//")) break;
					if (header.match(StringTools.trim(line))) head[header.matched(1)] = StringTools.trim(header.matched(2));
				}
				var name = n.substr(0, n.length - 7);
				var view = drawnOnly.contains(n) ? macro null : macro () -> $i{n}.view();
				macro {name: $v{name}, title: $v{head["title"] ?? name}, summary: $v{head["summary"] ?? ""}, view: $view, popup: $v{popups.contains(n)}};
			}
		];
		return macro $a{list};
	}
}
