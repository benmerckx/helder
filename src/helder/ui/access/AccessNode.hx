package helder.ui.access;

// A node of the accessibility tree as AccessTree builds it: what a screen
// reader sees of one Node (its id stays the node's), with its children's ids
@:structInit class AccessNode {
	public var id:Int;
	public var role:Role;
	public var name:String = "";
	public var description:Null<String> = null;
	public var href:Null<String> = null;
	// a text input's text (a password's: dots)
	public var value:Null<String> = null;
	// a password field (Semantics.secret)
	public var secret:Bool = false;
	public var checked:Null<Bool> = null;
	// checked neither way (Semantics.mixed)
	public var mixed:Bool = false;
	public var selected:Null<Bool> = null;
	public var multiselectable:Bool = false;
	// the current one of a set (Semantics.current)
	public var current:Bool = false;
	public var expanded:Null<Bool> = null;
	public var level:Null<Int> = null;
	public var disabled:Bool = false;
	public var focusable:Bool = false;
	public var valueNow:Null<Float> = null;
	public var valueMin:Null<Float> = null;
	public var valueMax:Null<Float> = null;
	public var valueText:Null<String> = null;
	// a live region (Semantics.live) and its text, as announced when it changes
	public var live:Live = Off;
	public var liveText:Null<String> = null;
	// the box in window pixels
	public var x:Float = 0;
	public var y:Float = 0;
	public var width:Float = 0;
	public var height:Float = 0;
	// a text input's selection and caret (UTF-16 indices; -1: not a text
	// input), whether it is read only
	public var textStart:Int = -1;
	public var textEnd:Int = -1;
	public var caret:Int = -1;
	public var readOnly:Bool = false;
	// an item's place in its set, from 1, and the set's size (0: none): a
	// list's items, a tab list's tabs, a radio group's, a menu's, a tree's
	// items of a level (AccessTree counts them)
	public var posInSet:Int = 0;
	public var setSize:Int = 0;
	// a table's rows and columns; a row's and a cell's place in it, from 0
	// (-1: none; AccessTree counts them)
	public var rowCount:Int = 0;
	public var colCount:Int = 0;
	public var rowIndex:Int = -1;
	public var colIndex:Int = -1;
	public var children:Array<Int> = [];

	// the same as another (an incremental update leaves it out)
	public function equals(o:AccessNode):Bool {
		if (o.role != role || o.name != name || o.description != description || o.href != href || o.value != value || o.secret != secret || o.checked != checked || o.mixed != mixed || o.selected != selected
			|| o.multiselectable != multiselectable || o.current != current || o.live != live || o.liveText != liveText
			|| o.expanded != expanded || o.level != level || o.disabled != disabled || o.focusable != focusable || o.valueNow != valueNow || o.valueMin != valueMin
			|| o.valueMax != valueMax || o.valueText != valueText || o.x != x || o.y != y || o.width != width || o.height != height
			|| o.textStart != textStart || o.textEnd != textEnd || o.caret != caret || o.readOnly != readOnly || o.posInSet != posInSet
			|| o.setSize != setSize || o.rowCount != rowCount || o.colCount != colCount || o.rowIndex != rowIndex || o.colIndex != colIndex
			|| o.children.length != children.length)
			return false;
		for (i in 0...children.length)
			if (o.children[i] != children[i]) return false;
		return true;
	}

	// whether assistive technology's actions reach it as a click: a button,
	// a toggle, an item chosen
	public function pressable():Bool
		return switch role {
			case Button | CheckBox | Switch | RadioButton | Tab | Link | MenuItem | MenuItemCheckBox | MenuItemRadio | ListBoxOption | ComboBox | TreeItem: !disabled;
			case ListItem | Row | Cell: focusable && !disabled;
			case _: false;
		}

	// whether it toggles (checked or not)
	public function toggles():Bool
		return checked != null && (role == CheckBox || role == Switch || role == MenuItemCheckBox || role == Button);

	// a text input, or a combobox or spin button typed in (it has a value: its text)
	public function editable():Bool
		return role == TextInput || role == MultilineTextInput || ((role == ComboBox || role == SpinButton) && value != null);

	// as JSON's fields (the browser adapter's format): unset ones left out
	public function toJson():Dynamic {
		var o:Dynamic = {id: id, role: role.aria(), name: name, x: x, y: y, w: width, h: height, children: children};
		if (description != null) o.description = description;
		if (href != null) o.href = href;
		if (value != null) o.value = value;
		if (secret) o.secret = true;
		if (checked != null) o.checked = mixed ? "mixed" : checked;
		if (selected != null) o.selected = selected;
		if (multiselectable) o.multiselectable = true;
		if (current) o.current = true;
		if (expanded != null) o.expanded = expanded;
		if (level != null) o.level = level;
		if (disabled) o.disabled = true;
		if (focusable) o.focusable = true;
		if (valueNow != null) o.valueNow = valueNow;
		if (valueMin != null) o.valueMin = valueMin;
		if (valueMax != null) o.valueMax = valueMax;
		if (valueText != null) o.valueText = valueText;
		if (live != Off) o.live = live.aria();
		if (role == MultilineTextInput) o.multiline = true;
		if (readOnly) o.readOnly = true;
		if (textStart >= 0) {
			o.textStart = textStart;
			o.textEnd = textEnd;
		}
		if (setSize > 0) {
			o.posInSet = posInSet;
			o.setSize = setSize;
		}
		if (role == Table) {
			o.rowCount = rowCount;
			o.colCount = colCount;
		}
		if (rowIndex >= 0) o.rowIndex = rowIndex;
		if (colIndex >= 0) o.colIndex = colIndex;
		return o;
	}
}
