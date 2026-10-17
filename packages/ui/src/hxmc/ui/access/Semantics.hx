package hxmc.ui.access;

// What a node declares about itself for assistive technology (Node.semantics;
// in markup, the attributes role, label, description, checked, selected,
// expanded, level, disabled, value-now, value-min, value-max, value-text,
// hidden). Unset
// fields say nothing: a TextNode is a Label of its text, an ImageNode an
// Image, a focusable node a Group.
@:structInit class Semantics {
	public var role(default, set):Null<Role> = null;
	// the name (else from the contents' text, for the roles named by content)
	public var label(default, set):Null<String> = null;
	public var description(default, set):Null<String> = null;
	public var checked(default, set):Null<Bool> = null;
	// a checkbox neither checked nor not (ARIA's checked="mixed"; markup: checked="mixed")
	public var mixed(default, set):Bool = false;
	public var selected(default, set):Null<Bool> = null;
	public var expanded(default, set):Null<Bool> = null;
	// a tree item's depth (from 1)
	public var level(default, set):Null<Int> = null;
	public var disabled(default, set):Bool = false;
	// a range's value (Slider, ProgressIndicator) and bounds, and its text
	public var valueNow(default, set):Null<Float> = null;
	public var valueMin(default, set):Null<Float> = null;
	public var valueMax(default, set):Null<Float> = null;
	public var valueText(default, set):Null<String> = null;
	// left out with its subtree (decoration)
	public var hidden(default, set):Bool = false;

	// (a change: the accessibility trees built again)
	function set_role(v:Null<Role>):Null<Role> {
		if (v != role) hxmc.ui.Ui.accessEpoch++;
		return role = v;
	}

	function set_label(v:Null<String>):Null<String> {
		if (v != label) hxmc.ui.Ui.accessEpoch++;
		return label = v;
	}

	function set_description(v:Null<String>):Null<String> {
		if (v != description) hxmc.ui.Ui.accessEpoch++;
		return description = v;
	}

	function set_checked(v:Null<Bool>):Null<Bool> {
		if (v != checked) hxmc.ui.Ui.accessEpoch++;
		return checked = v;
	}

	function set_mixed(v:Bool):Bool {
		if (v != mixed) hxmc.ui.Ui.accessEpoch++;
		return mixed = v;
	}

	function set_selected(v:Null<Bool>):Null<Bool> {
		if (v != selected) hxmc.ui.Ui.accessEpoch++;
		return selected = v;
	}

	function set_expanded(v:Null<Bool>):Null<Bool> {
		if (v != expanded) hxmc.ui.Ui.accessEpoch++;
		return expanded = v;
	}

	function set_level(v:Null<Int>):Null<Int> {
		if (v != level) hxmc.ui.Ui.accessEpoch++;
		return level = v;
	}

	function set_disabled(v:Bool):Bool {
		if (v != disabled) hxmc.ui.Ui.accessEpoch++;
		return disabled = v;
	}

	function set_valueNow(v:Null<Float>):Null<Float> {
		if (v != valueNow) hxmc.ui.Ui.accessEpoch++;
		return valueNow = v;
	}

	function set_valueMin(v:Null<Float>):Null<Float> {
		if (v != valueMin) hxmc.ui.Ui.accessEpoch++;
		return valueMin = v;
	}

	function set_valueMax(v:Null<Float>):Null<Float> {
		if (v != valueMax) hxmc.ui.Ui.accessEpoch++;
		return valueMax = v;
	}

	function set_valueText(v:Null<String>):Null<String> {
		if (v != valueText) hxmc.ui.Ui.accessEpoch++;
		return valueText = v;
	}

	function set_hidden(v:Bool):Bool {
		if (v != hidden) hxmc.ui.Ui.accessEpoch++;
		return hidden = v;
	}
}
