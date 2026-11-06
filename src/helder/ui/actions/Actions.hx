package helder.ui.actions;

import haxe.macro.Expr;
import helder.ui.actions.JsonType;

// Actions are values of an app's or a library's own types, declared by a
// definition (src/helder/compiler/DESIGN.md 4, its handler ActionsDefinition):
// in Haxe an enum, its constructors the actions and their arguments the
// parameters (GPUI's action types); in TypeScript an object's methods
// (helder/ui/actions, src/helder/ui/actions/index.ts):
//
//   enum ViewerAction { Next; Previous; ZoomIn; ZoomTo(percent:Float); }
//   actions("viewer", ViewerAction);   // "viewer::ZoomTo" in a keymap
//
// The definition is checked when the program is built (the namespace an
// identifier, a string literal, declared once in the program; each
// argument one a JSON keymap can give: numbers, strings, booleans, and
// arrays and structures of these) and made into the actions' names and
// their arguments' readers (ActionSpace): nothing is looked up by
// reflection at run time. It registers them where it is evaluated (once).
//
// A key binding (Keymap) or a menu item (helder.ui.menu) names one; it is
// dispatched through the focus tree (Ui.dispatchAction): the focused node's
// handlers (Node.on), then its ancestors' up to the root (a popup's: on to
// the node it is anchored to), then the window's (Ui.on), then the app's
// (Actions.on): each handles it (true) or lets it bubble (false). A
// handler's state says whether a menu shows its action enabled, checked.
// Declared names are what JSON keymaps use: "viewer::Next",
// ["viewer::ZoomTo", 100] (the arguments, one or an array).
@:definition macro function actions(namespace:Expr, type:Expr):Expr
	return helder.ui.actions.ActionsMacro.make(namespace, type);

#if !macro
// An action: a value of a declared enum (Haxe's) or a program's object
// (TypeScript's: {type: "zoomTo", percent: 100}, Script's)
@:typescript.type("Action")
abstract Action(Dynamic) from EnumValue to Dynamic {}

// What a handler takes: a declared enum (Haxe's, by itself) or the actions
// a definition made (ActionSpace)
abstract ActionType<T>(Dynamic) {
	inline function new(v:Dynamic)
		this = v;

	@:from static inline function ofEnum<T>(e:Enum<T>):ActionType<T>
		return new ActionType(e);

	@:from static inline function ofSpace<T>(s:ActionSpace<T>):ActionType<T>
		return new ActionType(s);

	// its actions (null: an enum not declared yet)
	public function space():Null<ActionSpace<Dynamic>>
		return Std.isOfType(this, ActionSpace) ? this : Actions.spaceOfEnum(this);
}

class Actions {
	static final spaces:Array<ActionSpace<Dynamic>> = [];
	// the app's handlers: after every window's
	public static final app:Array<ActionHandler> = [];

	// (what actions(...) makes: the space, registered once; another of the
	// same namespace is an error)
	public static function register<T>(space:ActionSpace<T>):ActionSpace<T> {
		for (s in spaces)
			if (s.namespace == space.namespace) {
				if (s.origin == space.origin) return cast s;
				throw 'helder.ui: the namespace ${space.namespace} is declared twice (${s.origin}, ${space.origin})';
			}
		spaces.push(cast space);
		return space;
	}

	// (every space, StandardAction's among them)
	static function all():Array<ActionSpace<Dynamic>> {
		Standard.declare();
		return spaces;
	}

	// the actions of a namespace (null: none declared)
	public static function space(namespace:String):Null<ActionSpace<Dynamic>> {
		for (s in all())
			if (s.namespace == namespace) return s;
		return null;
	}

	// (an enum's, when declared)
	public static function spaceOfEnum(e:Dynamic):Null<ActionSpace<Dynamic>> {
		for (s in all())
			if (s.enumType == e) return s;
		return null;
	}

	// the actions a holds and which of them it is (null: an undeclared one's)
	public static function spaceOf(a:Action):Null<ActionSpace<Dynamic>> {
		if (a == null) return null;
		for (s in all())
			if (s.index(a) >= 0) return s;
		return null;
	}

	// the name a keymap gives it: "viewer::ZoomTo"
	public static function name(a:Action):String {
		var s = spaceOf(a);
		if (s == null) throw "helder.ui: an action of no declared actions (actions(namespace, ...)): " + Std.string(a);
		return s.name(s.index(a));
	}

	// an action from a keymap's JSON: "ns::Name" or ["ns::Name", arg] or ["ns::Name", [args]]
	public static function parse(v:Dynamic):Action {
		var name:String, args:Array<Dynamic> = [];
		if (Std.isOfType(v, String)) name = v else if (Std.isOfType(v, Array) && (v : Array<Dynamic>).length >= 1) {
			var a:Array<Dynamic> = v;
			name = a[0];
			if (a.length == 2 && Std.isOfType(a[1], Array)) args = a[1] else args = a.slice(1);
		} else throw "helder.ui: not an action: " + Std.string(v);
		var i = name.indexOf("::");
		if (i < 0) throw "helder.ui: an action is namespace::Name: " + name;
		var s = space(name.substr(0, i));
		if (s == null) throw "helder.ui: no actions declared as " + name.substr(0, i) + " (actions(namespace, ...)), in " + name;
		var c = name.substr(i + 2);
		var k = s.find(c);
		if (k < 0) throw "helder.ui: " + name.substr(0, i) + " has no action " + c;
		return s.read(k, args);
	}

	// the same action: of the same actions, the same one, its arguments equal
	public static function equals(a:Action, b:Action):Bool {
		if (a == b) return true;
		if (a == null || b == null) return false;
		var s = spaceOf(a);
		if (s == null) return Reflect.isEnumValue(a) && Reflect.isEnumValue(b) && Type.enumEq(a, b);
		var i = s.index(a);
		if (s.index(b) != i) return false;
		var x = s.args(a), y = s.args(b), ps = s.actions[i].params;
		for (k in 0...ps.length)
			if (!JsonTypes.equal(ps[k].type, x[k], y[k])) return false;
		return true;
	}

	// a handler of type's actions, for a node's (markup's actions={...}: Node.on's)
	public static inline function handle<T>(type:ActionType<T>, handle:T->Bool, ?state:T->ActionState):ActionHandler
		return ActionHandler.of(type, handle, state);

	// a handler of type's actions, the app's (removed by the function returned)
	public static function on<T>(type:ActionType<T>, handle:T->Bool, ?state:T->ActionState):Void->Void {
		var h = ActionHandler.of(type, handle, state);
		app.push(h);
		return () -> app.remove(h);
	}
}

// The actions a definition declared (actions(namespace, ...)): their names
// and arguments (ActionsDefinition's), and its values: the action a value
// is, its arguments, a value made of them (Haxe's: generated for its enum;
// TypeScript's: its objects, Script's). A Haxe space a TypeScript program
// handles also knows its values as the program's objects (script).
class ActionSpace<T> {
	public final namespace:String;
	public final actions:Array<ActionInfo>;
	// (Haxe's: the enum; TypeScript's: null)
	public final enumType:Null<Enum<Dynamic>>;
	// (where it is declared: a declaration evaluated again registers it once)
	public final origin:String;

	final indexOf:Dynamic->Int;
	final argsOf:Dynamic->Array<Dynamic>;
	final make:(Int, Array<Dynamic>) -> Dynamic;

	// its values as a TypeScript program's objects (a Haxe space's, Script's)
	public var script:Null<ActionForm> = null;

	public function new(namespace, origin, actions, enumType, indexOf, argsOf, make) {
		this.namespace = namespace;
		this.origin = origin;
		this.actions = actions;
		this.enumType = enumType;
		this.indexOf = indexOf;
		this.argsOf = argsOf;
		this.make = make;
	}

	// which of its actions v is (-1: none of its)
	public function index(v:Dynamic):Int {
		var i = indexOf(v);
		return i >= 0 || script == null ? i : script.index(v);
	}

	// v's arguments, in order
	public function args(v:Dynamic):Array<Dynamic>
		return indexOf(v) >= 0 ? argsOf(v) : script.args(v);

	// "viewer::ZoomTo"
	public function name(i:Int):String
		return namespace + "::" + actions[i].name;

	// the action named (ZoomTo), -1: none
	public function find(name:String):Int {
		for (i in 0...actions.length)
			if (actions[i].name == name) return i;
		return -1;
	}

	// action i of args (JSON's: checked, numbers made as its types say)
	public function read(i:Int, args:Array<Dynamic>):T {
		var a = actions[i], what = name(i);
		if (args.length > a.params.length) throw 'helder.ui: $what takes ${a.params.length} argument' + (a.params.length == 1 ? "" : "s") + ', not ${args.length}';
		return make(i, [for (k in 0...a.params.length) JsonTypes.read(a.params[k].type, args[k], '$what\'s ${a.params[k].name}')]);
	}

	// v as its own kind of value (a Haxe enum's: an enum value)
	public function native(v:Dynamic):T {
		if (indexOf(v) >= 0) return v;
		var i = index(v);
		return read(i, script.args(v));
	}

	// v as TypeScript's object (a TypeScript space's own)
	public function toScript(v:Dynamic):Dynamic {
		if (script == null || script.index(v) >= 0) return v;
		var i = indexOf(v);
		return script.make(i, argsOf(v));
	}
}

typedef ActionForm = {index:Dynamic->Int, args:Dynamic->Array<Dynamic>, make:(Int, Array<Dynamic>) -> Dynamic};

// what a menu shows an action as, from the handler that would take it
enum abstract ActionState(Int) to Int {
	// no handler on the path takes it
	var Unhandled;
	var Disabled;
	var Enabled;
	// enabled, a check mark shown (or not: Unchecked)
	var Checked;
	var Unchecked;

	public var enabled(get, never):Bool;

	inline function get_enabled()
		return this >= 2;

	@:from static inline function ofInt(i:Int):ActionState
		return cast i;
}

// a node's, a window's or the app's handler of one kind's actions
class ActionHandler {
	public final type:ActionType<Dynamic>;
	final handle:Dynamic->Bool;
	final stateOf:Null<Dynamic->ActionState>;
	// (a TypeScript program's: its values given as its objects, Script's)
	final script:Bool;
	var resolved:Null<ActionSpace<Dynamic>> = null;

	function new(type, handle, stateOf, script) {
		this.type = type;
		this.handle = handle;
		this.stateOf = stateOf;
		this.script = script;
	}

	public static function of<T>(type:ActionType<T>, handle:T->Bool, ?state:T->ActionState):ActionHandler
		return new ActionHandler(cast type, cast handle, cast state, false);

	// (a TypeScript program's handler)
	public static function ofScript(type:ActionType<Dynamic>, handle:Dynamic->Bool, ?state:Dynamic->ActionState):ActionHandler
		return new ActionHandler(type, handle, state, true);

	function space():Null<ActionSpace<Dynamic>> {
		if (resolved == null) resolved = type.space();
		return resolved;
	}

	public function takes(a:Action):Bool {
		var s = space();
		if (s != null) return s.index(a) >= 0;
		// (an enum not declared: its values)
		return Reflect.isEnumValue(a) && Type.getEnum(a) == cast type;
	}

	// a as the handler takes it
	function value(a:Action):Dynamic {
		var s = space();
		return s == null ? a : script ? s.toScript(a) : s.native(a);
	}

	// (true: taken; false: on to the next)
	public function run(a:Action):Bool
		return handle(value(a));

	public function state(a:Action):ActionState
		return stateOf == null ? Enabled : stateOf(value(a));
}

// the actions every app has, the menus' roles (helder.ui.menu.MenuItem):
// UiWindow handles the window's, the app's macOS's own menu; copying a
// selection Ui's; a text field its editing keys (standard::Quit in a keymap)
enum StandardAction {
	About;
	Quit;
	Hide;
	HideOthers;
	ShowAll;
	CloseWindow;
	Minimize;
	Zoom;
	ToggleFullscreen;
	Undo;
	Redo;
	Cut;
	Copy;
	Paste;
	SelectAll;
}
#end
