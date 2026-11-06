package helder.ui.draw;

import helder.os.objc.*;
import helder.ui.access.AccessNode;
import helder.ui.access.AccessTree;
import helder.ui.access.Role;
import hxmc.unsafe.*;

// A UiWindow's accessibility tree on iOS (UIAccessibility), for VoiceOver,
// Switch Control and UI tests: the window's view (UIKitWindow's) is an
// accessibility container, not an element (methods added to its class at
// run time: isAccessibilityElement, accessibilityElements), whose elements
// are UIAccessibilityElements of a class made here (HxmcAccessibleElement:
// accessibilityActivate, accessibilityIncrement and accessibilityDecrement
// come back as Ui.accessAction), one per node VoiceOver stops at, in the
// tree's order: a control, or a node with no children in the tree (a
// label, an image, a cell); groups and rows only hold them. Each its
// label, value (a text's, a toggle's state, a range's text or percent,
// a tab's selection), hint (the description), traits (button, link,
// image, header, static text, adjustable, selected, not enabled; a text
// input, a search field), and frame in the view's points
// (accessibilityFrameInContainerSpace). Nothing is built until UIKit
// first asks the view for its elements; from then on updated after each
// frame from what changed (AccessTree.changes), UIKit told
// (UIAccessibilityLayoutChangedNotification, with the focused element: the
// cursor moves there); a live region's change is an announcement
// (UIAccessibilityAnnouncementNotification).
class IosAccess {
	static var elementClass = Ptr.nil();
	static final all:Array<IosAccess> = [];
	static var rect:Ptr<CGRect> = Ptr.nil();
	static var traits:Map<String, Int64>;

	final ui:Ui;
	final view:Ptr;
	final elements = new Map<Int, Ptr>();
	final ids = new Map<String, Int>();
	var tree:Null<AccessTree>;
	var active = false;
	// the container's elements (retained)
	var list = Ptr.nil();

	public function new(window:helder.os.Window, ui:Ui) {
		this.ui = ui;
		view = window.surface.handle;
		if (elementClass.isNull()) classes();
		all.push(this);
	}

	// whether UIKit asked for the elements (their changes then sent)
	public function listening():Bool
		return active;

	static function classes() {
		rect = LibC.malloc(32);
		var e = ObjC.cls("HxmcAccessibleElement"), fresh = e.isNull();
		if (fresh) e = Runtime.objc_allocateClassPair(ObjC.cls("UIAccessibilityElement"), Mem.cstr("HxmcAccessibleElement"), 0);
		Runtime.class_replaceMethod(e, ObjC.sel("accessibilityActivate"), Callback.addr(activate), Mem.cstr("B@:"));
		Runtime.class_replaceMethod(e, ObjC.sel("accessibilityIncrement"), Callback.addr(increment), Mem.cstr("v@:"));
		Runtime.class_replaceMethod(e, ObjC.sel("accessibilityDecrement"), Callback.addr(decrement), Mem.cstr("v@:"));
		if (fresh) Runtime.objc_registerClassPair(e);
		elementClass = e;
		// (the traits are UIKit's constants, read where they are: a trait iOS lacks is none)
		traits = new Map();
		for (t in ["Button", "Link", "Image", "Header", "StaticText", "Adjustable", "Selected", "NotEnabled", "SearchField", "UpdatesFrequently", "TabBar", "ToggleButton"]) {
			var p:Ptr<Int64> = Arena.scopedValue(a -> Posix.dlsym(Ptr.ofI64(-2), a.cstring("UIAccessibilityTrait" + t)));
			traits.set(t, p.isNull() ? 0 : p.value);
		}
	}

	// the view a container (once: its class's methods)
	function container() {
		var cls = Runtime.object_getClass(view);
		Runtime.class_replaceMethod(cls, ObjC.sel("isAccessibilityElement"), Callback.addr(notElement), Mem.cstr("B@:"));
		Runtime.class_replaceMethod(cls, ObjC.sel("accessibilityElements"), Callback.addr(viewElements), Mem.cstr("@@:"));
	}

	var made = false;

	// (UiWindow: after each frame)
	public function update() {
		if (!made) {
			made = true;
			container();
		}
		if (!active) return;
		var t = ui.accessTree(), old = tree;
		var c = t.changes(old);
		var focusChanged = old != null && old.focus != t.focus;
		var said = t.announcements(old);
		if (c.nodes.length == 0 && c.removed.length == 0 && !focusChanged && said.length == 0) {
			tree = t;
			return;
		}
		var pool = Runtime.objc_autoreleasePoolPush();
		for (id in c.removed) {
			var e = elements.get(id);
			if (e != null) {
				ids.remove(key(e));
				Runtime.objc_release(e);
				elements.remove(id);
			}
		}
		tree = t;
		for (n in c.nodes)
			if (n.id != t.root && stops(n)) set(element(n.id), n);
		// the elements in order
		var order = [for (id in t.order) if (id != t.root && stops(t.nodes.get(id))) element(id)];
		if (!list.isNull()) Runtime.objc_release(list);
		list = Msg.id(array(order), ObjC.sel("retain"));
		if (old != null) {
			var f = t.focus != 0 && elements.exists(t.focus) ? elements.get(t.focus) : Ptr.nil();
			UIKitAccess.UIAccessibilityPostNotification(notification("UIAccessibilityLayoutChangedNotification"), focusChanged ? f : Ptr.nil());
		}
		for (s in said)
			UIKitAccess.UIAccessibilityPostNotification(notification("UIAccessibilityAnnouncementNotification"), str(s.text));
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// (a notification's number: UIKit's constant)
	static function notification(name:String):Int {
		var p:Ptr<Int32> = Arena.scopedValue(a -> Posix.dlsym(Ptr.ofI64(-2), a.cstring(name)));
		return p.isNull() ? 0 : p.value;
	}

	// whether VoiceOver stops at a node: a control, or one with nothing below it
	static function stops(n:AccessNode):Bool
		return n.children.length == 0 || n.pressable() || n.editable() || n.valueNow != null || n.checked != null || n.role == Image || n.role == Heading
			|| n.role == Link;

	public function dispose() {
		for (e in elements)
			Runtime.objc_release(e);
		elements.clear();
		ids.clear();
		if (!list.isNull()) Runtime.objc_release(list);
		list = Ptr.nil();
		all.remove(this);
	}

	static inline function key(p:Ptr):String
		return Std.string(p.toI64());

	function element(id:Int):Ptr {
		var e = elements.get(id);
		if (e == null) {
			e = Msg.idPtr(Msg.id(elementClass, ObjC.sel("alloc")), ObjC.sel("initWithAccessibilityContainer:"), view);
			elements.set(id, e);
			ids.set(key(e), id);
		}
		return e;
	}

	static function array(items:Array<Ptr>):Ptr
		return Arena.scopedValue(a -> {
			var p:Ptr<Ptr> = a.alloc(8 * (items.length + 1));
			for (i in 0...items.length)
				p[i] = items[i];
			Msg.idPtrInt(ObjC.cls("NSArray"), ObjC.sel("arrayWithObjects:count:"), p, items.length);
		});

	static function str(s:String):Ptr
		return Msg.id(ObjC.str(s), ObjC.sel("autorelease"));

	// what VoiceOver says of its value
	static function valueOf(n:AccessNode):Null<String> {
		if (n.secret) return null;
		if (n.value != null) return n.value;
		if (n.checked != null) return n.mixed ? "mixed" : n.checked ? "1" : "0";
		if (n.valueText != null) return n.valueText;
		if (n.valueNow != null) {
			var lo = n.valueMin ?? 0.0, hi = n.valueMax ?? 1.0;
			return hi > lo ? Math.round((n.valueNow - lo) / (hi - lo) * 100) + "%" : Std.string(n.valueNow);
		}
		if (n.setSize > 0 && n.role != Tab) return '${n.posInSet} of ${n.setSize}';
		return null;
	}

	static function traitsOf(n:AccessNode):Int64 {
		var t:Int64 = 0;
		inline function on(name:String)
			t = t | traits.get(name);
		switch n.role {
			case Button | MenuItem | MenuItemCheckBox | MenuItemRadio | ComboBox | ListBoxOption | RadioButton | Tab | TreeItem: on("Button");
			case CheckBox | Switch: on(traits.get("ToggleButton") != 0 ? "ToggleButton" : "Button");
			case Link: on("Link");
			case Image: on("Image");
			case Heading: on("Header");
			case Label | Cell | ColumnHeader: on("StaticText");
			case Slider | SpinButton: on("Adjustable");
			case ProgressIndicator: on("UpdatesFrequently");
			case TabList: on("TabBar");
			case _:
		}
		if (n.role == Button && n.checked != null && traits.get("ToggleButton") != 0) on("ToggleButton");
		if (n.selected == true || n.checked == true && n.role != CheckBox && n.role != Switch) on("Selected");
		if (n.disabled) on("NotEnabled");
		return t;
	}

	// an element's properties from its node
	function set(e:Ptr, n:AccessNode) {
		Msg.vPtr(e, ObjC.sel("setAccessibilityLabel:"), str(n.name));
		var v = valueOf(n);
		Msg.vPtr(e, ObjC.sel("setAccessibilityValue:"), v == null ? Ptr.nil() : str(v));
		var hint = n.description ?? (n.editable() ? (n.readOnly ? "read only" : "text field") : null);
		Msg.vPtr(e, ObjC.sel("setAccessibilityHint:"), hint == null ? Ptr.nil() : str(hint));
		Msg.vInt(e, ObjC.sel("setAccessibilityTraits:"), traitsOf(n));
		Msg.vPtr(e, ObjC.sel("setAccessibilityIdentifier:"), str("helder-" + n.id));
		// the frame: UI pixels to the view's points
		var b = Msg.rect(view, ObjC.sel("bounds"));
		var k = ui.width > 0 ? b.size.width / ui.width : 1.0;
		rect.value.origin.x = n.x * k;
		rect.value.origin.y = n.y * k;
		rect.value.size.width = n.width * k;
		rect.value.size.height = n.height * k;
		Msg.vRect(e, ObjC.sel("setAccessibilityFrameInContainerSpace:"), rect.value);
	}

	// --- the classes' methods ---

	static function owner(e:Ptr):{a:Null<IosAccess>, id:Int} {
		var k = key(e);
		for (m in all)
			if (m.ids.exists(k)) return {a: m, id: m.ids.get(k)};
		return {a: null, id: 0};
	}

	static function act(e:Ptr, action:helder.ui.access.AccessAction):Bool {
		var o = owner(e);
		return o.a != null && o.a.ui.accessAction(o.id, action);
	}

	@:hxmc.callback static function activate(self:Ptr, cmd:Ptr):Int
		return act(self, Click) ? 1 : 0;

	@:hxmc.callback static function increment(self:Ptr, cmd:Ptr):Void
		act(self, Increment);

	@:hxmc.callback static function decrement(self:Ptr, cmd:Ptr):Void
		act(self, Decrement);

	@:hxmc.callback static function notElement(self:Ptr, cmd:Ptr):Int
		return 0;

	// (the first question builds the tree)
	@:hxmc.callback static function viewElements(self:Ptr, cmd:Ptr):Ptr {
		for (m in all)
			if (m.view == self) {
				if (!m.active) {
					m.active = true;
					m.update();
				}
				return m.list;
			}
		return Ptr.nil();
	}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/UIKit.framework/UIKit") extern class UIKitAccess {
	static function UIAccessibilityPostNotification(notification:Int, argument:Ptr):Void;
}
