package helder.ui.draw;

import helder.ui.access.AccessAction;
import helder.ui.access.AccessNode;
import helder.ui.access.AccessTree;
import helder.ui.access.Role;
import hxmc.unsafe.*;

// A UiWindow's accessibility tree on Windows (UI Automation), for Narrator
// and the other assistive technology: the window answers WM_GETOBJECT with
// its root's provider (UiaReturnRawElementProvider); each node is a COM
// object made here, sixteen interfaces in one block (IRawElementProviderSimple,
// IRawElementProviderFragment, IRawElementProviderFragmentRoot (the root's),
// and the patterns' providers a node has: Invoke, Toggle, RangeValue,
// Value, ExpandCollapse, SelectionItem, Selection, ScrollItem, Grid,
// GridItem, Table, TableItem, Text), each interface a vtable pointer then
// the block's address, their methods @:hxmc.callback functions; the block
// ends with the node's id (0 once it left the tree) and the reference
// count. A text input's Text pattern gives ranges (ITextRangeProvider, a
// small block of its own: the node, a start and an end in UTF-16 units):
// its text by characters, words, lines and the whole, its selection set,
// found, compared, moved by units. UI Automation calls them on the
// window's thread (ProviderOptions_UseComThreading; the thread joins a COM
// apartment). Properties: the control type, name, help text, focusability,
// focus, enabled state, automation id, an item's place in its set, a
// heading's level, whether it is off screen; navigation by the tree;
// bounds in screen pixels; actions (invoke, toggle, a value set, expand,
// collapse, select, scroll into view, focus, a text's selection) come back
// as Ui.accessAction. After each frame, from what changed (AccessTree.changes):
// the focus event, StructureChanged (a node's children invalidated),
// property changes (name, help text, toggle and expand states, selection,
// values, enabled), ElementSelected, a text's TextChanged and
// TextSelectionChanged, a live region's LiveRegionChanged.
class WinAccess {
	static inline var SLOTS = 16;
	static inline var BLOCK = 16 * SLOTS + 16;
	static final IIDS = [
		// IRawElementProviderSimple, IRawElementProviderFragment, IRawElementProviderFragmentRoot
		"d6dd68d1-86fd-4332-8666-9abedea2d24c", "f7063da8-8359-439c-9297-bbc5299a7d87", "620ce2a5-ab8f-40a9-86cb-de3c75599b58",
		// IInvokeProvider, IToggleProvider, IRangeValueProvider, IValueProvider
		"54fcb24b-e18e-47a2-b4d3-eccbe77599a2", "56d00bd0-c4f4-433c-a836-1a52a57e0892", "36dc7aef-33e6-4691-afe1-2be7274b3d33",
		"c7935180-6fb3-4201-b174-7df73adbf64a",
		// IExpandCollapseProvider, ISelectionItemProvider, ISelectionProvider, IScrollItemProvider
		"d847d3a5-cab0-4a98-8c32-ecb45c59ad24", "2acad808-b2d4-452d-a407-91ff1ad167b2", "fb8b03af-3bdf-48d4-bd36-1a65793be168",
		"2360c714-4bf1-4b26-ba65-9b21316127eb",
		// IGridProvider, IGridItemProvider, ITableProvider, ITableItemProvider, ITextProvider
		"b17d6187-0907-464b-a168-0ef17a1572b1", "d02541f1-fb81-4d64-ae32-f520f8a6dbd1", "9c860395-97b3-490a-b52a-858cc22af166",
		"b9734fa6-771f-4d78-9c90-2517999349cd", "3589c92c-63f3-4367-99bb-ada653b77cf2"
	];
	// each pattern's id, by its slot (from 3)
	static final PATTERNS = [10000, 10015, 10003, 10002, 10005, 10010, 10001, 10017, 10006, 10007, 10012, 10013, 10014];
	static inline var IID_UNKNOWN = "00000000-0000-0000-c000-000000000046";
	static inline var IID_RANGE = "5347ad7b-c355-46f8-aff5-909033582f63";
	static inline var S_OK = 0;
	static inline var E_NOINTERFACE = 0x80004002;
	static inline var E_FAIL = 0x80004005;
	static inline var E_INVALIDARG = 0x80070057;
	static inline var NOT_AVAILABLE = 0x80040201; // UIA_E_ELEMENTNOTAVAILABLE
	static inline var INVALID_OPERATION = 0x80131509; // UIA_E_INVALIDOPERATION

	static var vtables:Array<Ptr> = [];
	// each event raised, told (tests: WinAccessProbe's run prints them)
	public static var log:Null<String->Void> = null;

	static function raise(p:Ptr, id:Int) {
		var hr = Uia.UiaRaiseAutomationEvent(p, id);
		if (log != null) log('event $id: ' + StringTools.hex(hr));
	}
	static var rangeTable:Ptr = Ptr.nil();
	// the windows' adapters, by their blocks' addresses (and their ranges')
	static final byBlock = new Map<String, WinAccess>();
	static final all:Array<WinAccess> = [];
	static var started = false;

	final ui:Ui;
	final window:helder.os.Window;
	final hwnd:Ptr;
	final blocks = new Map<Int, Ptr>();
	var parents = new Map<Int, Int>();
	var tree:Null<AccessTree>;

	public function new(window:helder.os.Window, ui:Ui) {
		this.window = window;
		this.ui = ui;
		hwnd = window.surface.handle;
		if (!started) start();
		all.push(this);
		helder.os.win32.Win32Window.getObject = getObject;
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
			[Callback.addr(valueSet), Callback.addr(valueGet), Callback.addr(readOnly)],
			[Callback.addr(expand), Callback.addr(collapse), Callback.addr(expandState)],
			[Callback.addr(select), Callback.addr(select), Callback.addr(unselect), Callback.addr(isSelected), Callback.addr(selectionContainer)],
			[Callback.addr(selection), Callback.addr(canSelectMultiple), Callback.addr(selectionRequired)],
			[Callback.addr(scrollIntoView)],
			[Callback.addr(gridItem), Callback.addr(gridRows), Callback.addr(gridColumns)],
			[Callback.addr(itemRow), Callback.addr(itemColumn), Callback.addr(itemSpan), Callback.addr(itemSpan), Callback.addr(containingGrid)],
			[Callback.addr(rowHeaders), Callback.addr(columnHeaders), Callback.addr(rowMajor)],
			[Callback.addr(rowHeaders), Callback.addr(itemColumnHeaders)],
			[Callback.addr(textSelection), Callback.addr(visibleRanges), Callback.addr(rangeFromChild), Callback.addr(rangeFromPoint),
				Callback.addr(documentRange), Callback.addr(supportedSelection)]
		];
		for (m in methods)
			vtables.push(table(unknown.concat(m)));
		rangeTable = table([
			Callback.addr(rangeQuery), Callback.addr(rangeAddRef), Callback.addr(rangeRelease), Callback.addr(rClone), Callback.addr(rCompare),
			Callback.addr(rCompareEndpoints), Callback.addr(rExpand), Callback.addr(rFindAttribute), Callback.addr(rFindText), Callback.addr(rAttribute),
			Callback.addr(rRectangles), Callback.addr(rEnclosing), Callback.addr(rText), Callback.addr(rMove), Callback.addr(rMoveEndpoint),
			Callback.addr(rMoveEndpointByRange), Callback.addr(rSelect), Callback.addr(rInvalid), Callback.addr(rInvalid), Callback.addr(rScroll),
			Callback.addr(rChildren)
		]);
	}

	static function table(fns:Array<Ptr>):Ptr {
		var t:Ptr<Ptr> = LibC.malloc(8 * fns.length);
		for (i in 0...fns.length)
			t[i] = fns[i];
		return t;
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

	// whether a client asked for the tree (its changes then raised)
	public function listening():Bool
		return active;

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

	// the tree after a frame: blocks for the nodes new, released for the
	// gone, the events of what changed
	public function update() {
		if (!active) return;
		var t = ui.accessTree();
		var old = tree;
		var c = t.changes(old);
		for (id in c.removed)
			drop(id);
		if (c.nodes.length > 0 || c.removed.length > 0) parents = t.parents();
		var said = t.announcements(old);
		tree = t;
		if (log != null) log('update: ${c.nodes.length} changed, listening ${Uia.UiaClientsAreListening()}, ${old == null ? "first" : "again"}');
		if (old == null || Uia.UiaClientsAreListening() == 0) return;
		for (n in c.nodes) {
			var b = old.nodes.get(n.id);
			if (b != null) changed(b, n);
		}
		if (old.focus != t.focus && t.focus != 0) raise(block(t.focus), 20005); // UIA_AutomationFocusChangedEventId
		for (s in said)
			raise(block(s.id), 20024); // UIA_LiveRegionChangedEventId
	}

	// a node's events: what differs from how it was
	function changed(b:AccessNode, n:AccessNode) {
		var p = block(n.id);
		if (b.children.join(",") != n.children.join(",")) Arena.scoped(a -> {
			// (StructureChangeType_ChildrenInvalidated: its children read again)
			// (the root's: the window's, UiaRuntimeId's 42 and the HWND)
			var rid:Ptr<Int32> = a.alloc(8);
			rid[0] = n.id == tree.root ? 42 : 3;
			rid[1] = n.id == tree.root ? hwnd.toI64().toInt() : n.id;
			var hr = Uia.UiaRaiseStructureChangedEvent(p, 2, rid, 2);
			if (log != null) log('structure ${n.id}: ' + StringTools.hex(hr));
		});
		if (b.name != n.name && n.id != tree.root) changedProperty(p, 30005, v -> str(v, b.name), v -> str(v, n.name)); // Name
		if (b.description != n.description) changedProperty(p, 30013, v -> str(v, b.description ?? ""), v -> str(v, n.description ?? "")); // HelpText
		if (b.disabled != n.disabled) changedProperty(p, 30010, v -> bool(v, !b.disabled), v -> bool(v, !n.disabled)); // IsEnabled
		if (b.checked != n.checked || b.mixed != n.mixed) changedProperty(p, 30086, v -> int(v, toggleOf(b)), v -> int(v, toggleOf(n))); // Toggle.ToggleState
		if (b.expanded != n.expanded && n.expanded != null)
			changedProperty(p, 30070, v -> int(v, b.expanded == true ? 1 : 0), v -> int(v, n.expanded ? 1 : 0)); // ExpandCollapse.ExpandCollapseState
		if (b.selected != n.selected && n.selected != null) {
			changedProperty(p, 30079, v -> bool(v, b.selected == true), v -> bool(v, n.selected)); // SelectionItem.IsSelected
			if (n.selected) raise(p, 20012); // SelectionItem_ElementSelectedEventId
		}
		if (b.valueNow != n.valueNow && n.valueNow != null) changedProperty(p, 30047, v -> double(v, b.valueNow ?? 0), v -> double(v, n.valueNow)); // RangeValue.Value
		if (b.value != n.value && n.value != null) {
			changedProperty(p, 30045, v -> str(v, b.value ?? ""), v -> str(v, n.value)); // Value.Value
			if (n.editable()) raise(p, 20015); // Text_TextChangedEventId
		}
		if (n.editable() && (b.textStart != n.textStart || b.textEnd != n.textEnd)) raise(p, 20014); // Text_TextSelectionChangedEventId
	}

	// a property's change: its old and new values (VARIANTs, passed by address)
	function changedProperty(p:Ptr, id:Int, was:Ptr->Void, now:Ptr->Void)
		Arena.scoped(a -> {
			var o:Ptr = a.alloc(24), v:Ptr = a.alloc(24);
			clear(o);
			clear(v);
			was(o);
			now(v);
			var hr = Uia.UiaRaiseAutomationPropertyChangedEvent(p, id, o, v);
			if (log != null) log('property $id: ' + StringTools.hex(hr));
			OleAut.VariantClear(o);
			OleAut.VariantClear(v);
		});

	static function clear(v:Ptr) {
		(v : Ptr<Int64>).value = 0;
		(v.add(8) : Ptr<Int64>).value = 0;
		(v.add(16) : Ptr<Int64>).value = 0;
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

	// a node gone: its block dead (its methods fail), UI Automation told, our reference released
	function drop(id:Int) {
		var b = blocks.get(id);
		if (b == null) return;
		blocks.remove(id);
		(b.add(16 * SLOTS) : Ptr<Int64>).value = 0;
		if (Uia.UiaClientsAreListening() != 0) Uia.UiaDisconnectProvider(b);
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
		if (k >= 3 && (n == null || !adapter(self).has(n, k))) return E_NOINTERFACE;
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

	// whether a node has the pattern of a slot (from 3)
	function has(n:AccessNode, slot:Int):Bool
		return switch slot {
			case 3: n.pressable() && !n.toggles();
			case 4: n.toggles();
			case 5: n.valueNow != null && !n.editable();
			case 6: n.editable();
			case 7: n.expanded != null;
			case 8: n.selected != null;
			case 9: items(n).length > 0;
			case 10: n.id != tree.root;
			case 11 | 13: n.role == Table;
			case 12: (n.role == Cell || n.role == ColumnHeader) && n.rowIndex >= 0;
			case 14: n.role == Cell && n.rowIndex >= 0;
			case 15: n.editable();
			case _: false;
		}

	// the items a container selects among: a table's rows, else its children that are selected or not
	function items(n:AccessNode):Array<AccessNode> {
		var src = n.role == Table ? tree.tableRows(n.id) : [for (k in n.children) tree.nodes.get(k)];
		return [for (c in src) if (c.selected != null) c];
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
		var k = PATTERNS.indexOf(id) + 3;
		return k >= 3 && adapter(self).has(n, k) ? give(base(self), k, out) : S_OK;
	}

	@:hxmc.callback static function propertyValue(self:Ptr, id:Int, v:Ptr):Int {
		clear(v);
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
			case 30011: str(v, "helder-" + n.id); // AutomationId
			case 30012: str(v, "helder"); // ClassName
			case 30024: str(v, "helder"); // FrameworkId
			case 30016 | 30017: bool(v, true); // IsControlElement, IsContentElement
			case 30019: bool(v, n.secret); // IsPassword
			case 30022: bool(v, n.x + n.width <= 0 || n.y + n.height <= 0 || n.x >= a.ui.width || n.y >= a.ui.height); // IsOffscreen
			case 30023 if (n.role == Slider || n.role == ProgressIndicator): int(v, 1); // Orientation: horizontal
			case 30135 if (n.live != Off): int(v, n.live == Assertive ? 2 : 1); // LiveSetting (Polite, Assertive)
			case 30157 if (n.role == Navigation): int(v, 80003); // LandmarkType (Navigation)
			case 30102 if (n.current): str(v, "current=page"); // AriaProperties
			case 30152 if (n.setSize > 0): int(v, n.posInSet); // PositionInSet
			case 30153 if (n.setSize > 0): int(v, n.setSize); // SizeOfSet
			case 30154 if (n.level != null): int(v, n.level); // Level
			case 30173 if (n.role == Heading): int(v, 80050 + Std.int(Math.min(9, Math.max(1, n.level ?? 2)))); // HeadingLevel
			case 30045 if (n.value != null): str(v, n.value); // Value.Value
			case _:
		}
		return S_OK;
	}

	static function int(v:Ptr, i:Int) {
		(v : Ptr<UInt16>).value = 3; // VT_I4
		(v.add(8) : Ptr<Int32>).value = i;
	}

	static function double(v:Ptr, d:Float) {
		(v : Ptr<UInt16>).value = 5; // VT_R8
		(v.add(8) : Ptr<Float>).value = d;
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
			case MenuItem | MenuItemCheckBox | MenuItemRadio: 50011;
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
		if (n.id == a.tree.root) return Uia.UiaHostProviderFromHwnd(a.hwnd, out);
		// (a field the platform's editor shows: its EDIT's element merged with ours, not a second, unnamed one)
		var node = a.tree.node(n.id);
		for (e in @:privateAccess helder.ui.platform.WinViews.editors)
			if (@:privateAccess e.shown && e.listener == cast node) return Uia.UiaHostProviderFromHwnd(@:privateAccess e.hwnd, out);
		return S_OK;
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
		// (the root, hosted in the window: none of its own, the window's element is its)
		var a = adapter(self);
		if (a != null && a.tree != null && id == a.tree.root) {
			out.value = Ptr.nil();
			return S_OK;
		}
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
		var o = origin();
		return [o[0] + n.x * k, o[1] + n.y * k, n.width * k, n.height * k];
	}

	// the window's client area's top left on the screen
	function origin():Array<Float>
		return Arena.scopedValue(a -> {
			var p = a.make(helder.os.win32.User32.POINT);
			p.value.x = 0;
			p.value.y = 0;
			helder.os.win32.User32.User32.ClientToScreen(hwnd, p);
			[(p.value.x : Float), (p.value.y : Float)];
		});

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

	static function act(self:Ptr, action:AccessAction, ?value:String):Int {
		var a = adapter(self), id = idOf(self);
		return a != null && id != 0 && a.ui.accessAction(id, action, value) ? S_OK : E_FAIL;
	}

	@:hxmc.callback static function invoke(self:Ptr):Int
		return act(self, Click);

	@:hxmc.callback static function toggle(self:Ptr):Int
		return act(self, Click);

	// (ToggleState: off, on, indeterminate)
	static function toggleOf(n:AccessNode):Int
		return n.mixed ? 2 : n.checked == true ? 1 : 0;

	@:hxmc.callback static function toggleState(self:Ptr, out:Ptr<Int32>):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		out.value = toggleOf(n);
		return S_OK;
	}

	// (a range's value: stepped there, as its keys step it)
	@:hxmc.callback static function rangeSet(self:Ptr, v:Float):Int {
		var n = node(self);
		if (n == null || n.valueNow == null || n.role == ProgressIndicator) return E_FAIL;
		return act(self, SetValue, Std.string(v));
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
		out.value = n.disabled || n.readOnly || n.role == ProgressIndicator ? 1 : 0;
		return S_OK;
	}

	static function string(s:Ptr):String {
		var text = new StringBuf(), p:Ptr<UInt16> = s, i = 0;
		while (!s.isNull() && p[i] != 0) {
			var c = p[i++];
			if (c >= 0xD800 && c < 0xDC00 && p[i] >= 0xDC00 && p[i] < 0xE000) c = 0x10000 + ((c - 0xD800) << 10) + (p[i++] - 0xDC00);
			text.addChar(c);
		}
		return text.toString();
	}

	@:hxmc.callback static function valueSet(self:Ptr, s:Ptr):Int {
		var n = node(self);
		if (n != null && n.readOnly) return INVALID_OPERATION;
		return act(self, SetValue, string(s));
	}

	@:hxmc.callback static function valueGet(self:Ptr, out:Ptr<Ptr>):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		out.value = bstr(n.value ?? "");
		return S_OK;
	}

	@:hxmc.callback static function expand(self:Ptr):Int
		return act(self, Expand);

	@:hxmc.callback static function collapse(self:Ptr):Int
		return act(self, Collapse);

	// (ExpandCollapseState: collapsed, expanded)
	@:hxmc.callback static function expandState(self:Ptr, out:Ptr<Int32>):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		out.value = n.expanded == true ? 1 : 0;
		return S_OK;
	}

	@:hxmc.callback static function select(self:Ptr):Int
		return act(self, Select);

	// (one selected of a set: another's selection deselects it, not this)
	@:hxmc.callback static function unselect(self:Ptr):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		if (n.selected != true) return S_OK;
		var a = adapter(self), box = a.container(n.id);
		return box != 0 && a.tree.nodes.get(box).multiselectable ? act(self, Click) : INVALID_OPERATION;
	}

	@:hxmc.callback static function isSelected(self:Ptr, out:Ptr<Int32>):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		out.value = n.selected == true ? 1 : 0;
		return S_OK;
	}

	// the container whose selection an item is part of (0: none)
	function container(id:Int):Int {
		var t = tree.ancestor(id, Table, parents);
		if (t != 0) return t;
		return parents.get(id) ?? 0;
	}

	@:hxmc.callback static function selectionContainer(self:Ptr, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		var box = a.container(n.id);
		return box == 0 ? S_OK : give(a.block(box), 0, out);
	}

	// an array of nodes' providers (VT_UNKNOWN: SafeArrayPutElement references each)
	function providers(ids:Array<Int>):Ptr {
		var sa = OleAut.SafeArrayCreateVector(13, 0, ids.length);
		Arena.scoped(a -> {
			var i:Ptr<Int32> = a.alloc(4);
			for (k in 0...ids.length) {
				i.value = k;
				OleAut.SafeArrayPutElement(sa, i, block(ids[k]));
			}
		});
		return sa;
	}

	@:hxmc.callback static function selection(self:Ptr, out:Ptr<Ptr>):Int {
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		out.value = a.providers([for (c in a.items(n)) if (c.selected) c.id]);
		return S_OK;
	}

	@:hxmc.callback static function canSelectMultiple(self:Ptr, out:Ptr<Int32>):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		out.value = n.multiselectable ? 1 : 0;
		return S_OK;
	}

	@:hxmc.callback static function selectionRequired(self:Ptr, out:Ptr<Int32>):Int {
		out.value = 0;
		return S_OK;
	}

	@:hxmc.callback static function scrollIntoView(self:Ptr):Int
		return act(self, ScrollIntoView);

	@:hxmc.callback static function gridItem(self:Ptr, row:Int, col:Int, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		var c = a.tree.cellAt(n.id, row, col);
		return c == null ? E_INVALIDARG : give(a.block(c.id), 0, out);
	}

	static function intOut(self:Ptr, out:Ptr<Int32>, f:AccessNode->Int):Int {
		var n = node(self);
		if (n == null) return NOT_AVAILABLE;
		out.value = f(n);
		return S_OK;
	}

	@:hxmc.callback static function gridRows(self:Ptr, out:Ptr<Int32>):Int
		return intOut(self, out, n -> n.rowCount);

	@:hxmc.callback static function gridColumns(self:Ptr, out:Ptr<Int32>):Int
		return intOut(self, out, n -> n.colCount);

	@:hxmc.callback static function itemRow(self:Ptr, out:Ptr<Int32>):Int
		return intOut(self, out, n -> n.rowIndex);

	@:hxmc.callback static function itemColumn(self:Ptr, out:Ptr<Int32>):Int
		return intOut(self, out, n -> n.colIndex);

	@:hxmc.callback static function itemSpan(self:Ptr, out:Ptr<Int32>):Int
		return intOut(self, out, n -> 1);

	@:hxmc.callback static function containingGrid(self:Ptr, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		var t = a.tree.ancestor(n.id, Table, a.parents);
		return t == 0 ? S_OK : give(a.block(t), 0, out);
	}

	@:hxmc.callback static function rowHeaders(self:Ptr, out:Ptr<Ptr>):Int {
		var a = adapter(self);
		if (a == null || node(self) == null) return NOT_AVAILABLE;
		out.value = a.providers([]);
		return S_OK;
	}

	@:hxmc.callback static function columnHeaders(self:Ptr, out:Ptr<Ptr>):Int {
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		var hs = [];
		for (c in 0...n.colCount) {
			var h = a.tree.columnHeader(n.id, c);
			if (h != null) hs.push(h.id);
		}
		out.value = a.providers(hs);
		return S_OK;
	}

	@:hxmc.callback static function rowMajor(self:Ptr, out:Ptr<Int32>):Int {
		out.value = 0; // RowOrColumnMajor_RowMajor
		return S_OK;
	}

	@:hxmc.callback static function itemColumnHeaders(self:Ptr, out:Ptr<Ptr>):Int {
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		var t = a.tree.ancestor(n.id, Table, a.parents), h = t == 0 ? null : a.tree.columnHeader(t, n.colIndex);
		out.value = a.providers(h == null ? [] : [h.id]);
		return S_OK;
	}

	// --- text: ITextProvider, its ranges (UTF-16 units) ---

	// the range blocks: the vtable, the node's id, start, end, the reference count
	function range(id:Int, start:Int, end:Int):Ptr {
		var r:Ptr = LibC.malloc(40);
		(r : Ptr<Ptr>).value = rangeTable;
		(r.add(8) : Ptr<Int64>).value = id;
		(r.add(16) : Ptr<Int64>).value = start;
		(r.add(24) : Ptr<Int64>).value = end;
		(r.add(32) : Ptr<Int64>).value = 1;
		byBlock.set(key(r), this);
		return r;
	}

	static inline function rId(r:Ptr):Int
		return (r.add(8) : Ptr<Int64>).value.toInt();

	static inline function rStart(r:Ptr):Int
		return (r.add(16) : Ptr<Int64>).value.toInt();

	static inline function rEnd(r:Ptr):Int
		return (r.add(24) : Ptr<Int64>).value.toInt();

	static function rSet(r:Ptr, start:Int, end:Int) {
		(r.add(16) : Ptr<Int64>).value = start;
		(r.add(24) : Ptr<Int64>).value = end;
	}

	// a range's node and its text (null: gone)
	static function rNode(r:Ptr):Null<{a:WinAccess, n:AccessNode, text:String}> {
		var a = byBlock.get(key(r));
		if (a == null || a.tree == null) return null;
		var n = a.tree.nodes.get(rId(r));
		return n == null ? null : {a: a, n: n, text: n.value ?? ""};
	}

	@:hxmc.callback static function textSelection(self:Ptr, out:Ptr<Ptr>):Int {
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		var len = (n.value ?? "").length;
		var s = n.textStart < 0 ? len : n.textStart, e = n.textEnd < 0 ? len : n.textEnd;
		out.value = a.ranges([a.range(n.id, s, e)]);
		return S_OK;
	}

	// an array of ranges (VT_UNKNOWN: referenced by it; ours released)
	function ranges(rs:Array<Ptr>):Ptr {
		var sa = OleAut.SafeArrayCreateVector(13, 0, rs.length);
		Arena.scoped(a -> {
			var i:Ptr<Int32> = a.alloc(4);
			for (k in 0...rs.length) {
				i.value = k;
				OleAut.SafeArrayPutElement(sa, i, rs[k]);
				releaseRange(rs[k]);
			}
		});
		return sa;
	}

	@:hxmc.callback static function visibleRanges(self:Ptr, out:Ptr<Ptr>):Int {
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		out.value = a.ranges([a.range(n.id, 0, (n.value ?? "").length)]);
		return S_OK;
	}

	@:hxmc.callback static function rangeFromChild(self:Ptr, child:Ptr, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		return E_INVALIDARG;
	}

	// (the point: a UiaPoint, two doubles, passed by address)
	@:hxmc.callback static function rangeFromPoint(self:Ptr, point:Ptr<Float>, out:Ptr<Ptr>):Int {
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		var s = n.value ?? "", at = s.length;
		for (i in 0...s.length) {
			var b = a.charBox(n, s, i, i + 1);
			if (point[0] >= b[0] && point[0] < b[0] + b[2] && point[1] >= b[1] && point[1] < b[1] + b[3]) {
				at = i;
				break;
			}
		}
		out.value = a.range(n.id, at, at);
		return S_OK;
	}

	@:hxmc.callback static function documentRange(self:Ptr, out:Ptr<Ptr>):Int {
		var a = adapter(self), n = node(self);
		if (a == null || n == null) return NOT_AVAILABLE;
		out.value = a.range(n.id, 0, (n.value ?? "").length);
		return S_OK;
	}

	@:hxmc.callback static function supportedSelection(self:Ptr, out:Ptr<Int32>):Int {
		out.value = 1; // SupportedTextSelection_Single
		return S_OK;
	}

	// a range of the text's box on the screen (an estimate: the node's box
	// shared out by the characters of its line, lines by the line breaks)
	function charBox(n:AccessNode, s:String, from:Int, to:Int):Array<Float> {
		var e = screenRect(n);
		var lines = helder.ui.access.TextUnits.pieces(s, Line), line = 0;
		for (i in 0...lines.length)
			if (from >= lines[i][0] && (from < lines[i][1] || i == lines.length - 1)) {
				line = i;
				break;
			}
		var l = lines[line], len = Math.max(1, l[1] - l[0]), h = e[3] / lines.length;
		var x0 = e[0] + e[2] * (from - l[0]) / len, x1 = e[0] + e[2] * Math.min(to - l[0], len) / len;
		return [x0, e[1] + h * line, Math.max(0, x1 - x0), h];
	}

	static function releaseRange(r:Ptr):Int {
		var refs:Ptr<Int64> = r.add(32);
		var n = refs.value.toInt() - 1;
		refs.value = n;
		if (n == 0) {
			byBlock.remove(key(r));
			LibC.free(r);
		}
		return n;
	}

	@:hxmc.callback static function rangeQuery(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int {
		if (out.isNull()) return E_INVALIDARG;
		var g = guid(iid);
		if (g != IID_UNKNOWN && g != IID_RANGE) {
			out.value = Ptr.nil();
			return E_NOINTERFACE;
		}
		rangeAddRef(self);
		out.value = self;
		return S_OK;
	}

	@:hxmc.callback static function rangeAddRef(self:Ptr):Int {
		var refs:Ptr<Int64> = self.add(32);
		var n = refs.value.toInt() + 1;
		refs.value = n;
		return n;
	}

	@:hxmc.callback static function rangeRelease(self:Ptr):Int
		return releaseRange(self);

	@:hxmc.callback static function rClone(self:Ptr, out:Ptr<Ptr>):Int {
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		out.value = r.a.range(rId(self), rStart(self), rEnd(self));
		return S_OK;
	}

	@:hxmc.callback static function rCompare(self:Ptr, other:Ptr, out:Ptr<Int32>):Int {
		out.value = !other.isNull() && rId(other) == rId(self) && rStart(other) == rStart(self) && rEnd(other) == rEnd(self) ? 1 : 0;
		return S_OK;
	}

	static inline function endpoint(r:Ptr, which:Int):Int
		return which == 0 ? rStart(r) : rEnd(r);

	@:hxmc.callback static function rCompareEndpoints(self:Ptr, which:Int, other:Ptr, otherWhich:Int, out:Ptr<Int32>):Int {
		if (other.isNull()) return E_INVALIDARG;
		out.value = endpoint(self, which) - endpoint(other, otherWhich);
		return S_OK;
	}

	// (TextUnit: Character, Format, Word, Line, Paragraph, Page, Document;
	// Format and Page as the whole, the next unit we have)
	static function unitOf(u:Int):helder.ui.access.TextUnits.TextUnit
		return switch u {
			case 0: Character;
			case 2: Word;
			case 3: Line;
			case 4: Paragraph;
			case _: Document;
		}

	@:hxmc.callback static function rExpand(self:Ptr, unit:Int):Int {
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		var p = helder.ui.access.TextUnits.at(r.text, rStart(self), unitOf(unit));
		rSet(self, p[0], p[1]);
		return S_OK;
	}

	@:hxmc.callback static function rFindAttribute(self:Ptr, attr:Int, value:Ptr, backward:Int, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		return S_OK;
	}

	@:hxmc.callback static function rFindText(self:Ptr, text:Ptr, backward:Int, ignoreCase:Int, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		var s = r.text.substring(rStart(self), rEnd(self)), t = string(text);
		if (ignoreCase != 0) {
			s = s.toLowerCase();
			t = t.toLowerCase();
		}
		var i = backward != 0 ? s.lastIndexOf(t) : s.indexOf(t);
		if (i >= 0 && t != "") out.value = r.a.range(rId(self), rStart(self) + i, rStart(self) + i + t.length);
		return S_OK;
	}

	@:hxmc.callback static function rAttribute(self:Ptr, attr:Int, v:Ptr):Int {
		clear(v);
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		if (attr == 40015) bool(v, r.n.readOnly) // IsReadOnly
		else Arena.scoped(a -> {
			// (the attributes we have none of: UI Automation's "not supported")
			var u:Ptr<Ptr> = a.alloc(8);
			Uia.UiaGetReservedNotSupportedValue(u);
			(v : Ptr<UInt16>).value = 13; // VT_UNKNOWN
			(v.add(8) : Ptr<Ptr>).value = u.value;
		});
		return S_OK;
	}

	@:hxmc.callback static function rRectangles(self:Ptr, out:Ptr<Ptr>):Int {
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		var s = r.text, from = rStart(self), to = rEnd(self), boxes = [];
		for (l in helder.ui.access.TextUnits.pieces(s, Line)) {
			var a = Std.int(Math.max(from, l[0])), b = Std.int(Math.min(to, l[1]));
			if (a < b || (from == to && from >= l[0] && from <= l[1] && boxes.length == 0)) boxes.push(r.a.charBox(r.n, s, a, Std.int(Math.max(a, b))));
		}
		var sa = OleAut.SafeArrayCreateVector(5, 0, boxes.length * 4);
		Arena.scoped(m -> {
			var i:Ptr<Int32> = m.alloc(4), d:Ptr<Float> = m.alloc(8);
			for (k in 0...boxes.length)
				for (j in 0...4) {
					i.value = k * 4 + j;
					d.value = boxes[k][j];
					OleAut.SafeArrayPutElement(sa, i, d);
				}
		});
		out.value = sa;
		return S_OK;
	}

	@:hxmc.callback static function rEnclosing(self:Ptr, out:Ptr<Ptr>):Int {
		out.value = Ptr.nil();
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		return give(r.a.block(r.n.id), 0, out);
	}

	@:hxmc.callback static function rText(self:Ptr, max:Int, out:Ptr<Ptr>):Int {
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		var s = r.text.substring(rStart(self), rEnd(self));
		if (max >= 0 && s.length > max) s = s.substr(0, max);
		out.value = bstr(s);
		return S_OK;
	}

	@:hxmc.callback static function rMove(self:Ptr, unit:Int, count:Int, out:Ptr<Int32>):Int {
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		var m = helder.ui.access.TextUnits.move(r.text, rStart(self), rEnd(self), unitOf(unit), count);
		rSet(self, m.start, m.end);
		out.value = m.moved;
		return S_OK;
	}

	@:hxmc.callback static function rMoveEndpoint(self:Ptr, which:Int, unit:Int, count:Int, out:Ptr<Int32>):Int {
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		var m = helder.ui.access.TextUnits.moveBoundary(r.text, endpoint(self, which), unitOf(unit), count);
		var s = rStart(self), e = rEnd(self);
		if (which == 0) {
			s = m.at;
			if (e < s) e = s;
		} else {
			e = m.at;
			if (s > e) s = e;
		}
		rSet(self, s, e);
		out.value = m.moved;
		return S_OK;
	}

	@:hxmc.callback static function rMoveEndpointByRange(self:Ptr, which:Int, other:Ptr, otherWhich:Int):Int {
		if (other.isNull()) return E_INVALIDARG;
		var at = endpoint(other, otherWhich), s = rStart(self), e = rEnd(self);
		if (which == 0) {
			s = at;
			if (e < s) e = s;
		} else {
			e = at;
			if (s > e) s = e;
		}
		rSet(self, s, e);
		return S_OK;
	}

	@:hxmc.callback static function rSelect(self:Ptr):Int {
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		return r.a.ui.accessAction(r.n.id, SetSelection, rStart(self) + "," + rEnd(self)) ? S_OK : INVALID_OPERATION;
	}

	@:hxmc.callback static function rInvalid(self:Ptr):Int
		return INVALID_OPERATION;

	@:hxmc.callback static function rScroll(self:Ptr, alignToTop:Int):Int {
		var r = rNode(self);
		if (r == null) return NOT_AVAILABLE;
		return r.a.ui.accessAction(r.n.id, ScrollIntoView) ? S_OK : E_FAIL;
	}

	@:hxmc.callback static function rChildren(self:Ptr, out:Ptr<Ptr>):Int {
		out.value = OleAut.SafeArrayCreateVector(13, 0, 0);
		return S_OK;
	}
}

@:hxmc.c @:hxmc.lib("uiautomationcore") extern class Uia {
	static function UiaReturnRawElementProvider(hwnd:Ptr, wParam:Int64, lParam:Int64, provider:Ptr):Int64;
	static function UiaHostProviderFromHwnd(hwnd:Ptr, out:Ptr<Ptr>):Int;
	static function UiaRaiseAutomationEvent(provider:Ptr, id:Int):Int;
	// (the VARIANTs by address: Windows x64 passes a struct of 24 bytes so)
	static function UiaRaiseAutomationPropertyChangedEvent(provider:Ptr, id:Int, oldValue:Ptr, newValue:Ptr):Int;
	static function UiaRaiseStructureChangedEvent(provider:Ptr, type:Int, runtimeId:Ptr<Int32>, length:Int):Int;
	static function UiaDisconnectProvider(provider:Ptr):Int;
	static function UiaGetReservedNotSupportedValue(out:Ptr<Ptr>):Int;
	static function UiaClientsAreListening():Int;
}

@:hxmc.c @:hxmc.lib("oleaut32") extern class OleAut {
	static function SysAllocStringLen(s:Ptr, length:Int):Ptr;
	static function SafeArrayCreateVector(vt:Int, lower:Int, count:Int):Ptr;
	static function SafeArrayPutElement(array:Ptr, index:Ptr<Int32>, value:Ptr):Int;
	static function VariantClear(v:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("ole32") extern class Ole32 {
	static function CoInitializeEx(reserved:Ptr, flags:Int):Int;
}
