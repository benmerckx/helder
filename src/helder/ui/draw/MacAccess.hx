package helder.ui.draw;

import helder.os.objc.*;
import helder.ui.access.AccessNode;
import helder.ui.access.AccessTree;
import helder.ui.access.Role;
import hxmc.unsafe.*;

// A UiWindow's accessibility tree on macOS (NSAccessibility), for VoiceOver
// and the other assistive technology: each node an NSAccessibilityElement
// (of a class made at run time, HxmcAccessElement, whose press, increment
// and decrement actions come back as Ui.accessAction, as do its value,
// focus, expanded and selected states set: their getters read the tree),
// its role, label, help, range, frame (in screen points) set through the
// element's accessibility properties, a text input's characters, selected
// range, selected text and caret's line (its string for a range and line
// for an index answered), a table's rows, columns, selected rows and
// column headers, a row's and an item's index, a cell's row and column,
// its parent and children; the window's view the
// top's parent, of a subclass made at run time (HxmcAccessView) that
// answers its children, which element has the focus and which is under a
// point. Nothing is built until assistive technology first asks the view
// one of those; from then on updated after each frame from what changed
// (AccessTree.changes), all the frames again when the window moved, with
// the notifications of what changed (AXTitleChanged, AXValueChanged,
// AXSelectedTextChanged, AXSelectedRowsChanged or
// AXSelectedChildrenChanged, AXRowCountChanged, AXRowExpanded and
// AXRowCollapsed, AXCreated, AXUIElementDestroyed, AXLayoutChanged); a
// live region's change is an announcement (AXAnnouncementRequested).
@:hxmc.unsafe(gc)
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

	public function new(window:helder.os.Window, ui:Ui) {
		this.ui = ui;
		view = window.surface.handle;
		nsWindow = Msg.id(view, ObjC.sel("window"));
		if (elementClass.isNull()) classes();
		Runtime.object_setClass(view, viewClass);
		all.push(this);
	}

	static function classes() {
		rect = LibC.malloc(32);
		// (hxmc dev's host: the class an earlier build made, its methods this build's)
		var e = ObjC.cls("HxmcAccessElement"), fresh = e.isNull();
		if (fresh) e = Runtime.objc_allocateClassPair(ObjC.cls("NSAccessibilityElement"), Mem.cstr("HxmcAccessElement"), 0);
		Runtime.class_replaceMethod(e, ObjC.sel("accessibilityPerformPress"), Callback.addr(press), Mem.cstr("c@:"));
		Runtime.class_replaceMethod(e, ObjC.sel("accessibilityPerformIncrement"), Callback.addr(increment), Mem.cstr("c@:"));
		Runtime.class_replaceMethod(e, ObjC.sel("accessibilityPerformDecrement"), Callback.addr(decrement), Mem.cstr("c@:"));
		// (the states assistive technology sets: read from the tree, set as actions)
		Runtime.class_replaceMethod(e, ObjC.sel("accessibilityValue"), Callback.addr(value), Mem.cstr("@@:"));
		Runtime.class_replaceMethod(e, ObjC.sel("setAccessibilityValue:"), Callback.addr(setValue), Mem.cstr("v@:@"));
		Runtime.class_replaceMethod(e, ObjC.sel("isAccessibilityFocused"), Callback.addr(isFocused), Mem.cstr("c@:"));
		Runtime.class_replaceMethod(e, ObjC.sel("setAccessibilityFocused:"), Callback.addr(setFocused), Mem.cstr("v@:c"));
		Runtime.class_replaceMethod(e, ObjC.sel("isAccessibilityExpanded"), Callback.addr(isExpanded), Mem.cstr("c@:"));
		Runtime.class_replaceMethod(e, ObjC.sel("setAccessibilityExpanded:"), Callback.addr(setExpanded), Mem.cstr("v@:c"));
		Runtime.class_replaceMethod(e, ObjC.sel("isAccessibilitySelected"), Callback.addr(isSelected), Mem.cstr("c@:"));
		Runtime.class_replaceMethod(e, ObjC.sel("setAccessibilitySelected:"), Callback.addr(setSelected), Mem.cstr("v@:c"));
		Runtime.class_replaceMethod(e, ObjC.sel("accessibilityStringForRange:"), Callback.addr(stringForRange), Mem.cstr("@@:{_NSRange=QQ}"));
		Runtime.class_replaceMethod(e, ObjC.sel("accessibilityLineForIndex:"), Callback.addr(lineForIndex), Mem.cstr("q@:q"));
		if (fresh) Runtime.objc_registerClassPair(e);
		elementClass = e;
		var v = ObjC.cls("HxmcAccessView"), freshView = v.isNull();
		if (freshView) v = Runtime.objc_allocateClassPair(ObjC.cls("NSView"), Mem.cstr("HxmcAccessView"), 0);
		Runtime.class_replaceMethod(v, ObjC.sel("accessibilityChildren"), Callback.addr(children), Mem.cstr("@@:"));
		Runtime.class_replaceMethod(v, ObjC.sel("accessibilityFocusedUIElement"), Callback.addr(focused), Mem.cstr("@@:"));
		Runtime.class_replaceMethod(v, ObjC.sel("accessibilityHitTest:"), Callback.addr(hitTest), Mem.cstr("@@:{CGPoint=dd}"));
		if (freshView) Runtime.objc_registerClassPair(v);
		viewClass = v;
	}

	// whether assistive technology asked for the tree (its changes then posted)
	public function listening():Bool
		return active;

	public function dispose() {
		for (e in elements)
			Runtime.objc_release(e);
		elements.clear();
		ids.clear();
		if (!rootChildren.isNull()) Runtime.objc_release(rootChildren);
		rootChildren = Ptr.nil();
		// (the view a plain NSView again: its methods are this build's code, gone after a dev host's hand-over)
		Runtime.object_setClass(view, ObjC.cls("NSView"));
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
				post(e, "AXUIElementDestroyed");
				ids.remove(key(e));
				Runtime.objc_release(e);
				elements.remove(id);
			}
		}
		var old = tree;
		tree = t;
		for (n in c.nodes)
			if (n.id != t.root) set(element(n.id), n);
		if (old != null && !moved)
			for (n in c.nodes)
				notify(old, n);
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
			// (isAccessibilityFocused reads the tree)
			if (f != null) post(f, "AXFocusedUIElementChanged");
		}
		if (old != null) post(view, "AXLayoutChanged");
		// (a live region's change: an announcement, high priority for an assertive one)
		for (s in t.announcements(old)) {
			var info = Msg.id(ObjC.cls("NSMutableDictionary"), ObjC.sel("dictionary"));
			Msg.idPtrPtr(info, ObjC.sel("setObject:forKey:"), str(s.text), str("AXAnnouncementKey"));
			Msg.idPtrPtr(info, ObjC.sel("setObject:forKey:"), number(s.live == Assertive ? 90 : 50), str("AXPriorityKey"));
			AppKitAccess.NSAccessibilityPostNotificationWithUserInfo(view, str("AXAnnouncementRequested"), info);
		}
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// a node's notifications: what differs from how it was (new: created)
	function notify(old:AccessTree, n:AccessNode) {
		var e = element(n.id), b = old.nodes.get(n.id);
		if (b == null) {
			post(e, "AXCreated");
			return;
		}
		if (b.name != n.name) post(e, "AXTitleChanged");
		if (b.value != n.value || b.valueNow != n.valueNow || b.checked != n.checked || b.mixed != n.mixed) post(e, "AXValueChanged");
		if (b.textStart != n.textStart || b.textEnd != n.textEnd) post(e, "AXSelectedTextChanged");
		if (b.rowCount != n.rowCount) post(e, "AXRowCountChanged");
		if (b.expanded != n.expanded && n.expanded != null && n.role == TreeItem) post(e, n.expanded ? "AXRowExpanded" : "AXRowCollapsed");
		if (b.selected != n.selected && n.selected != null) {
			var parents = tree.parents(), t = tree.ancestor(n.id, Table, parents), p = parents.get(n.id);
			if (t != 0) post(element(t), "AXSelectedRowsChanged") else if (p != null) post(p == tree.root ? view : element(p), "AXSelectedChildrenChanged");
		}
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
		// (the value: accessibilityValue's, from the tree)
		if (n.role != Label) Msg.vPtr(e, ObjC.sel("setAccessibilityLabel:"), str(n.name));
		if (n.description != null) Msg.vPtr(e, ObjC.sel("setAccessibilityHelp:"), str(n.description));
		if (n.valueMin != null) Msg.vPtr(e, ObjC.sel("setAccessibilityMinValue:"), number(n.valueMin));
		if (n.valueMax != null) Msg.vPtr(e, ObjC.sel("setAccessibilityMaxValue:"), number(n.valueMax));
		if (n.valueText != null) Msg.vPtr(e, ObjC.sel("setAccessibilityValueDescription:"), str(n.valueText));
		Msg.vBool(e, ObjC.sel("setAccessibilityEnabled:"), !n.disabled);
		// a text input's characters, selection and caret's line
		if (n.editable() && n.value != null) {
			var s = n.value, len = s.length;
			var from = n.textStart < 0 ? len : n.textStart, to = n.textEnd < 0 ? len : n.textEnd;
			Msg.vInt(e, ObjC.sel("setAccessibilityNumberOfCharacters:"), len);
			Msg.vIntInt(e, ObjC.sel("setAccessibilitySelectedTextRange:"), from, to - from);
			Msg.vPtr(e, ObjC.sel("setAccessibilitySelectedText:"), str(s.substring(from, to)));
			Msg.vIntInt(e, ObjC.sel("setAccessibilityVisibleCharacterRange:"), 0, len);
			Msg.vInt(e, ObjC.sel("setAccessibilityInsertionPointLineNumber:"), lineOf(s, n.caret < 0 ? len : n.caret));
		}
		// a table's rows and columns, a row's index, a cell's row and column, an item's index
		if (n.role == Table) {
			var rows = tree.tableRows(n.id);
			Msg.vInt(e, ObjC.sel("setAccessibilityRowCount:"), n.rowCount);
			Msg.vInt(e, ObjC.sel("setAccessibilityColumnCount:"), n.colCount);
			Msg.vPtr(e, ObjC.sel("setAccessibilityRows:"), array([for (r in rows) element(r.id)]));
			Msg.vPtr(e, ObjC.sel("setAccessibilitySelectedRows:"), array([for (r in rows) if (r.selected == true) element(r.id)]));
			var headers = [for (c in 0...n.colCount) tree.columnHeader(n.id, c)];
			Msg.vPtr(e, ObjC.sel("setAccessibilityColumnHeaderUIElements:"), array([for (h in headers) if (h != null) element(h.id)]));
		}
		if (n.role == Row && n.rowIndex >= 0) Msg.vInt(e, ObjC.sel("setAccessibilityIndex:"), n.rowIndex);
		if ((n.role == Cell || n.role == ColumnHeader) && n.rowIndex >= 0) {
			Msg.vIntInt(e, ObjC.sel("setAccessibilityRowIndexRange:"), n.rowIndex, 1);
			Msg.vIntInt(e, ObjC.sel("setAccessibilityColumnIndexRange:"), n.colIndex, 1);
		}
		if (n.setSize > 0 && n.role != Row) Msg.vInt(e, ObjC.sel("setAccessibilityIndex:"), n.posInSet - 1);
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

	static function act(e:Ptr, action:helder.ui.access.AccessAction):Int {
		var o = owner(e);
		return o.a != null && o.a.ui.accessAction(o.id, action) ? 1 : 0;
	}

	@:hxmc.callback static function press(self:Ptr, cmd:Ptr):Int
		return act(self, Click);

	@:hxmc.callback static function increment(self:Ptr, cmd:Ptr):Int
		return act(self, Increment);

	@:hxmc.callback static function decrement(self:Ptr, cmd:Ptr):Int
		return act(self, Decrement);

	// a UTF-16 index's line (from 0)
	static function lineOf(s:String, i:Int):Int {
		var line = 0;
		for (k in 0...Std.int(Math.min(i, s.length)))
			if (s.charCodeAt(k) == "\n".code) line++;
		return line;
	}

	// an element's node (null: gone)
	static function nodeOf(e:Ptr):Null<{a:MacAccess, n:AccessNode}> {
		var o = owner(e);
		if (o.a == null || o.a.tree == null) return null;
		var n = o.a.tree.nodes.get(o.id);
		return n == null ? null : {a: o.a, n: n};
	}

	// (accessibilityValue: a label's text, a text input's, a toggle's state,
	// a range's value, a tab's or radio's selection, a heading's level)
	@:hxmc.callback static function value(self:Ptr, cmd:Ptr):Ptr {
		var o = nodeOf(self);
		if (o == null) return Ptr.nil();
		var n = o.n;
		if (n.role == Label) return str(n.name);
		if (n.value != null) return str(n.value);
		if (n.checked != null) return number(n.mixed ? 2 : n.checked ? 1 : 0);
		if (n.valueNow != null) return number(n.valueNow);
		if ((n.role == Tab || n.role == RadioButton) && n.selected != null) return number(n.selected ? 1 : 0);
		if (n.role == Heading && n.level != null) return number(n.level);
		return Ptr.nil();
	}

	// (a text input's text set, a range's value: stepped there)
	@:hxmc.callback static function setValue(self:Ptr, cmd:Ptr, v:Ptr):Void {
		var o = nodeOf(self);
		if (o == null || v.isNull()) return;
		var n = o.n;
		if (n.editable() && !n.readOnly) o.a.ui.accessAction(n.id, SetValue, ObjC.string(Msg.id(v, ObjC.sel("description"))) ?? "")
		else if (n.valueNow != null) o.a.ui.accessAction(n.id, SetValue, Std.string(Msg.f(v, ObjC.sel("doubleValue"))));
	}

	@:hxmc.callback static function isFocused(self:Ptr, cmd:Ptr):Int {
		var o = nodeOf(self);
		return o != null && o.a.tree.focus == o.n.id ? 1 : 0;
	}

	@:hxmc.callback static function setFocused(self:Ptr, cmd:Ptr, on:Int):Void {
		var o = nodeOf(self);
		if (o != null && on & 255 != 0) o.a.ui.accessAction(o.n.id, Focus);
	}

	@:hxmc.callback static function isExpanded(self:Ptr, cmd:Ptr):Int {
		var o = nodeOf(self);
		return o != null && o.n.expanded == true ? 1 : 0;
	}

	@:hxmc.callback static function setExpanded(self:Ptr, cmd:Ptr, on:Int):Void {
		var o = nodeOf(self);
		if (o != null) o.a.ui.accessAction(o.n.id, on & 255 != 0 ? Expand : Collapse);
	}

	@:hxmc.callback static function isSelected(self:Ptr, cmd:Ptr):Int {
		var o = nodeOf(self);
		return o != null && o.n.selected == true ? 1 : 0;
	}

	@:hxmc.callback static function setSelected(self:Ptr, cmd:Ptr, on:Int):Void {
		var o = nodeOf(self);
		if (o != null && on & 255 != 0) o.a.ui.accessAction(o.n.id, Select);
	}

	// (the range: an NSRange by value, its location and length)
	@:hxmc.callback static function stringForRange(self:Ptr, cmd:Ptr, at:Int64, length:Int64):Ptr {
		var o = nodeOf(self);
		if (o == null) return Ptr.nil();
		var s = o.n.value ?? o.n.name, from = at.toInt(), to = from + length.toInt();
		if (from < 0 || to > s.length || from > to) return Ptr.nil();
		return str(s.substring(from, to));
	}

	@:hxmc.callback static function lineForIndex(self:Ptr, cmd:Ptr, i:Int64):Int64 {
		var o = nodeOf(self);
		return o == null ? 0 : lineOf(o.n.value ?? o.n.name, i.toInt());
	}

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
