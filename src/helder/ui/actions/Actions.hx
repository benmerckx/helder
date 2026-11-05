package helder.ui.actions;

// Actions are values of an enum, an app's or a library's own, its
// constructors the actions and their arguments the parameters (GPUI's
// action types):
//
//   enum ViewerAction { Next; Previous; ZoomIn; ZoomTo(percent:Float); }
//   Actions.declare("viewer", ViewerAction);   // "viewer::ZoomTo" in a keymap
//
// A key binding (Keymap) or a menu item (helder.ui.menu) names one; it is
// dispatched through the focus tree (Ui.dispatchAction): the focused node's
// handlers (Node.on), then its ancestors' up to the root (a popup's: on to
// the node it is anchored to), then the window's (Ui.on), then the app's
// (Actions.on): each handles it (true) or lets it bubble (false). A
// handler's state says whether a menu shows its action enabled, checked.
// Declared names are what JSON keymaps use: "viewer::Next",
// ["viewer::ZoomTo", 100] (the arguments, one or an array).
class Actions {
	// (namespace => enum, an enum's name => namespace)
	static final enums:Map<String, Enum<Dynamic>> = [];
	static final spaces:Map<String, String> = [];
	// the app's handlers: after every window's
	public static final app:Array<ActionHandler> = [];

	// names an enum's actions namespace::Constructor (its names in keymaps)
	public static function declare(namespace:String, e:Enum<Dynamic>) {
		enums.set(namespace, e);
		spaces.set(Type.getEnumName(e), namespace);
	}

	// the name a keymap gives it: "viewer::ZoomTo" (an undeclared enum's: its full name)
	public static function name(a:EnumValue):String {
		var e = Type.getEnumName(Type.getEnum(a));
		return (spaces.exists(e) ? spaces.get(e) : e) + "::" + Type.enumConstructor(a);
	}

	// an action from a keymap's JSON: "ns::Name" or ["ns::Name", arg] or ["ns::Name", [args]]
	public static function parse(v:Dynamic):EnumValue {
		var name:String, args:Array<Dynamic> = [];
		if (Std.isOfType(v, String)) name = v else if (Std.isOfType(v, Array) && (v : Array<Dynamic>).length >= 1) {
			var a:Array<Dynamic> = v;
			name = a[0];
			if (a.length == 2 && Std.isOfType(a[1], Array)) args = a[1] else args = a.slice(1);
		} else throw "helder.ui: not an action: " + Std.string(v);
		var i = name.indexOf("::");
		if (i < 0) throw "helder.ui: an action is namespace::Name: " + name;
		var e = enums.get(name.substr(0, i));
		if (e == null) throw "helder.ui: no actions declared as " + name.substr(0, i) + " (Actions.declare), in " + name;
		var c = name.substr(i + 2);
		if (!Type.getEnumConstructs(e).contains(c)) throw "helder.ui: " + name.substr(0, i) + " has no action " + c;
		return Type.createEnum(e, c, args);
	}

	public static inline function equals(a:EnumValue, b:EnumValue):Bool
		return Type.enumEq(a, b);

	// a handler of e's actions, for a node's (markup's actions={...}: Node.on's)
	public static inline function handle<T:EnumValue>(e:Enum<T>, handle:T->Bool, ?state:T->ActionState):ActionHandler
		return ActionHandler.of(e, handle, state);

	// a handler of e's actions, the app's (removed by the function returned)
	public static function on<T:EnumValue>(e:Enum<T>, handle:T->Bool, ?state:T->ActionState):Void->Void {
		var h = ActionHandler.of(e, handle, state);
		app.push(h);
		return () -> app.remove(h);
	}
}

// what a menu shows an action as, from the handler that would take it
enum abstract ActionState(Int) {
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
}

// a node's, a window's or the app's handler of one enum's actions
class ActionHandler {
	public final type:Enum<Dynamic>;
	final handle:Dynamic->Bool;
	final stateOf:Null<Dynamic->ActionState>;

	function new(type, handle, stateOf) {
		this.type = type;
		this.handle = handle;
		this.stateOf = stateOf;
	}

	public static function of<T:EnumValue>(e:Enum<T>, handle:T->Bool, ?state:T->ActionState):ActionHandler
		return new ActionHandler(cast e, cast handle, cast state);

	public inline function takes(a:EnumValue):Bool
		return Type.getEnum(a) == type;

	// (true: taken; false: on to the next)
	public function run(a:EnumValue):Bool
		return handle(a);

	public function state(a:EnumValue):ActionState
		return stateOf == null ? Enabled : stateOf(a);
}

// the actions every app has, the menus' roles (helder.ui.menu.MenuItem):
// UiWindow handles the window's, the app's macOS's own menu; copying a
// selection Ui's; a text field its editing keys
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
