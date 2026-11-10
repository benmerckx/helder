// title: Foundry
// summary: Make a font by drawing it: letters as pen lines on guides, one pen for the whole font (weight, contrast, nib angle), letters borrowed from each other (b from d, u from n, é from e), open fonts traced into pen lines to start from, every edit set at once in a real font you type in, exported as a .ttf by helder.text's FontEncoder; agents draw and blend fonts too, over MCP
// tags: ui, view, text, canvas, app, showcase
// demo: canvas 1280x800
import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.ui.menu.Menu;
import helder.ui.view.UiFlow.MenuBarView;
import helder.ui.widgets.Theme;
import helder.view.*;

// Foundry (README.md): a font made by drawing it, for people who never made
// one. Lines are drawn with a pen, not built from points; letters share
// shapes; the font is real from the first line.
class Foundry implements Markup {
	static function main() {
		fonts();
		actions("foundry", FoundryAction);
		Keymap.global.bind("secondary-z", Undo)
			.bind("secondary-shift-z", Redo)
			.bind("p", Draw)
			.bind("v", Adjust)
			.bind("e", Erase)
			.bind("t", Guide)
			.bind("]", Next)
			.bind("[", Previous)
			.bind("secondary-e", Export)
			.bind("secondary-n", NewFont)
			.bind("secondary-=", ZoomIn)
			.bind("secondary-shift-=", ZoomIn)
			.bind("secondary--", ZoomOut)
			.bind("secondary-0", ZoomFit)
			.bind("secondary-1", ZoomActual)
			.bind("secondary-2", ZoomSelection);
		var ws = new Workshop();
		// (the colours given inline follow the appearance chosen, as the sheet's do)
		Theme.appearance = () -> ws.dark();
		#if !(hxmc.target == "wasm32-wasi")
		Mcp.start(ws);
		#end
		UiWindow.run(<Surface title="Foundry" width={1280} height={800} titlebar="inset" theme={Shell.sheet} background={Theme.c("canvas")}
			dark={ws.dark()}>
			<view grow={1} min-height={0} actions={[Actions.handle(FoundryAction, a -> {
				switch a {
					case Undo: ws.undo();
					case Redo: ws.redo();
					case Draw: ws.tool("draw");
					case Adjust: ws.tool("adjust");
					case Erase: ws.tool("erase");
					case Guide: ws.guide(!ws.guide.peek());
					case Next: step(ws, 1);
					case Previous: step(ws, -1);
					case Export: ws.export();
					case Install: ws.install();
					case NewFont: ws.starting(true);
					case ZoomIn: ws.board?.zoomBy(1.5);
					case ZoomOut: ws.board?.zoomBy(1 / 1.5);
					case ZoomFit: ws.board?.fit();
					case ZoomActual: ws.board?.actual();
					case ZoomSelection: ws.board?.zoomToSelection();
					case Appearance(kind): ws.appear(kind);
				}
				true;
			}, a -> switch a {
				case Undo: ws.canUndo.peek() ? Enabled : Disabled;
				case Redo: ws.canRedo.peek() ? Enabled : Disabled;
				case Draw: ws.tool.peek() == "draw" ? Checked : Unchecked;
				case Adjust: ws.tool.peek() == "adjust" ? Checked : Unchecked;
				case Erase: ws.tool.peek() == "erase" ? Checked : Unchecked;
				case Guide: ws.guide.peek() ? Checked : Unchecked;
				case Install: Workshop.canInstall() ? Enabled : Disabled;
				case Appearance(kind): ws.appearance.peek() == kind ? Checked : Unchecked;
				case _: Enabled;
			})]}>
				<MenuBarView menus={menus()}/>
				{Shell.view(ws)}
			</view>
		</Surface>);
	}

	static function step(ws:Workshop, by:Int) {
		var all = Charset.all, i = all.indexOf(ws.current.peek());
		ws.open(all[(i + by + all.length) % all.length]);
	}

	static function menus():Array<Menu>
		return [
			{
				label: "File",
				items: [
					Item("New Font…", NewFont), Separator, Item("Export .ttf", Export), Item("Install Font", Install),
					Separator, Role(Quit)
				]
			},
			{label: "Edit", items: [Item("Undo", Undo), Item("Redo", Redo), Separator, Role(Cut), Role(Copy), Role(Paste), Role(SelectAll)]},
			{
				label: "View",
				items: [
					Item("Draw", Draw), Item("Adjust", Adjust), Item("Erase", Erase), Separator, Item("Zoom In", ZoomIn), Item("Zoom Out", ZoomOut),
					Item("Fit Letter", ZoomFit), Item("Actual Size", ZoomActual), Item("Zoom to Selection", ZoomSelection), Separator,
					Item("Tracing Letter", Guide), Item("Next Glyph", Next),
					Item("Previous Glyph", Previous), Separator,
					Submenu("Appearance", [Item("System", Appearance("system")), Item("Light", Appearance("light")), Item("Dark", Appearance("dark"))])
				]
			},
			{label: "Window", role: Window, items: []}
		];

	// Hanken Grotesk for the interface, Geist Mono for values, Inter to start
	// from (examples/foundry/fonts), Pebble's own
	static function fonts() {
		var f = helder.text.SystemFonts.get();
		for (b in [
			helder.asset.Asset.embed("fonts/HankenGrotesk-Regular.ttf"),
			helder.asset.Asset.embed("fonts/HankenGrotesk-Medium.ttf"),
			helder.asset.Asset.embed("fonts/GeistMono-Regular.ttf"),
			helder.asset.Asset.embed("fonts/Inter.ttf")
		])
			try f.add(b) catch (_:Dynamic) {}
		Start.fonts();
	}
}

enum FoundryAction {
	Undo;
	Redo;
	Draw;
	Adjust;
	Erase;
	Guide;
	Next;
	Previous;
	Export;
	Install;
	NewFont;
	ZoomIn;
	ZoomOut;
	ZoomFit;
	ZoomActual;
	ZoomSelection;
	// "system", "light" or "dark"
	Appearance(kind:String);
}
