import helder.ui.Ui;
import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;
import helder.ui.actions.Keystroke;
import helder.ui.menu.Menu;
import helder.ui.menu.Menus;

// actions(namespace, Enum) in Haxe: shortcuts.tsx prints the same.
enum ViewerAction {
	Next;
	ZoomTo(percent:Float);
	Move(to:{x:Float, y:Float});
	Open(path:String, tags:Array<String>);
}

class Shortcuts implements helder.view.Markup {
	static function show(a:ViewerAction):String
		return switch a {
			case Next: "next";
			case ZoomTo(percent): 'zoomTo $percent';
			case Move(to): 'move ${to.x},${to.y}';
			case Open(path, tags): 'open $path [${tags.join(",")}]';
		}

	static function main() {
		actions("viewer", ViewerAction);
		var log = [], zoomed = false;
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		var ui = new Ui(new helder.story.StoryText(), 200, 200);
		var keymap = new Keymap().bind("n", Next, "Viewer").bind("ctrl-k ctrl-z", ZoomTo(50), "Viewer").bind("1", ZoomTo(100)).bind("q", StandardAction.Quit);
		keymap.setUser('[{"context": "Viewer", "bindings": {"2": ["viewer::ZoomTo", 200], "m": ["viewer::Move", {"x": 3, "y": 4}],
			"o": ["viewer::Open", ["a.png", ["x", "y"]]], "1": null}}]');
		ui.keymap = keymap;
		helder.view.Render.render(<view key-context="Viewer" actions={[Actions.handle(ViewerAction, a -> {
			log.push(show(a));
			if (a.match(ZoomTo(_))) zoomed = !zoomed;
			!a.match(Open(_, _));
		}, a -> switch a {
			case Next: Disabled;
			case ZoomTo(_): zoomed ? Checked : Unchecked;
			case _: Enabled;
		}), Actions.handle(StandardAction, a -> {
			log.push(Actions.name(a));
			true;
		})]}>
			<view tag="image" focusable width={20} height={20}/>
		</view>, ui.root);
		ui.update();
		ui.root.find("image").focus();
		for (keys in ["n", "1", "2", "ctrl-k ctrl-z", "m", "o", "q"])
			for (k in Keystroke.sequence(keys))
				ui.keyDown(k.key, k.held());
		Sys.println(log.join("\n"));
		Sys.println('${ui.dispatchAction(Move({x: 1, y: 2}))} ${ui.dispatchAction(Open("b", []))} ${(ui.actionState(Next) : Int)} ${(ui.actionState(ZoomTo(1)) : Int)}');
		Sys.println([for (b in keymap.bindings()) b.toString()].join("\n"));
		var viewer = [helder.ui.actions.KeyContext.parse("Viewer")];
		Sys.println('${keymap.label(ZoomTo(200), viewer)} ${keymap.label(ZoomTo(50), viewer)} ${keymap.label(ZoomTo(100))} ${keymap.label(StandardAction.Quit)}');
		var parsed = Actions.parse(["viewer::ZoomTo", 7]);
		Sys.println('${Actions.name(parsed)} ${Actions.equals(parsed, ZoomTo(7))} ${Actions.equals(parsed, ZoomTo(8))} ${Actions.name(Actions.parse("standard::Copy"))}');
		for (it in Menus.resolve(ui, [Item("Next", Next), Separator, Item("Zoom", ZoomTo(200)), Item("Open", Open("a.png", ["x", "y"])), Role(Quit)], null, []))
			Sys.println(it.separator == true ? "-" : '${it.label}: ${it.shortcut ?? "-"}, ${it.disabled == true ? "disabled" : "enabled"}'
				+ (it.checked == null ? "" : it.checked ? ", checked" : ", unchecked"));
		// (a menu bar: F10 bound to its own action, menu::OpenMenuBar)
		var bar = new MenuBar(ui, [{label: "View", items: [Item("Zoom", ZoomTo(200))]}]);
		ui.root.insert(bar.node, 0);
		Sys.println(keymap.label(Actions.parse("menu::OpenMenuBar")));
	}
}
