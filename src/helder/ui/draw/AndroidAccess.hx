package helder.ui.draw;

import helder.os.android.Jni;
import helder.os.android.Jni.JniEnv;
import helder.os.android.MainThread;
import helder.ui.access.AccessAction;
import helder.ui.access.AccessNode;
import helder.ui.access.AccessTree;
import helder.ui.access.Role;
import hxmc.unsafe.*;

// A UiWindow's accessibility tree on Android, for TalkBack, Switch Access
// and uiautomator: NativeActivity's content view (the window's one view)
// gets an AccessibilityDelegate whose AccessibilityNodeProvider
// (org.hxmc.AccessDelegate and org.hxmc.AccessProvider of classes.dex,
// helder.pack.android.Glue: their methods are natives registered here)
// gives each node as a virtual view of it: its AccessibilityNodeInfo (the
// class of the widget it is, its text or content description, bounds on
// the screen, parent and children in the tree's order, which TalkBack
// follows; enabled, focusable, focused, accessibility-focused, clickable,
// checkable and checked, selected, editable, a password, its text's
// selection, a heading, a range's RangeInfo, a list's or table's
// CollectionInfo and an item's or cell's CollectionItemInfo, a live
// region, the actions it takes). The provider runs on the main thread,
// reading the tree the program's thread published after its last frame;
// the actions asked (click, focus, select, expand, collapse, set text, set
// selection, scroll forward and back: a range stepped) wait for the
// program's thread (dispatch: UiWindow.pollAccess), accessibility focus is
// the provider's own (its events sent). After each frame, once a service
// asked: the window's content changed (TYPE_WINDOW_CONTENT_CHANGED), the
// focus moved (TYPE_VIEW_FOCUSED), a live region's text announced.
@:hxmc.android
@:hxmc.unsafe(gc)
class AndroidAccess {
	static inline var HOST = -1;
	static var current:Null<AndroidAccess> = null;
	// (the main thread's)
	static var host = Ptr.nil();
	static var provider = Ptr.nil();
	static var delegate = Ptr.nil();
	static var a11yFocus = 0;
	static final methods = new Map<String, Ptr>();
	static var jargs:Ptr = Ptr.nil();
	static var location:Ptr = Ptr.nil();
	static var asked = false;
	// (asked, nothing published yet: a frame wanted, UiWindow.needsFrame's)
	public static var pending = false;
	// where the delegate went (tests): "" until it did
	public static var state = "";
	static final lock = new sys.thread.Mutex();
	static var queue:Array<{id:Int, action:AccessAction, value:Null<String>}> = [];

	final ui:Ui;
	final window:helder.os.Window;
	// the tree the main thread reads, its parents, pixels per UI pixel
	var published:Null<AccessTree> = null;
	var parents = new Map<Int, Int>();
	var scale = 1.0;
	var tree:Null<AccessTree> = null;

	public function new(window:helder.os.Window, ui:Ui) {
		this.window = window;
		this.ui = ui;
		current = this;
		MainThread.post(install);
	}

	// whether a service asked (the tree's changes then published)
	public function listening():Bool
		return asked;

	public function dispose() {
		if (current == this) current = null;
	}

	// (the main thread) the delegate on the content view
	static function install() {
		if (!host.isNull()) return;
		// (NativeActivity's NativeContentView, the content's one child; else the window's decor view)
		var content = Jni.obj(Jni.activity, m("android.app.Activity", "findViewById", "(I)Landroid/view/View;"), 0x1020002); // android.R.id.content
		var v = content.isNull() ? Ptr.nil() : Jni.int(content, m("android.view.ViewGroup", "getChildCount", "()I")) > 0 ? Jni.obj(content,
			m("android.view.ViewGroup", "getChildAt", "(I)Landroid/view/View;"), 0) : content;
		if (v.isNull()) {
			var win = Jni.obj(Jni.activity, m("android.app.Activity", "getWindow", "()Landroid/view/Window;"));
			v = win.isNull() ? Ptr.nil() : Jni.obj(win, m("android.view.Window", "getDecorView", "()Landroid/view/View;"));
		}
		if (v.isNull()) {
			state = "no view";
			return;
		}
		host = Jni.global(v);
		state = "on " + Jni.fromString(Jni.obj(Jni.obj(v, m("java.lang.Object", "getClass", "()Ljava/lang/Class;")), m("java.lang.Class", "getName",
			"()Ljava/lang/String;")));
		var p = cls("org.hxmc.AccessProvider"), d = cls("org.hxmc.AccessDelegate");
		Jni.registerNatives(p, [
			{name: "createAccessibilityNodeInfo", sig: "(I)Landroid/view/accessibility/AccessibilityNodeInfo;", fn: Callback.addr(nodeInfo)},
			{name: "performAction", sig: "(IILandroid/os/Bundle;)Z", fn: Callback.addr(performAction)},
			{name: "findFocus", sig: "(I)Landroid/view/accessibility/AccessibilityNodeInfo;", fn: Callback.addr(findFocus)}
		]);
		Jni.registerNatives(d, [
			{
				name: "getAccessibilityNodeProvider",
				sig: "(Landroid/view/View;)Landroid/view/accessibility/AccessibilityNodeProvider;",
				fn: Callback.addr(nodeProvider)
			}
		]);
		provider = Jni.global(Jni.newObject(p, Jni.method(p, "<init>", "()V")));
		delegate = Jni.global(Jni.newObject(d, Jni.method(d, "<init>", "()V")));
		Jni.call(host, m("android.view.View", "setAccessibilityDelegate", "(Landroid/view/View$AccessibilityDelegate;)V"), delegate.toI64());
		// (the host's own importance: yes, its virtual children are what is read)
		Jni.call(host, m("android.view.View", "setImportantForAccessibility", "(I)V"), 1);
	}

	static function cls(name:String):Ptr
		return Jni.cls(name);

	// a method by its class's Java name, kept
	static function m(c:String, name:String, sig:String):Ptr {
		var k = c + "." + name + sig;
		var r = methods.get(k);
		if (r == null) {
			r = Jni.method(cls(c), name, sig);
			methods.set(k, r);
		}
		return r;
	}

	static function sm(c:String, name:String, sig:String):Ptr {
		var k = "static " + c + "." + name + sig;
		var r = methods.get(k);
		if (r == null) {
			r = Jni.staticMethod(cls(c), name, sig);
			methods.set(k, r);
		}
		return r;
	}

	// a method that may not be there (a newer API's): null then
	static function maybe(c:String, name:String, sig:String):Ptr
		return try m(c, name, sig) catch (e:Dynamic) Ptr.nil();

	// --- the program's thread ---

	// the tree after a frame: published, the events of what changed
	public function update() {
		if (!asked) return;
		pending = false;
		var t = ui.accessTree(), old = tree;
		var c = t.changes(old);
		if (old != null && c.nodes.length == 0 && c.removed.length == 0 && old.focus == t.focus) return;
		var ps = t.parents();
		var k = ui.width > 0 ? window.surface.width / ui.width : 1.0;
		var said = t.announcements(old);
		var focusMoved = old != null && old.focus != t.focus ? t.focus : 0;
		tree = t;
		MainThread.post(() -> {
			parents = ps;
			scale = k;
			published = t;
			event(2048, HOST); // TYPE_WINDOW_CONTENT_CHANGED
			if (focusMoved != 0) event(8, focusMoved); // TYPE_VIEW_FOCUSED
			if (enabled()) for (s in said)
				Jni.call(host, m("android.view.View", "announceForAccessibility", "(Ljava/lang/CharSequence;)V"), Jni.string(s.text).toI64());
		});
	}

	// the actions asked on the main thread, done (each loop turn)
	public static function dispatch() {
		if (current == null) return;
		lock.acquire();
		var q = queue;
		queue = [];
		lock.release();
		for (a in q)
			current.ui.accessAction(a.id, a.action, a.value);
	}

	// --- the main thread ---

	static function ask(id:Int, action:AccessAction, ?value:String):Bool {
		lock.acquire();
		queue.push({id: id, action: action, value: value});
		lock.release();
		MainThread.wake();
		return true;
	}

	// an event of a virtual view (HOST: the content view's own)
	static var manager = Ptr.nil();

	// (whether a service listens: the system refuses events otherwise)
	static function enabled():Bool {
		if (manager.isNull()) {
			var m = Jni.obj(Jni.activity, m("android.content.Context", "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;"), Jni.string("accessibility").toI64());
			if (m.isNull()) return false;
			manager = Jni.global(m);
		}
		return Jni.bool(manager, m("android.view.accessibility.AccessibilityManager", "isEnabled", "()Z"));
	}

	static function event(type:Int, id:Int) {
		if (host.isNull() || !enabled()) return;
		var e = Jni.staticObj(cls("android.view.accessibility.AccessibilityEvent"), sm("android.view.accessibility.AccessibilityEvent", "obtain",
			"(I)Landroid/view/accessibility/AccessibilityEvent;"), type);
		Jni.call(e, m("android.view.accessibility.AccessibilityRecord", "setSource", "(Landroid/view/View;I)V"), host.toI64(), id);
		Jni.call(e, m("android.view.accessibility.AccessibilityRecord", "setClassName", "(Ljava/lang/CharSequence;)V"), Jni.string("android.view.View").toI64());
		Jni.call(e, m("android.view.accessibility.AccessibilityEvent", "setPackageName", "(Ljava/lang/CharSequence;)V"),
			Jni.obj(Jni.activity, m("android.content.Context", "getPackageName", "()Ljava/lang/String;")).toI64());
		if (type == 2048) Jni.call(e, m("android.view.accessibility.AccessibilityEvent", "setContentChangeTypes", "(I)V"), 1); // CONTENT_CHANGE_TYPE_SUBTREE
		var parent = Jni.obj(host, m("android.view.View", "getParent", "()Landroid/view/ViewParent;"));
		if (!parent.isNull())
			Jni.bool(parent, m("android.view.ViewParent", "requestSendAccessibilityEvent", "(Landroid/view/View;Landroid/view/accessibility/AccessibilityEvent;)Z"),
				host.toI64(), e.toI64());
	}

	static function className(n:AccessNode):String
		return switch n.role {
			case Button | Tab | MenuItem | MenuItemRadio | ListBoxOption | Link | TreeItem: n.checked != null && n.role == Button ? "android.widget.ToggleButton" : "android.widget.Button";
			case CheckBox | MenuItemCheckBox: "android.widget.CheckBox";
			case Switch: "android.widget.Switch";
			case RadioButton: "android.widget.RadioButton";
			case Slider: "android.widget.SeekBar";
			case ProgressIndicator: "android.widget.ProgressBar";
			case TextInput | MultilineTextInput: "android.widget.EditText";
			case Label | Heading | Cell | ColumnHeader: "android.widget.TextView";
			case Image: "android.widget.ImageView";
			case List | ListBox | Tree | Menu: "android.widget.ListView";
			case Table: "android.widget.GridView";
			case TabList: "android.widget.TabWidget";
			case ComboBox: "android.widget.Spinner";
			case ScrollView: "android.widget.ScrollView";
			case _: "android.view.ViewGroup";
		}

	// the screen's pixels of the content view's top left
	static function origin():Array<Int> {
		if (location.isNull()) location = Jni.global(JniArrays.NewIntArray(Jni.env, 2));
		Jni.call(host, m("android.view.View", "getLocationOnScreen", "([I)V"), location.toI64());
		return Arena.scopedValue(a -> {
			var p:Ptr<Int32> = a.alloc(8);
			JniArrays.GetIntArrayRegion(Jni.env, location, 0, 2, p);
			[p[0], p[1]];
		});
	}

	static function rect(l:Int, t:Int, r:Int, b:Int):Ptr {
		var c = cls("android.graphics.Rect");
		return Jni.newObject(c, m("android.graphics.Rect", "<init>", "(IIII)V"), l, t, r, b);
	}

	// a static call of five arguments (jvalue each)
	static function static5(c:String, name:String, sig:String, a:Int64, b:Int64, cc:Int64, d:Int64, e:Int64):Ptr {
		if (jargs.isNull()) jargs = LibC.malloc(64);
		Mem.setI64(jargs, 0, a);
		Mem.setI64(jargs, 8, b);
		Mem.setI64(jargs, 16, cc);
		Mem.setI64(jargs, 24, d);
		Mem.setI64(jargs, 32, e);
		var r = JniEnv.CallStaticObjectMethodA(Jni.env, cls(c), sm(c, name, sig), jargs);
		Jni.check();
		return r;
	}

	static inline var INFO = "android.view.accessibility.AccessibilityNodeInfo";

	static function set(info:Ptr, name:String, sig:String, a:Int64 = 0, b:Int64 = 0) {
		var f = maybe(INFO, name, sig);
		if (!f.isNull()) Jni.call(info, f, a, b);
	}

	static inline function flag(info:Ptr, name:String, on:Bool)
		set(info, name, "(Z)V", Jni.z(on));

	// a virtual view's AccessibilityNodeInfo (null: none)
	static function info(id:Int):Ptr {
		var a = current;
		var t = a == null ? null : a.published;
		var nodeInfo = cls(INFO);
		if (id == HOST) {
			var info = Jni.staticObj(nodeInfo, sm(INFO, "obtain", "(Landroid/view/View;)L" + INFO.split(".").join("/") + ";"), host.toI64());
			Jni.call(host, m("android.view.View", "onInitializeAccessibilityNodeInfo", "(L" + INFO.split(".").join("/") + ";)V"), info.toI64());
			if (t != null)
				for (k in t.nodes.get(t.root).children)
					Jni.call(info, m(INFO, "addChild", "(Landroid/view/View;I)V"), host.toI64(), k);
			return info;
		}
		if (t == null) return Ptr.nil();
		var n = t.nodes.get(id);
		if (n == null) return Ptr.nil();
		var info = Jni.staticObj(nodeInfo, sm(INFO, "obtain", "(Landroid/view/View;I)L" + INFO.split(".").join("/") + ";"), host.toI64(), id);
		Jni.call(info, m(INFO, "setPackageName", "(Ljava/lang/CharSequence;)V"), Jni.obj(Jni.activity, m("android.content.Context", "getPackageName",
			"()Ljava/lang/String;")).toI64());
		Jni.call(info, m(INFO, "setClassName", "(Ljava/lang/CharSequence;)V"), Jni.string(className(n)).toI64());
		var p = a.parents.get(id);
		if (p == null || p == t.root) Jni.call(info, m(INFO, "setParent", "(Landroid/view/View;)V"), host.toI64()) else
			Jni.call(info, m(INFO, "setParent", "(Landroid/view/View;I)V"), host.toI64(), p);
		for (k in n.children)
			Jni.call(info, m(INFO, "addChild", "(Landroid/view/View;I)V"), host.toI64(), k);
		// its text: a text input's, a label's, a control's name; else its name as a description
		var cs = "(Ljava/lang/CharSequence;)V";
		if (n.editable()) {
			Jni.call(info, m(INFO, "setText", cs), Jni.string(n.value ?? "").toI64());
			var hint = maybe(INFO, "setHintText", cs);
			if (!hint.isNull()) Jni.call(info, hint, Jni.string(n.name).toI64()) else Jni.call(info, m(INFO, "setContentDescription", cs), Jni.string(n.name).toI64());
		} else if (n.name != "" && (n.role == Label || n.role == Heading || n.role.namedByContent())) Jni.call(info, m(INFO, "setText", cs), Jni.string(n.name).toI64())
		else if (n.name != "") Jni.call(info, m(INFO, "setContentDescription", cs), Jni.string(n.name).toI64());
		if (n.description != null) set(info, "setTooltipText", cs, Jni.string(n.description).toI64());
		// bounds: the screen's pixels, and the parent's (the host's)
		var o = origin(), k = a.scale;
		var l = Math.round(n.x * k), tp = Math.round(n.y * k), r = Math.round((n.x + n.width) * k), b = Math.round((n.y + n.height) * k);
		Jni.call(info, m(INFO, "setBoundsInParent", "(Landroid/graphics/Rect;)V"), rect(l, tp, r, b).toI64());
		Jni.call(info, m(INFO, "setBoundsInScreen", "(Landroid/graphics/Rect;)V"), rect(o[0] + l, o[1] + tp, o[0] + r, o[1] + b).toI64());
		flag(info, "setVisibleToUser", true);
		flag(info, "setEnabled", !n.disabled);
		flag(info, "setFocusable", n.focusable);
		flag(info, "setFocused", t.focus == id);
		flag(info, "setAccessibilityFocused", a11yFocus == id);
		flag(info, "setClickable", n.pressable());
		if (n.checked != null) {
			flag(info, "setCheckable", true);
			flag(info, "setChecked", n.checked);
		}
		if (n.selected != null) flag(info, "setSelected", n.selected);
		if (n.editable()) {
			flag(info, "setEditable", !n.readOnly);
			flag(info, "setPassword", n.secret);
			flag(info, "setMultiLine", n.role == MultilineTextInput);
			if (n.textStart >= 0) set(info, "setTextSelection", "(II)V", n.textStart, n.textEnd);
		}
		if (n.role == Heading) flag(info, "setHeading", true);
		if (n.live != Off) set(info, "setLiveRegion", "(I)V", n.live == Assertive ? 2 : 1);
		// a range, a collection, an item of one
		if (n.valueNow != null) {
			var ri = "android.view.accessibility.AccessibilityNodeInfo$RangeInfo";
			var info2 = Jni.staticObj(cls(ri), sm(ri, "obtain", "(IFFF)Landroid/view/accessibility/AccessibilityNodeInfo$RangeInfo;"), 1, Jni.f(n.valueMin ?? 0),
				Jni.f(n.valueMax ?? 1), Jni.f(n.valueNow));
			Jni.call(info, m(INFO, "setRangeInfo", "(Landroid/view/accessibility/AccessibilityNodeInfo$RangeInfo;)V"), info2.toI64());
		}
		var ci = "android.view.accessibility.AccessibilityNodeInfo$CollectionInfo";
		if (n.role == Table || n.role == List || n.role == ListBox || n.role == Tree || n.role == TabList || n.role == RadioGroup) {
			var rows = n.role == Table ? n.rowCount : n.children.length, cols = n.role == Table ? n.colCount : 1;
			var c = Jni.staticObj(cls(ci), sm(ci, "obtain", "(IIZ)Landroid/view/accessibility/AccessibilityNodeInfo$CollectionInfo;"), rows, cols,
				Jni.z(n.role == Tree));
			Jni.call(info, m(INFO, "setCollectionInfo", "(Landroid/view/accessibility/AccessibilityNodeInfo$CollectionInfo;)V"), c.toI64());
		}
		var cii = "android.view.accessibility.AccessibilityNodeInfo$CollectionItemInfo";
		var row = -1, col = 0;
		if ((n.role == Cell || n.role == ColumnHeader) && n.rowIndex >= 0) {
			row = n.rowIndex;
			col = n.colIndex;
		} else if (n.role == Row && n.rowIndex >= 0) row = n.rowIndex else if (n.setSize > 0) row = n.posInSet - 1;
		if (row >= 0) {
			var c = static5(cii, "obtain", "(IIIIZ)Landroid/view/accessibility/AccessibilityNodeInfo$CollectionItemInfo;", row, 1, col, 1, Jni.z(n.role == ColumnHeader));
			Jni.call(info, m(INFO, "setCollectionItemInfo", "(Landroid/view/accessibility/AccessibilityNodeInfo$CollectionItemInfo;)V"), c.toI64());
		}
		// the actions it takes
		var add = m(INFO, "addAction", "(I)V");
		inline function action(a:Int)
			Jni.call(info, add, a);
		action(a11yFocus == id ? 128 : 64); // ACTION_CLEAR_ACCESSIBILITY_FOCUS, ACTION_ACCESSIBILITY_FOCUS
		if (n.focusable && !n.disabled) action(t.focus == id ? 2 : 1); // ACTION_CLEAR_FOCUS, ACTION_FOCUS
		if (n.pressable()) action(16); // ACTION_CLICK
		if (n.selected == false) action(4); // ACTION_SELECT
		if (n.expanded != null) action(n.expanded ? 524288 : 262144); // ACTION_COLLAPSE, ACTION_EXPAND
		if (n.editable() && !n.readOnly) action(2097152); // ACTION_SET_TEXT
		if (n.editable()) action(131072); // ACTION_SET_SELECTION
		if (n.valueNow != null && n.role != ProgressIndicator) {
			action(4096); // ACTION_SCROLL_FORWARD
			action(8192); // ACTION_SCROLL_BACKWARD
		}
		return info;
	}

	// --- the natives ---

	@:hxmc.callback static function nodeProvider(env:Ptr, self:Ptr, view:Ptr):Ptr
		return provider;

	@:hxmc.callback static function nodeInfo(env:Ptr, self:Ptr, id:Int):Ptr {
		if (!asked) {
			asked = true;
			pending = true;
			MainThread.wake();
		}
		return try info(id) catch (e:Dynamic) {
			Sys.println("helder.ui: an accessibility node: " + Std.string(e));
			Ptr.nil();
		}
	}

	@:hxmc.callback static function findFocus(env:Ptr, self:Ptr, type:Int):Ptr {
		var a = current, t = a == null ? null : a.published;
		if (t == null) return Ptr.nil();
		// (FOCUS_INPUT: the program's focus; FOCUS_ACCESSIBILITY: ours)
		var id = type == 1 ? t.focus : a11yFocus;
		return id == 0 || !t.nodes.exists(id) ? Ptr.nil() : nodeInfo(env, self, id);
	}

	@:hxmc.callback static function performAction(env:Ptr, self:Ptr, id:Int, action:Int, args:Ptr):Int {
		var a = current, t = a == null ? null : a.published;
		if (id == HOST)
			return Jni.bool(host, m("android.view.View", "performAccessibilityAction", "(ILandroid/os/Bundle;)Z"), action, args.toI64()) ? 1 : 0;
		if (t == null || !t.nodes.exists(id)) return 0;
		var n = t.nodes.get(id);
		var done = try switch action {
			case 64: // ACTION_ACCESSIBILITY_FOCUS
				a11yFocus = id;
				Jni.call(host, m("android.view.View", "invalidate", "()V"));
				event(32768, id); // TYPE_VIEW_ACCESSIBILITY_FOCUSED
				true;
			case 128: // ACTION_CLEAR_ACCESSIBILITY_FOCUS
				if (a11yFocus == id) {
					a11yFocus = 0;
					event(65536, id); // TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED
				}
				true;
			case 16: ask(id, Click);
			case 1: ask(id, Focus);
			case 4: ask(id, Select);
			case 262144: ask(id, Expand);
			case 524288: ask(id, Collapse);
			case 4096: n.valueNow != null ? ask(id, Increment) : ask(id, ScrollIntoView);
			case 8192: n.valueNow != null ? ask(id, Decrement) : false;
			case 2097152: // ACTION_SET_TEXT: ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE
				var s = args.isNull() ? Ptr.nil() : Jni.obj(args, m("android.os.Bundle", "getCharSequence", "(Ljava/lang/String;)Ljava/lang/CharSequence;"),
					Jni.string("ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE").toI64());
				var text = s.isNull() ? "" : Jni.fromString(Jni.obj(s, m("java.lang.Object", "toString", "()Ljava/lang/String;")));
				ask(id, SetValue, text);
			case 131072: // ACTION_SET_SELECTION: its start and end
				if (args.isNull()) false else {
					var get = m("android.os.Bundle", "getInt", "(Ljava/lang/String;)I");
					var s = Jni.int(args, get, Jni.string("ACTION_ARGUMENT_SELECTION_START_INT").toI64());
					var e = Jni.int(args, get, Jni.string("ACTION_ARGUMENT_SELECTION_END_INT").toI64());
					ask(id, SetSelection, '$s,$e');
				}
			case _: false;
		} catch (e:Dynamic) {
			Sys.println("helder.ui: an accessibility action: " + Std.string(e));
			false;
		}
		return done ? 1 : 0;
	}
}

// JNI's int arrays (jni.h's NewIntArray, GetIntArrayRegion)
@:build(helder.os.VTable.build())
@:hxmc.unsafe(gc)
class JniArrays {
	@:slot(179) static function NewIntArray(env:Ptr, length:Int):Ptr;
	@:slot(203) static function GetIntArrayRegion(env:Ptr, a:Ptr, start:Int, length:Int, buf:Ptr):Void;
}
