package hxmc.ui.draw;

import hxmc.os.objc.*;
import hxmc.ui.access.AccessNode;
import hxmc.ui.access.AccessTree;
import hxmc.ui.access.Role;
import hxmc.unsafe.*;

// A UiWindow's accessibility tree on macOS (NSAccessibility), for VoiceOver
// and the other assistive technology: each node an NSAccessibilityElement
// (of a class made at run time, HxmcAccessElement, whose press, increment
// and decrement actions come back as Ui.accessAction), its role, label,
// value, states and frame (in screen points) set through the element's
// accessibility properties, its parent and children; the window's view the
// top's parent, of a subclass made at run time (HxmcAccessView) that
// answers its children, which element has the focus and which is under a
// point. Nothing is built until assistive technology first asks the view
// one of those; from then on updated after each frame from what changed
// (AccessTree.changes), all the frames again when the window moved; a live
// region's change is an announcement (AXAnnouncementRequested).
class MacAccess {
	static var elementClass = Ptr.nil();
	static var viewClass = Ptr.nil();
	static final all:Array<MacAccess> = [];
	// a rect passed by value
	static var rect:Ptr<CGRect> = Ptr.nil();

	final ui:Ui;
	final view:Ptr;
	final nsWindow:Ptr;
	final elements = new Map<Int, Ptr>();
	// the element's id, by its address
	final ids = new Map<String, Int>();
	var tree:Null<AccessTree>;
	var windowX = Math.NaN;
	var windowY = Math.NaN;
	// (asked: building; the view's children, retained)
	var active = false;
	var rootChildren = Ptr.nil();

	public function new(window:hxmc.os.Window, ui:Ui) {
		this.ui = ui;
		view = window.surface.handle;
		nsWindow = Msg.id(view, ObjC.sel("window"));
		if (elementClass.isNull()) classes();
		Runtime.object_setClass(view, viewClass);
		all.push(this);
	}

	static function classes() {
		rect = LibC.malloc(32);
		var e = Runtime.objc_allocateClassPair(ObjC.cls("NSAccessibilityElement"), Mem.cstr("HxmcAccessElement"), 0);
		Runtime.class_addMethod(e, ObjC.sel("accessibilityPerformPress"), Callback.addr(press), Mem.cstr("c@:"));
		Runtime.class_addMethod(e, ObjC.sel("accessibilityPerformIncrement"), Callback.addr(increment), Mem.cstr("c@:"));
		Runtime.class_addMethod(e, ObjC.sel("accessibilityPerformDecrement"), Callback.addr(decrement), Mem.cstr("c@:"));
		Runtime.objc_registerClassPair(e);
		elementClass = e;
		var v = Runtime.objc_allocateClassPair(ObjC.cls("NSView"), Mem.cstr("HxmcAccessView"), 0);
		Runtime.class_addMethod(v, ObjC.sel("accessibilityChildren"), Callback.addr(children), Mem.cstr("@@:"));
		Runtime.class_addMethod(v, ObjC.sel("accessibilityFocusedUIElement"), Callback.addr(focused), Mem.cstr("@@:"));
		Runtime.class_addMethod(v, ObjC.sel("accessibilityHitTest:"), Callback.addr(hitTest), Mem.cstr("@@:{CGPoint=dd}"));
		Runtime.objc_registerClassPair(v);
		viewClass = v;
	}

	public function dispose() {
		for (e in elements)
			Runtime.objc_release(e);
		elements.clear();
		ids.clear();
		if (!rootChildren.isNull()) Runtime.objc_release(rootChildren);
		rootChildren = Ptr.nil();
		all.remove(this);
	}

	// the tree after a frame: the elements of what changed made or set again
	public function update() {
		if (!active) return;
		var t = ui.accessTree();
		var wf = Msg.rect(nsWindow, ObjC.sel("frame"));
		var moved = wf.origin.x != windowX || wf.origin.y != windowY;
		windowX = wf.origin.x;
		windowY = wf.origin.y;
		var c = t.changes(moved ? null : tree);
		var focusChanged = tree == null || tree.focus != t.focus;
		if (c.nodes.length == 0 && c.removed.length == 0 && !focusChanged) {
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
		for (n in c.nodes)
			if (n.id != t.root) set(element(n.id), n);
		// parents and children (of the nodes changed: their lists are theirs)
		for (n in c.nodes) {
			var kids = [for (k in n.children) element(k)];
			var parent = n.id == t.root ? view : element(n.id);
			for (k in kids)
				Msg.vPtr(k, ObjC.sel("setAccessibilityParent:"), parent);
			var list = array(kids);
			if (n.id == t.root) {
				if (!rootChildren.isNull()) Runtime.objc_release(rootChildren);
				rootChildren = Msg.id(list, ObjC.sel("retain"));
			}
			Msg.vPtr(parent, ObjC.sel("setAccessibilityChildren:"), list);
		}
		if (focusChanged) {
			var f = t.focus != 0 ? elements.get(t.focus) : null;
			if (tree != null && tree.focus != 0 && elements.exists(tree.focus))
				Msg.vBool(elements.get(tree.focus), ObjC.sel("setAccessibilityFocused:"), false);
			if (f != null) {
				Msg.vBool(f, ObjC.sel("setAccessibilityFocused:"), true);
				post(f, "AXFocusedUIElementChanged");
			}
		}
		if (tree != null) post(view, "AXLayoutChanged");
		// (a live region's change: an announcement, high priority for an assertive one)
		for (s in t.announcements(tree)) {
			var info = Msg.id(ObjC.cls("NSMutableDictionary"), ObjC.sel("dictionary"));
			Msg.idPtrPtr(info, ObjC.sel("setObject:forKey:"), str(s.text), str("AXAnnouncementKey"));
			Msg.idPtrPtr(info, ObjC.sel("setObject:forKey:"), number(s.live == Assertive ? 90 : 50), str("AXPriorityKey"));
			AppKitAccess.NSAccessibilityPostNotificationWithUserInfo(view, str("AXAnnouncementRequested"), info);
		}
		Runtime.objc_autoreleasePoolPop(pool);
		tree = t;
	}

	static inline function key(p:Ptr):String
		return Std.string(p.toI64());

	function element(id:Int):Ptr {
		var e = elements.get(id);
		if (e == null) {
			e = Msg.id(Msg.id(elementClass, ObjC.sel("alloc")), ObjC.sel("init"));
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

	static function str(s:String):Ptr {
		var ns = ObjC.str(s);
		// (autoreleased: the properties retain what they keep)
		return Msg.id(ns, ObjC.sel("autorelease"));
	}

	static function number(v:Float):Ptr
		return Msg.idFloat(ObjC.cls("NSNumber"), ObjC.sel("numberWithDouble:"), v);

	static function post(e:Ptr, notification:String)
		AppKitAccess.NSAccessibilityPostNotification(e, str(notification));

	// an element's properties from its node
	function set(e:Ptr, n:AccessNode) {
		// (a combobox typed in: AppKit's combo box)
		var role = n.role == ComboBox && n.value != null ? "AXComboBox" : macRole(n.role);
		Msg.vPtr(e, ObjC.sel("setAccessibilityRole:"), str(role));
		var sub = switch n.role {
			case Switch: "AXSwitch";
			case Tab: "AXTabButton";
			case Dialog | AlertDialog: "AXApplicationDialog";
			case Navigation: "AXLandmarkNavigation";
			case TextInput if (n.secret): "AXSecureTextField";
			case _: null;
		}
		if (sub != null) Msg.vPtr(e, ObjC.sel("setAccessibilitySubrole:"), str(sub));
		if (n.role == Label) Msg.vPtr(e, ObjC.sel("setAccessibilityValue:"), str(n.name)) else
			Msg.vPtr(e, ObjC.sel("setAccessibilityLabel:"), str(n.name));
		if (n.description != null) Msg.vPtr(e, ObjC.sel("setAccessibilityHelp:"), str(n.description));
		if (n.value != null) Msg.vPtr(e, ObjC.sel("setAccessibilityValue:"), str(n.value));
		if (n.checked != null) Msg.vPtr(e, ObjC.sel("setAccessibilityValue:"), number(n.mixed ? 2 : n.checked ? 1 : 0));
		if (n.valueNow != null) Msg.vPtr(e, ObjC.sel("setAccessibilityValue:"), number(n.valueNow));
		if (n.valueMin != null) Msg.vPtr(e, ObjC.sel("setAccessibilityMinValue:"), number(n.valueMin));
		if (n.valueMax != null) Msg.vPtr(e, ObjC.sel("setAccessibilityMaxValue:"), number(n.valueMax));
		if (n.valueText != null) Msg.vPtr(e, ObjC.sel("setAccessibilityValueDescription:"), str(n.valueText));
		if (n.selected != null) Msg.vBool(e, ObjC.sel("setAccessibilitySelected:"), n.selected);
		if (n.expanded != null) Msg.vBool(e, ObjC.sel("setAccessibilityExpanded:"), n.expanded);
		Msg.vBool(e, ObjC.sel("setAccessibilityEnabled:"), !n.disabled);
		// the frame: the window's points (y up) to the screen's
		var b = Msg.rect(view, ObjC.sel("bounds"));
		var k = ui.width > 0 ? b.size.width / ui.width : 1.0;
		rect.value.origin.x = n.x * k;
		rect.value.origin.y = b.size.height - (n.y + n.height) * k;
		rect.value.size.width = n.width * k;
		rect.value.size.height = n.height * k;
		var s = Msg.rectRect(nsWindow, ObjC.sel("convertRectToScreen:"), Msg.rectRectPtr(view, ObjC.sel("convertRect:toView:"), rect.value, Ptr.nil()));
		rect.value.origin.x = s.origin.x;
		rect.value.origin.y = s.origin.y;
		rect.value.size.width = s.size.width;
		rect.value.size.height = s.size.height;
		Msg.vRect(e, ObjC.sel("setAccessibilityFrame:"), rect.value);
	}

	static function macRole(r:Role):String
		return switch r {
			case Group | TabPanel | ListItem | Dialog | AlertDialog: "AXGroup";
			case Button: "AXButton";
			case CheckBox | Switch: "AXCheckBox";
			case RadioGroup: "AXRadioGroup";
			case RadioButton | Tab: "AXRadioButton";
			case Slider: "AXSlider";
			case ProgressIndicator: "AXProgressIndicator";
			case TextInput: "AXTextField";
			case MultilineTextInput: "AXTextArea";
			case Label: "AXStaticText";
			case Image: "AXImage";
			case TabList: "AXTabGroup";
			case ScrollView: "AXScrollArea";
			case List | ListBox: "AXList";
			case Heading: "AXHeading";
			case Link: "AXLink";
			case Menu: "AXMenu";
			case MenuItem | MenuItemCheckBox | MenuItemRadio: "AXMenuItem";
			case ListBoxOption: "AXStaticText";
			case ComboBox: "AXPopUpButton";
			case Tooltip: "AXHelpTag";
			case Table: "AXTable";
			case Row: "AXRow";
			case Cell | ColumnHeader: "AXCell";
			// (an outline's rows, as AppKit's outline views have them)
			case Tree: "AXOutline";
			case TreeItem: "AXRow";
			case Separator: "AXSplitter";
			case SpinButton: "AXIncrementor";
			case MenuBar: "AXMenuBar";
			case Toolbar: "AXToolbar";
			case Navigation: "AXGroup";
		}

	// --- the classes' methods ---

	static function owner(e:Ptr):{a:Null<MacAccess>, id:Int} {
		var k = key(e);
		for (m in all)
			if (m.ids.exists(k)) return {a: m, id: m.ids.get(k)};
		return {a: null, id: 0};
	}

	static function act(e:Ptr, action:hxmc.ui.access.AccessAction):Int {
		var o = owner(e);
		return o.a != null && o.a.ui.accessAction(o.id, action) ? 1 : 0;
	}

	@:hxmc.callback static function press(self:Ptr, cmd:Ptr):Int
		return act(self, Click);

	@:hxmc.callback static function increment(self:Ptr, cmd:Ptr):Int
		return act(self, Increment);

	@:hxmc.callback static function decrement(self:Ptr, cmd:Ptr):Int
		return act(self, Decrement);

	static function of(view:Ptr):Null<MacAccess> {
		for (m in all)
			if (m.view == view) return m;
		return null;
	}

	// (the first question builds the tree)
	function activate() {
		if (active) return;
		active = true;
		update();
	}

	@:hxmc.callback static function children(self:Ptr, cmd:Ptr):Ptr {
		var m = of(self);
		if (m == null) return Ptr.nil();
		m.activate();
		return m.rootChildren;
	}

	@:hxmc.callback static function focused(self:Ptr, cmd:Ptr):Ptr {
		var m = of(self);
		if (m != null) m.activate();
		if (m == null || m.tree == null || m.tree.focus == 0) return self;
		var e = m.elements.get(m.tree.focus);
		return e == null ? self : e;
	}

	// the deepest element whose frame holds the point (screen points), else the view
	@:hxmc.callback static function hitTest(self:Ptr, cmd:Ptr, x:Float, y:Float):Ptr {
		var m = of(self);
		if (m != null) m.activate();
		if (m == null || m.tree == null) return self;
		var best = self;
		var id = m.tree.root;
		while (true) {
			var n = m.tree.nodes.get(id);
			var next = 0;
			if (n != null)
				for (k in n.children) {
					var e = m.elements.get(k);
					if (e == null) continue;
					var f = Msg.rect(e, ObjC.sel("accessibilityFrame"));
					if (x >= f.origin.x && x < f.origin.x + f.size.width && y >= f.origin.y && y < f.origin.y + f.size.height) {
						next = k;
						best = e;
					}
				}
			if (next == 0) break;
			id = next;
		}
		return best;
	}
}

// AppKit's accessibility function
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/AppKit.framework/AppKit") extern class AppKitAccess {
	static function NSAccessibilityPostNotification(element:Ptr, notification:Ptr):Void;
	static function NSAccessibilityPostNotificationWithUserInfo(element:Ptr, notification:Ptr, userInfo:Ptr):Void;
}
