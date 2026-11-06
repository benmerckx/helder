package helder.ui.actions;

import helder.ui.Node;
import helder.ui.Ui;
import helder.ui.actions.Actions;
import helder.ui.actions.JsonType;
import helder.ui.menu.Menu;
import helder.ui.menu.Menus;
import helder.ui.platform.PlatformMenuItem;

// helder.ui.actions for TypeScript programs (helder/ui/actions:
// src/helder/ui/actions/index.ts, which a program imports; this is its
// runtime, helder/ui/actions/runtime). A program's actions are objects,
// {type: "zoomTo", percent: 100}, made and recognised by index.ts's
// functions (each space's form: which action a value is, its arguments, a
// value of them), and its spaces Haxe's (ActionSpace): a definition's
// (define, its handler's output), and StandardAction's, whose values the
// program's handlers are given as its objects (mirror). The rest are
// helder.ui's: handlers, keymaps, dispatch, menus.
class Script {
	// a program's actions(namespace, {...}): its definition's output
	// (ActionsDefinition.toJson), its values the program's (form: which
	// action one is, its arguments, one made of them, two the same)
	public static function define(json:String, index:Dynamic->Int, args:Dynamic->Array<Dynamic>, make:(Int, Array<Dynamic>) -> Dynamic,
			same:(Int, Dynamic, Dynamic) -> Bool):ActionSpace<Dynamic> {
		var d:Dynamic = haxe.Json.parse(json);
		var list:Array<Dynamic> = d.actions;
		var infos:Array<ActionInfo> = [
			for (a in list)
				new ActionInfo(a.name, a.type, [for (p in (a.params : Array<Dynamic>)) new ParamInfo(p.name, JsonTypes.ofData(p.type))])
		];
		var ns:String = d.namespace;
		// (a keymap's arguments checked as the types say, then made the program's)
		function read(i:Int, xs:Array<Dynamic>):Dynamic {
			var a = infos[i];
			for (k in 0...a.params.length)
				JsonTypes.check(a.params[k].type, xs[k], '$ns::${a.name}\'s ${a.params[k].name}');
			return make(i, xs);
		}
		return Actions.register(new ActionSpace<Dynamic>(ns, "ts:" + ns, infos, null, index, args, read, same));
	}

	// StandardAction's actions (standard::Quit...)
	public static function standard():ActionSpace<Dynamic>
		return cast Standard.declare();

	// a space's actions as the definition's output describes them (JSON)
	public static function info(space:ActionSpace<Dynamic>):String
		return ActionsDefinition.toJson({namespace: space.namespace, actions: space.actions});

	// a Haxe space's values as the program's objects (the form index.ts made for it)
	public static function mirror(space:ActionSpace<Dynamic>, index:Dynamic->Int, args:Dynamic->Array<Dynamic>, make:(Int, Array<Dynamic>) -> Dynamic):Void
		if (space.enumType != null) space.script = new ActionForm(index, args, make);

	// a handler of space's actions (for <view actions={...}>): run takes one
	// (true) or lets it bubble (false), state what a menu shows it as
	public static function handle(space:ActionSpace<Dynamic>, run:Dynamic->Bool, ?state:Dynamic->Int):ActionHandler
		return ActionHandler.ofScript(space, run, state == null ? null : a -> (state(a) : ActionState));

	// a node's handler (Node.on: a ref's node), removed by the function returned
	public static function on(node:Node, space:ActionSpace<Dynamic>, run:Dynamic->Bool, ?state:Dynamic->Int):Void->Void {
		var h = handle(space, run, state);
		if (node.actionHandlers == null) node.actionHandlers = [];
		node.actionHandlers.push(h);
		return () -> node.actionHandlers.remove(h);
	}

	// a window's handler (Ui.on), after its tree's
	public static function onWindow(ui:Ui, space:ActionSpace<Dynamic>, run:Dynamic->Bool, ?state:Dynamic->Int):Void->Void {
		var h = handle(space, run, state);
		ui.actionHandlers.push(h);
		return () -> ui.actionHandlers.remove(h);
	}

	// the app's handler (Actions.on), after every window's
	public static function onApp(space:ActionSpace<Dynamic>, run:Dynamic->Bool, ?state:Dynamic->Int):Void->Void {
		var h = handle(space, run, state);
		Actions.app.push(h);
		return () -> Actions.app.remove(h);
	}

	// "viewer::ZoomTo"
	public static function name(action:Dynamic):String
		return Actions.name(action);

	// an action of a keymap's JSON: "viewer::Next", ["viewer::ZoomTo", 100]
	public static function parse(json:String):Dynamic
		return Actions.parse(haxe.Json.parse(json));

	public static function equals(a:Dynamic, b:Dynamic):Bool
		return Actions.equals(a, b);

	// --- keymaps

	// the app's keymap, every window's unless given its own
	public static function global():Keymap
		return Keymap.global;

	public static function keymap():Keymap
		return new Keymap();

	// a default binding (keys "secondary-o", "ctrl-k ctrl-s"; null unbinds them there)
	public static function bind(keymap:Keymap, keys:String, action:Dynamic, ?context:String):Void
		keymap.bind(keys, action, context);

	// a user's JSON keymap, after the defaults
	public static function setUser(keymap:Keymap, json:String):Void
		keymap.setUser(json);

	// a user's keymap file, read again when it changes (UiWindow polls it)
	public static function loadUser(keymap:Keymap, path:String):Void
		keymap.loadUser(path);

	// the keys of action's best binding as a menu shows them ("Ctrl+O"), null: none
	public static function label(keymap:Keymap, action:Dynamic, ?context:String):Null<String>
		return keymap.label(action, context == null ? null : [for (c in context.split(" > ")) KeyContext.parse(c)]);

	// the keymap's bindings as text ("ctrl-k ctrl-s -> viewer::Next in Editor")
	public static function bindings(keymap:Keymap):Array<String>
		return [for (b in keymap.bindings()) b.toString()];

	// on macOS secondary is Command (UiWindow sets it)
	public static function setMac(mac:Bool):Void
		Keymap.mac = mac;

	// --- windows and dispatch

	// the Ui a node is in (a ref's, once mounted: its window's), null: none
	public static function uiOf(node:Node):Null<Ui>
		return node.ui;

	// a Ui of no window (tests), its text helder's own (helder.story's, the same on every system)
	public static function headless(width:Float, height:Float):Ui {
		helder.text.Shaping.engine = helder.text.Shaping.HELDER;
		return new Ui(new helder.story.StoryText(), width, height);
	}

	public static function root(ui:Ui):Node
		return ui.root;

	// content rendered into its root and laid out (dispose removes it)
	public static function mount(ui:Ui, content:helder.view.View):Void->Void {
		var dispose = helder.view.Render.render(content, ui.root);
		ui.update();
		return dispose;
	}

	public static function setKeymap(ui:Ui, keymap:Keymap):Void
		ui.keymap = keymap;

	public static function layout(ui:Ui):Void
		ui.update();

	// the focus given to node
	public static function focus(node:Node):Void
		node.focus();

	// the node of a tag under node (the first, depth first), null: none
	public static function find(node:Node, tag:String):Null<Node>
		return node.find(tag);

	// each keystroke of keys typed ("ctrl-k ctrl-s"), through the keymap
	public static function type(ui:Ui, keys:String):Void
		for (k in Keystroke.sequence(keys))
			ui.keyDown(k.key, k.held());

	// action dispatched from the focus (or from), true: a handler took it
	public static function dispatch(ui:Ui, action:Dynamic, ?from:Node):Bool
		return ui.dispatchAction(action, from);

	// what a menu shows action as from the focus (or from): ActionState
	public static function state(ui:Ui, action:Dynamic, ?from:Node):Int
		return ui.actionState(action, from);

	// --- menus

	public static function item(label:String, action:Dynamic):MenuItem
		return Item(label, action);

	public static function separator():MenuItem
		return Separator;

	public static function submenu(label:String, items:Array<MenuItem>):MenuItem
		return Submenu(label, items);

	// a standard item ("about", "quit", "copy"...: MenuRole's), its label the platform's unless given
	public static function role(role:String, ?label:String):MenuItem
		return Role(cast role, label);

	// a menu of the bar (role "window": the window menu)
	public static function menu(label:String, items:Array<MenuItem>, ?role:String):Menu
		return role == null ? {label: label, items: items} : {label: label, items: items, role: cast role};

	// the items as the platform's menus take them: labels, shortcuts, states
	public static function resolve(ui:Ui, items:Array<MenuItem>, ?from:Node):Array<PlatformMenuItem>
		return Menus.resolve(ui, items, from, []);

	// a context menu at x, y for from (default: the focus)
	public static function popup(ui:Ui, items:Array<MenuItem>, x:Float, y:Float, ?from:Node):Void
		Menus.popup(ui, items, x, y, from);

	// the window's menu bar (the platform's, else drawn at the top of its root)
	public static function menuBar(ui:Ui, menus:Array<Menu>):MenuBar {
		var bar = new MenuBar(ui, menus);
		ui.root.insert(bar.node, 0);
		return bar;
	}

	public static function setMenus(bar:MenuBar, menus:Array<Menu>):Void
		bar.setMenus(menus);
}

