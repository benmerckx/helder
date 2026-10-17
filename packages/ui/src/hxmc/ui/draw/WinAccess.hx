package hxmc.ui.draw;

import hxmc.ui.access.AccessNode;
import hxmc.ui.access.AccessTree;
import hxmc.ui.access.Role;
import hxmc.unsafe.*;

// A UiWindow's accessibility tree on Windows (UI Automation), for Narrator
// and the other assistive technology: the window answers WM_GETOBJECT with
// its root's provider (UiaReturnRawElementProvider); each node is a COM
// object made here, seven interfaces in one block (IRawElementProviderSimple,
// IRawElementProviderFragment, IRawElementProviderFragmentRoot (the root's),
// and the patterns IInvokeProvider, IToggleProvider, IRangeValueProvider,
// IValueProvider), each interface a vtable pointer then the block's address,
// their methods @:hxmc.callback functions; the block ends with the node's
// id (0 once it left the tree) and the reference count. UI Automation calls
// them on the window's thread (ProviderOptions_UseComThreading; the thread
// joins a COM apartment). Properties: the control type, name, help text,
// focusability, focus, enabled state, automation id; navigation by the
// tree; bounds in screen pixels; actions (invoke, toggle, a value set,
// focus) come back as Ui.accessAction. A change of focus raises UI
// Automation's focus event, a live region's change (LiveSetting) its
// LiveRegionChanged event.
class WinAccess {
	static inline var SLOTS = 7;
	static inline var BLOCK = 16 * SLOTS + 16;
	static final IIDS = [
		// IRawElementProviderSimple, IRawElementProviderFragment, IRawElementProviderFragmentRoot
		"d6dd68d1-86fd-4332-8666-9abedea2d24c", "f7063da8-8359-439c-9297-bbc5299a7d87", "620ce2a5-ab8f-40a9-86cb-de3c75599b58",
		// IInvokeProvider, IToggleProvider, IRangeValueProvider, IValueProvider
		"54fcb24b-e18e-47a2-b4d3-eccbe77599a2", "56d00bd0-c4f4-433c-a836-1a52a57e0892", "36dc7aef-33e6-4691-afe1-2be7274b3d33",
		"c7935180-6fb3-4201-b174-7df73adbf64a"
	];
	static inline var IID_UNKNOWN = "00000000-0000-0000-c000-000000000046";
	static inline var S_OK = 0;
	static inline var E_NOINTERFACE = 0x80004002;
	static inline var E_FAIL = 0x80004005;
	static inline var E_INVALIDARG = 0x80070057;
	static inline var NOT_AVAILABLE = 0x80040201; // UIA_E_ELEMENTNOTAVAILABLE

	static var vtables:Array<Ptr> = [];
	// the windows' adapters, by their blocks' addresses
	static final byBlock = new Map<String, WinAccess>();
	static final all:Array<WinAccess> = [];
	static var started = false;

	final ui:Ui;
	final window:hxmc.os.Window;
	final hwnd:Ptr;
	final blocks = new Map<Int, Ptr>();
	final parents = new Map<Int, Int>();
	var tree:Null<AccessTree>;

	public function new(window:hxmc.os.Window, ui:Ui) {
		this.window = window;
		this.ui = ui;
		hwnd = window.surface.handle;
		if (!started) start();
		all.push(this);
		hxmc.os.win32.Win32Window.getObject = getObject;
	}

	static function start() {
		started = true;
		// (a single-threaded apartment: UI Automation's calls come through the message loop)
		Ole32.CoInitializeEx(Ptr.nil(), 2);
		var unknown = [Callback.addr(queryInterface), Callback.addr(addRef), Callback.addr(release)];
		var methods:Array<Array<Ptr>> = [
			[Callback.addr(providerOptions), Callback.addr(patternProvider), Callback.addr(propertyValue), Callback.addr(hostProvider)],
			[Callback.addr(navigate), Callback.addr(runtimeId), Callback.addr(boundingRectangle), Callback.addr(embeddedRoots), Callback.addr(setFocus),
				Callback.addr(fragmentRoot)],
			[Callback.addr(fromPoint), Callback.addr(getFocus)],
			[Callback.addr(invoke)],
			[Callback.addr(toggle), Callback.addr(toggleState)],
			[Callback.addr(rangeSet), Callback.addr(rangeValue), Callback.addr(readOnly), Callback.addr(rangeMax), Callback.addr(rangeMin),
				Callback.addr(rangeLarge), Callback.addr(rangeSmall)],
			[Callback.addr(valueSet), Callback.addr(valueGet), Callback.addr(readOnly)]
		];
		for (m in methods) {
			var all = unknown.concat(m);
			var t:Ptr<Ptr> = LibC.malloc(8 * all.length);
			for (i in 0...all.length)
				t[i] = all[i];
			vtables.push(t);
		}
	}

	// WM_GETOBJECT for UI Automation's root (UiaRootObjectId: -25): the root's provider
	static function getObject(hwnd:Ptr, wParam:Int64, lParam:Int64):Int64 {
		if (lParam.toInt() != -25) return 0;
		for (a in all)
			if (a.hwnd == hwnd) {
				a.activate();
				if (a.tree != null) return Uia.UiaReturnRawElementProvider(hwnd, wParam, lParam, a.block(a.tree.root));
			}
		return 0;
	}

	// (no tree is built until a client asks for the root: most programs run with none)
	var active = false;

	function activate() {
		if (active) return;
		active = true;
		update();
	}

	public function dispose() {
		Uia.UiaReturnRawElementProvider(hwnd, 0, 0, Ptr.nil());
		for (id in [for (k in blocks.keys()) k])
			drop(id);
		all.remove(this);
	}

	// the tree after a frame: blocks for the nodes new, released for the gone
	public function update() {
		if (!active) return;
		var t = ui.accessTree();
		var c = t.changes(tree);
		var focusChanged = tree != null && tree.focus != t.focus;
		for (id in c.removed)
			drop(id);
		if (c.nodes.length > 0) {
			parents.clear();
			for (id in t.order)
				for (k in t.nodes.get(id).children)
					parents.set(k, id);
		}
		var said = t.announcements(tree);
		tree = t;
		if (focusChanged && t.focus != 0 && Uia.UiaClientsAreListening() != 0) Uia.UiaRaiseAutomationEvent(block(t.focus), 20005); // UIA_AutomationFocusChangedEventId
		for (s in said)
			if (Uia.UiaClientsAreListening() != 0) Uia.UiaRaiseAutomationEvent(block(s.id), 20024); // UIA_LiveRegionChangedEventId
	}

	// the root's provider (IRawElementProviderSimple; tests)
	public function rootProvider():Ptr {
		activate();
		return tree == null ? Ptr.nil() : block(tree.root);
	}

	// a node's block (its IRawElementProviderSimple), made when it has none
	function block(id:Int):Ptr {
		var b = blocks.get(id);
		if (b == null) {
			b = LibC.malloc(BLOCK);
			for (k in 0...SLOTS) {
				(b.add(16 * k) : Ptr<Ptr>).value = vtables[k];
				(b.add(16 * k + 8) : Ptr<Ptr>).value = b;
			}
			(b.add(16 * SLOTS) : Ptr<Int64>).value = id;
			(b.add(16 * SLOTS + 8) : Ptr<Int64>).value = 1;
			blocks.set(id, b);
			byBlock.set(key(b), this);
		}
		return b;
	}

	// a node gone: its block dead (its methods fail), our reference released
	function drop(id:Int) {
		var b = blocks.get(id);
		if (b == null) return;
		blocks.remove(id);
		(b.add(16 * SLOTS) : Ptr<Int64>).value = 0;
		releaseBlock(b);
	}

	static inline function key(b:Ptr):String
		return Std.string(b.toI64());

	// --- from an interface pointer ---

	static inline function base(self:Ptr):Ptr
		return (self.add(8) : Ptr<Ptr>).value;

	static function idOf(self:Ptr):Int
		return (base(self).add(16 * SLOTS) : Ptr<Int64>).value.toInt();

	static function adapter(self:Ptr):Null<WinAccess>
		return byBlock.get(key(base(self)));

	// the node of an interface pointer (null: gone)
	static function node(self:Ptr):Null<AccessNode> {
		var a = adapter(self), id = idOf(self);
		return a == null || id == 0 || a.tree == null ? null : a.tree.nodes.get(id);
	}

	static function releaseBlock(b:Ptr):Int {
		var refs:Ptr<Int64> = b.add(16 * SLOTS + 8);
		var n = refs.value.toInt() - 1;
		refs.value = n;
		if (n == 0) {
			byBlock.remove(key(b));
			LibC.free(b);
		}
		return n;
	}

	// an interface of a block, referenced (into out)
	static function give(b:Ptr, slot:Int, out:Ptr<Ptr>):Int {
		var refs:Ptr<Int64> = b.add(16 * SLOTS + 8);
		refs.value = refs.value.toInt() + 1;
		out.value = b.add(16 * slot);
		return S_OK;
	}

	static function guid(p:Ptr):String {
		inline function hex(v:Int, n:Int)
			return StringTools.hex(v, n).toLowerCase();
		var b:Ptr<UInt8> = p;
		var d1 = b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);
		var s = hex(d1, 8) + "-" + hex(b[4] | (b[5] << 8), 4) + "-" + hex(b[6] | (b[7] << 8), 4) + "-" + hex(b[8], 2) + hex(b[9], 2) + "-";
		for (i in 10...16)
			s += hex(b[i], 2);
		return s;
	}

	// --- IUnknown ---

	@:hxmc.callback static function queryInterface(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int {
		if (out.isNull()) return E_INVALIDARG;
		out.value = Ptr.nil();
		var g = guid(iid), b = base(self);
		if (g == IID_UNKNOWN) return give(b, 0, out);
		var k = IIDS.indexOf(g);
		if (k < 0) return E_NOINTERFACE;
		var n = node(self);
		// (the fragment root: the root's; a pattern: when the node has it)
		if (k == 2 && (n == null || adapter(self).tree.root != n.id)) return E_NOINTERFACE;
		if (k >= 3 && (n == null || pattern(n) != k)) return E_NOINTERFACE;
		return give(b, k, out);
	}

	@:hxmc.callback static function addRef(self:Ptr):Int {
		var refs:Ptr<Int64> = base(self).add(16 * SLOTS + 8);
		var n = refs.value.toInt() + 1;
		refs.value = n;
		return n;
	}

	@:hxmc.callback static function release(self:Ptr):Int
		return releaseBlock(base(self));

	// the pattern interface's slot of a node (0: none): Invoke, Toggle, RangeValue, Value
	static function pattern(n:AccessNode):Int
		return switch n.role {
			case Button | MenuItem | Link | ListBoxOption | Tab: 3;
			case CheckBox | Switch: 4;
			case Slider | ProgressIndicator | SpinButton: 5;
			case TextInput | MultilineTextInput: 6;
			case ComboBox if (n.value != null): 6;
			case RadioButton: 3;
			case _: 0;
		}

	// --- IRawElementProviderSimple ---

	@:hxmc.callback static function providerOptions(self:Ptr, out:Ptr<Int32>):Int {
		out.value = 0x21; // ServerSideProvider | UseComThreading
		return S_OK;
	}

	@:hxmc.callback static function patternProvider(self:Ptr, id:Int, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		var k = pattern(n);
		var wanted = switch id {
			case 10000: 3; // Invoke
			case 10015: 4; // Toggle
			case 10003: 5; // RangeValue
			case 10002: 6; // Value
			case _: -1;
		}
		return wanted == k ? give(base(self), k, out) : S_OK;
	}

	@:hxmc.callback static function propertyValue(self:Ptr, id:Int, v:Ptr):Int {
		(v : Ptr<Int64>).value = 0;
		(v.add(8) : Ptr<Int64>).value = 0;
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		var a = adapter(self);
		var root = n.id == a.tree.root;
		switch id {
			case 30003: int(v, root ? 50033 : controlType(n.role)); // ControlType (the root: a pane)
			case 30005 if (!root): str(v, n.name); // Name (the root: the window's title)
			case 30013 if (n.description != null): str(v, n.description); // HelpText
			case 30009: bool(v, n.focusable); // IsKeyboardFocusable
			case 30008: bool(v, a.tree.focus == n.id); // HasKeyboardFocus
			case 30010: bool(v, !n.disabled); // IsEnabled
			case 30011: str(v, "hxmc-" + n.id); // AutomationId
			case 30016 | 30017: bool(v, true); // IsControlElement, IsContentElement
			case 30019: bool(v, n.secret); // IsPassword
			case 30135 if (n.live != Off): int(v, n.live == Assertive ? 2 : 1); // LiveSetting (Polite, Assertive)
			case 30157 if (n.role == Navigation): int(v, 80003); // LandmarkType (Navigation)
			case 30102 if (n.current): str(v, "current=page"); // AriaProperties
			case 30045 if (n.value != null): str(v, n.value); // Value.Value
			case _:
		}
		return S_OK;
	}

	static function int(v:Ptr, i:Int) {
		(v : Ptr<UInt16>).value = 3; // VT_I4
		(v.add(8) : Ptr<Int32>).value = i;
	}

	static function bool(v:Ptr, b:Bool) {
		(v : Ptr<UInt16>).value = 11; // VT_BOOL
		(v.add(8) : Ptr<Int16>).value = b ? -1 : 0;
	}

	static function str(v:Ptr, s:String) {
		(v : Ptr<UInt16>).value = 8; // VT_BSTR
		(v.add(8) : Ptr<Ptr>).value = bstr(s);
	}

	static function bstr(s:String):Ptr
		return Arena.scopedValue(a -> OleAut.SysAllocStringLen(a.wstring(s), s.length));

	static function controlType(r:Role):Int
		return switch r {
			case Button: 50000;
			case CheckBox | Switch: 50002;
			case ComboBox: 50003;
			case TextInput | MultilineTextInput: 50004;
			case Link: 50005;
			case Image: 50006;
			case ListItem | ListBoxOption: 50007;
			case List | ListBox: 50008;
			case Menu: 50009;
			case MenuBar: 50010;
			case Toolbar: 50021;
			case MenuItem: 50011;
			case ProgressIndicator: 50012;
			case RadioButton: 50013;
			case Slider: 50015;
			case SpinButton: 50016;
			case TabList: 50018;
			case Tab: 50019;
			case Label | Heading: 50020;
			case Tooltip: 50022;
			// (DataGrid, DataItem for rows and cells, HeaderItem: as Chromium maps a grid)
			case Table: 50028;
			case Row | Cell: 50029;
			case ColumnHeader: 50035;
			case Tree: 50023;
			case TreeItem: 50024;
			case Separator: 50038;
			case Dialog | AlertDialog: 50032;
			case ScrollView | TabPanel: 50033;
			case _: 50026; // Group
		}

	@:hxmc.callback static function hostProvider(self:Ptr, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		return n.id == a.tree.root ? Uia.UiaHostProviderFromHwnd(a.hwnd, out) : S_OK;
	}

	// --- IRawElementProviderFragment ---

	@:hxmc.callback static function navigate(self:Ptr, dir:Int, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		var t = a.tree;
		var target = 0;
		switch dir {
			case 0: // Parent (the root's: the window's, UI Automation's own)
				if (n.id != t.root) target = a.parents.get(n.id) ?? 0;
			case 1 | 2: // NextSibling, PreviousSibling
				var p = a.parents.get(n.id);
				if (p != null) {
					var kids = t.nodes.get(p).children, i = kids.indexOf(n.id) + (dir == 1 ? 1 : -1);
					if (i >= 0 && i < kids.length) target = kids[i];
				}
			case 3: if (n.children.length > 0) target = n.children[0]; // FirstChild
			case 4: if (n.children.length > 0) target = n.children[n.children.length - 1]; // LastChild
			case _:
		}
		return target == 0 ? S_OK : give(a.block(target), 1, out);
	}

	@:hxmc.callback static function runtimeId(self:Ptr, out:Ptr<Ptr>):Int {
		var id = idOf(self);
		if (id == 0) return NOT_AVAILABLE;
		// (UiaAppendRuntimeId, then the node's)
		var sa = OleAut.SafeArrayCreateVector(3, 0, 2);
		Arena.scoped(a -> {
			var i:Ptr<Int32> = a.alloc(4), v:Ptr<Int32> = a.alloc(4);
			i.value = 0;
			v.value = 3;
			OleAut.SafeArrayPutElement(sa, i, v);
			i.value = 1;
			v.value = id;
			OleAut.SafeArrayPutElement(sa, i, v);
		});
		out.value = sa;
		return S_OK;
	}

	// a node's box in screen pixels: left, top, width, height
	function screenRect(n:AccessNode):Array<Float> {
		var k = ui.width > 0 ? window.surface.width / ui.width : 1.0;
		var o = Arena.scopedValue(a -> {
			var p = a.make(hxmc.os.win32.User32.POINT);
			p.value.x = 0;
			p.value.y = 0;
			hxmc.os.win32.User32.User32.ClientToScreen(hwnd, p);
			[p.value.x, p.value.y];
		});
		return [o[0] + n.x * k, o[1] + n.y * k, n.width * k, n.height * k];
	}

	@:hxmc.callback static function boundingRectangle(self:Ptr, out:Ptr<Float>):Int {
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		var r = a.screenRect(n);
		for (i in 0...4)
			out[i] = r[i];
		return S_OK;
	}

	@:hxmc.callback static function embeddedRoots(self:Ptr, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		return S_OK;
	}

	@:hxmc.callback static function setFocus(self:Ptr):Int {
		var a = adapter(self), id = idOf(self);
		return a != null && id != 0 && a.ui.accessAction(id, Focus) ? S_OK : E_FAIL;
	}

	@:hxmc.callback static function fragmentRoot(self:Ptr, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var a = adapter(self);
		if (a == null || a.tree == null) return NOT_AVAILABLE;
		return give(a.block(a.tree.root), 2, out);
	}

	// --- IRawElementProviderFragmentRoot ---

	@:hxmc.callback static function fromPoint(self:Ptr, x:Float, y:Float, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var a = adapter(self);
		if (a == null || a.tree == null) return NOT_AVAILABLE;
		var t = a.tree, id = t.root;
		while (true) {
			var next = 0;
			for (k in t.nodes.get(id).children) {
				var r = a.screenRect(t.nodes.get(k));
				if (x >= r[0] && x < r[0] + r[2] && y >= r[1] && y < r[1] + r[3]) next = k;
			}
			if (next == 0) break;
			id = next;
		}
		return give(a.block(id), 1, out);
	}

	@:hxmc.callback static function getFocus(self:Ptr, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var a = adapter(self);
		if (a == null || a.tree == null) return NOT_AVAILABLE;
		return a.tree.focus == 0 ? S_OK : give(a.block(a.tree.focus), 1, out);
	}

	// --- the patterns ---

	static function act(self:Ptr, action:hxmc.ui.access.AccessAction, ?value:String):Int {
		var a = adapter(self), id = idOf(self);
		return a != null && id != 0 && a.ui.accessAction(id, action, value) ? S_OK : E_FAIL;
	}

	@:hxmc.callback static function invoke(self:Ptr):Int
		return act(self, Click);

	@:hxmc.callback static function toggle(self:Ptr):Int
		return act(self, Click);

	@:hxmc.callback static function toggleState(self:Ptr, out:Ptr<Int32>):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		// (ToggleState: off, on, indeterminate)
		out.value = n.mixed ? 2 : n.checked == true ? 1 : 0;
		return S_OK;
	}

	// (a range's value: stepped toward it, as the keys do)
	@:hxmc.callback static function rangeSet(self:Ptr, v:Float):Int {
		var n = node(self);
		if (n == null || n.valueNow == null || n.role == ProgressIndicator) return E_FAIL;
		return act(self, v > n.valueNow ? Increment : Decrement);
	}

	static function rangeOut(self:Ptr, out:Ptr<Float>, f:AccessNode->Null<Float>):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		var v = f(n);
		out.value = v == null ? 0 : v;
		return S_OK;
	}

	@:hxmc.callback static function rangeValue(self:Ptr, out:Ptr<Float>):Int
		return rangeOut(self, out, n -> n.valueNow);

	@:hxmc.callback static function rangeMax(self:Ptr, out:Ptr<Float>):Int
		return rangeOut(self, out, n -> n.valueMax);

	@:hxmc.callback static function rangeMin(self:Ptr, out:Ptr<Float>):Int
		return rangeOut(self, out, n -> n.valueMin);

	@:hxmc.callback static function rangeLarge(self:Ptr, out:Ptr<Float>):Int
		return rangeOut(self, out, n -> n.valueMax == null || n.valueMin == null ? null : (n.valueMax - n.valueMin) / 10);

	@:hxmc.callback static function rangeSmall(self:Ptr, out:Ptr<Float>):Int
		return rangeOut(self, out, n -> n.valueMax == null || n.valueMin == null ? null : (n.valueMax - n.valueMin) / 20);

	@:hxmc.callback static function readOnly(self:Ptr, out:Ptr<Int32>):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		out.value = n.disabled || n.role == ProgressIndicator ? 1 : 0;
		return S_OK;
	}

	@:hxmc.callback static function valueSet(self:Ptr, s:Ptr):Int {
		var text = new StringBuf(), p:Ptr<UInt16> = s, i = 0;
		while (!s.isNull() && p[i] != 0) {
			var c = p[i++];
			if (c >= 0xD800 && c < 0xDC00 && p[i] >= 0xDC00 && p[i] < 0xE000) c = 0x10000 + ((c - 0xD800) << 10) + (p[i++] - 0xDC00);
			text.addChar(c);
		}
		return act(self, SetValue, text.toString());
	}

	@:hxmc.callback static function valueGet(self:Ptr, out:Ptr<Ptr>):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		out.value = bstr(n.value ?? "");
		return S_OK;
	}
}

@:hxmc.c @:hxmc.lib("uiautomationcore") extern class Uia {
	static function UiaReturnRawElementProvider(hwnd:Ptr, wParam:Int64, lParam:Int64, provider:Ptr):Int64;
	static function UiaHostProviderFromHwnd(hwnd:Ptr, out:Ptr<Ptr>):Int;
	static function UiaRaiseAutomationEvent(provider:Ptr, id:Int):Int;
	static function UiaClientsAreListening():Int;
}

@:hxmc.c @:hxmc.lib("oleaut32") extern class OleAut {
	static function SysAllocStringLen(s:Ptr, length:Int):Ptr;
	static function SafeArrayCreateVector(vt:Int, lower:Int, count:Int):Ptr;
	static function SafeArrayPutElement(array:Ptr, index:Ptr<Int32>, value:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("ole32") extern class Ole32 {
	static function CoInitializeEx(reserved:Ptr, flags:Int):Int;
}
